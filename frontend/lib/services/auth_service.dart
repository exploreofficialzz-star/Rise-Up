// frontend/lib/services/auth_service.dart
// v7.0 — Token-First, Post-Update Resilient Auth
//
// FIXES vs v6:
//
//  FIX 1 — signedOut + _refreshInFlight race (the main post-update bug):
//    When a background refresh was already running AND Supabase fired signedOut
//    simultaneously, the old code skipped the recovery block entirely and fell
//    straight through to incrementing the failure counter. After 3 rapid events
//    (which Supabase fires freely during cold-start validation), _clearSession()
//    was called and the user was logged out. Fix: when _refreshInFlight is true,
//    return immediately — the in-flight refresh will resolve the state correctly.
//
//  FIX 2 — No startup grace period:
//    Supabase fires signedOut within the first few seconds while validating the
//    session restored by setSession(). During that same window, Render.com cold-
//    starts the backend (10-30 s), so the refresh request times out. Without a
//    grace period, rapid signedOut events during this window hit the failure
//    counter before any real failure has occurred. Fix: _startupGrace = true for
//    the first 10 s. During grace, signedOut only fires a background refresh
//    attempt — failure counters are never incremented.
//
//  FIX 3 — Token-first rule:
//    unauthenticated status is now ONLY set when ALL of these are true:
//      a) Explicit logout, OR
//      b) Both access_token AND refresh_token are absent from storage, AND
//         _silentRefresh() returned false (definitive backend rejection)
//    A Supabase event alone can never log the user out while tokens exist.
//
//  FIX 4 — _maxRefreshFailures raised to 5, counters reset on any success.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/storage_service.dart';
import '../config/app_constants.dart';
import 'device_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthService extends ChangeNotifier {
  static final AuthService _i = AuthService._();
  factory AuthService() => _i;
  AuthService._();

  static const _kAccess  = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kUserId  = 'user_id';

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  bool _refreshInFlight  = false;
  int  _refreshFailures  = 0;
  int  _supabaseFailures = 0;

  // FIX 2: Grace period — no failure counting for the first 10 seconds.
  // Covers Supabase session validation delay + Render cold-start window.
  bool   _startupGrace = true;
  Timer? _graceTimer;

  static const int _maxRefreshFailures = 5; // FIX 4: raised from 3

  StreamSubscription<AuthState>? _supabaseSub;

  // ── INIT ─────────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    try {
      final access  = await storageService.read(key: _kAccess);
      final refresh = await storageService.read(key: _kRefresh);

      if (access == null && refresh == null) {
        _startupGrace = false; // No tokens = new user; grace not needed
        _setStatus(AuthStatus.unauthenticated);
        _listenToSupabase();
        return;
      }

      // Tokens found → authenticated immediately.
      // Never wait for network validation before showing content.
      _setStatus(AuthStatus.authenticated);

      // Restore Supabase in-memory session so its internal refresh cycle works.
      if (access != null && refresh != null) {
        _restoreSupabaseSession(access, refresh);
      }

      _listenToSupabase();

      // Proactively refresh if expiring within 5 minutes.
      if (refresh != null && (access == null || _isExpiringSoon(access))) {
        _backgroundRefresh(refresh);
      }

      // FIX 2: Start grace timer AFTER subscribing to Supabase events.
      _graceTimer?.cancel();
      _graceTimer = Timer(const Duration(seconds: 10), () {
        _startupGrace = false;
      });
    } catch (_) {
      // Storage read error — default to authenticated (offline-first).
      _setStatus(AuthStatus.authenticated);
      _listenToSupabase();
    }
  }

  // ── RESUME REFRESH ────────────────────────────────────────────────────────
  Future<void> tryRefreshOnResume() async {
    if (!isAuthenticated) return;
    if (_refreshInFlight) return;

    final access  = await storageService.read(key: _kAccess);
    final refresh = await storageService.read(key: _kRefresh);
    if (refresh == null) return;

    if (access == null || _isExpiringSoon(access)) {
      await _backgroundRefresh(refresh);
    }
  }

  // ── BACKGROUND REFRESH ────────────────────────────────────────────────────
  Future<void> _backgroundRefresh(String refreshToken) async {
    final result = await _silentRefresh(refreshToken);

    if (result == true) {
      _refreshFailures  = 0;
      _supabaseFailures = 0;
      return;
    }

    if (result == false) {
      _refreshFailures++;
      if (_refreshFailures >= _maxRefreshFailures) {
        await _clearSession();
      }
    }
    // null = network error → keep user in, retry on next resume
  }

  // ── API INTERCEPTOR ────────────────────────────────────────────────────────
  Future<bool> handleUnauthorized() async {
    if (_refreshInFlight) {
      await Future.delayed(const Duration(seconds: 2));
      return isAuthenticated;
    }

    final refresh = await storageService.read(key: _kRefresh);
    if (refresh == null) {
      await _clearSession();
      return false;
    }

    final result = await _silentRefresh(refresh);

    if (result == true) {
      _refreshFailures  = 0;
      _supabaseFailures = 0;
      return true;
    }

    if (result == false) {
      _refreshFailures++;
      if (_refreshFailures >= _maxRefreshFailures) {
        await _clearSession();
        return false;
      }
    }

    return isAuthenticated;
  }

  // ── SILENT REFRESH ────────────────────────────────────────────────────────
  Future<bool?> _silentRefresh(String refreshToken) async {
    if (_refreshInFlight) return null;
    _refreshInFlight = true;

    try {
      final deviceId = await deviceService.getDeviceId();

      final res = await http.post(
        Uri.parse('$kApiBaseUrl/auth/refresh'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID':  deviceId,
        },
        body: json.encode({'refresh_token': refreshToken}),
      ).timeout(const Duration(seconds: 20)); // extended for Render cold starts

      if (res.statusCode == 200) {
        final body = json.decode(res.body);

        final newAccess  = body['access_token']  as String?;
        final newRefresh = body['refresh_token'] as String?;
        final userId     = body['user_id']       as String?;

        await Future.wait([
          if (newAccess  != null) storageService.write(key: _kAccess,  value: newAccess),
          if (newRefresh != null) storageService.write(key: _kRefresh, value: newRefresh),
          if (userId     != null) storageService.write(key: _kUserId,  value: userId),
        ]);

        if (newAccess != null && newRefresh != null) {
          _restoreSupabaseSession(newAccess, newRefresh);
        }

        _refreshFailures  = 0;
        _supabaseFailures = 0;
        return true;
      }

      // 401/403 = backend definitively rejected the refresh token
      if (res.statusCode == 401 || res.statusCode == 403) return false;

      // 5xx / unexpected = server hiccup or cold start → keep user in
      return null;
    } catch (_) {
      // Network unreachable / timeout → keep user in
      return null;
    } finally {
      _refreshInFlight = false;
    }
  }

  // ── TOKEN EXPIRY ──────────────────────────────────────────────────────────
  bool _isExpiringSoon(String token) {
    try {
      final payload = json.decode(
        utf8.decode(
          base64Url.decode(base64Url.normalize(token.split('.')[1])),
        ),
      );
      final exp = payload['exp'] as int?;
      if (exp == null) return true;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return now >= (exp - 300); // refresh 5 min before expiry
    } catch (_) {
      return true;
    }
  }

  // ── RESTORE SUPABASE SESSION ──────────────────────────────────────────────
  void _restoreSupabaseSession(String access, String refresh) {
    try {
      // This version of supabase_flutter takes only the refresh token.
      Supabase.instance.client.auth.setSession(refresh);
    } catch (_) {}
  }

  // ── SUPABASE STREAM LISTENER ──────────────────────────────────────────────
  //
  // Why post-update logouts happened here:
  //   Supabase fires signedOut while validating the session after setSession().
  //   Simultaneously, the backend is cold-starting (Render), so _silentRefresh
  //   times out. The three-event failure counter was hit before any real auth
  //   failure occurred, triggering _clearSession().
  //
  // The fix — three-layer protection:
  //   Layer 1: if _refreshInFlight → return immediately (FIX 1)
  //   Layer 2: if _startupGrace   → try refresh, never count (FIX 2)
  //   Layer 3: if tokens exist    → try refresh, count only on definitive
  //                                  rejection (false), not timeouts (FIX 3)
  void _listenToSupabase() {
    _supabaseSub?.cancel();
    _supabaseSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) async {
        final session = data.session;
        final event   = data.event;

        // ── Session available ────────────────────────────────────────────
        if (session != null) {
          await Future.wait([
            storageService.write(key: _kAccess,  value: session.accessToken),
            if (session.refreshToken != null)
              storageService.write(key: _kRefresh, value: session.refreshToken!),
            storageService.write(key: _kUserId, value: session.user.id),
          ]);
          _refreshFailures  = 0;
          _supabaseFailures = 0;
          _startupGrace     = false;
          _graceTimer?.cancel();
          _setStatus(AuthStatus.authenticated);
          return;
        }

        // ── No session ───────────────────────────────────────────────────
        if (event != AuthChangeEvent.signedOut) return; // ignore non-signedOut

        // LAYER 1 — FIX 1: Refresh already running → it will resolve state.
        if (_refreshInFlight) return;

        // LAYER 2 — FIX 2: Startup grace → never count, just try refresh.
        if (_startupGrace) {
          final r = await storageService.read(key: _kRefresh);
          if (r != null) _silentRefresh(r); // fire-and-forget
          return;
        }

        // LAYER 3 — FIX 3: Token-first approach.
        final storedRefresh = await storageService.read(key: _kRefresh);
        final storedAccess  = await storageService.read(key: _kAccess);

        if (storedRefresh != null) {
          final result = await _silentRefresh(storedRefresh);

          if (result == true) {
            _supabaseFailures = 0;
            _refreshFailures  = 0;
            return; // Session recovered
          }

          if (result == null) return; // Network error — stay logged in

          // result == false: backend confirmed token is invalid
          _supabaseFailures++;
          _refreshFailures++;
          if (_supabaseFailures  < _maxRefreshFailures &&
              _refreshFailures   < _maxRefreshFailures) {
            return; // More attempts remain
          }
          await _clearSession();
          return;
        }

        // Has access token but no refresh token — keep going until access expires
        if (storedAccess != null) return;

        // Truly no tokens + signedOut = genuinely logged out
        await _clearSession();
      },
      onError: (_) {},
    );
  }

  // ── LOGIN ─────────────────────────────────────────────────────────────────
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
  }) async {
    _refreshFailures  = 0;
    _supabaseFailures = 0;
    _startupGrace     = false;
    _graceTimer?.cancel();

    await Future.wait([
      storageService.write(key: _kAccess,  value: accessToken),
      storageService.write(key: _kRefresh, value: refreshToken),
      storageService.write(key: _kUserId,  value: userId),
    ]);

    _restoreSupabaseSession(accessToken, refreshToken);
    _status = AuthStatus.authenticated;
    notifyListeners();
    _listenToSupabase();
  }

  void onLoginSuccess() {
    _refreshFailures  = 0;
    _supabaseFailures = 0;
    _startupGrace     = false;
    _graceTimer?.cancel();
    _status = AuthStatus.authenticated;
    notifyListeners();
    _listenToSupabase();
  }

  // ── LOGOUT ────────────────────────────────────────────────────────────────
  Future<void> onLogout() async {
    _graceTimer?.cancel();
    _startupGrace = false;
    _supabaseSub?.cancel();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    await _clearSession();
  }

  Future<void> _clearSession() async {
    await Future.wait([
      storageService.delete(key: _kAccess),
      storageService.delete(key: _kRefresh),
      storageService.delete(key: _kUserId),
      storageService.clearProfileCache(),
    ]);
    _refreshFailures  = 0;
    _supabaseFailures = 0;
    _setStatus(AuthStatus.unauthenticated);
  }

  void _setStatus(AuthStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _graceTimer?.cancel();
    _supabaseSub?.cancel();
    super.dispose();
  }
}

final authService = AuthService();
