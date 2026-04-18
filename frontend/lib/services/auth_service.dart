// frontend/lib/services/auth_service.dart
// v6.0 — Persistent login (Facebook/Instagram-style)
//
// FIXES vs v5:
//  FIX 1: Restore Supabase session on startup so its internal
//          auto-refresh fires correctly and doesn't trigger signedOut.
//  FIX 2: _listenToSupabase() no longer immediately clears session on
//          signedOut — it attempts a silent refresh first. Only clears
//          after _maxRefreshFailures consecutive unrecoverable failures.
//  FIX 3: _isExpiringSoon() replaces _isExpired() — proactive refresh
//          5 minutes before expiry instead of after.
//  FIX 4: saveSession() and _silentRefresh() also restore Supabase
//          session so the internal refresh cycle stays in sync.
//  FIX 5: tryRefreshOnResume() now actually called (main.dart wires it
//          via didChangeAppLifecycleState).

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

  bool _refreshInFlight = false;
  int  _refreshFailures = 0;
  static const int _maxRefreshFailures = 3;

  // Guard: only log out from Supabase signedOut AFTER we've tried and
  // failed to recover. Incremented on each unrecoverable signedOut.
  int _supabaseSignOutFailures = 0;

  StreamSubscription<AuthState>? _supabaseSub;

  // ── INIT ─────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    try {
      final access  = await storageService.read(key: _kAccess);
      final refresh = await storageService.read(key: _kRefresh);

      if (access == null && refresh == null) {
        _setStatus(AuthStatus.unauthenticated);
        _listenToSupabase();
        return;
      }

      // We have stored credentials — user is authenticated immediately.
      _setStatus(AuthStatus.authenticated);

      // FIX 1: Restore Supabase's in-memory session from our stored tokens.
      // Without this, Supabase has no session on every cold start, so its
      // internal refresh loop never runs, and it eventually fires signedOut.
      if (access != null && refresh != null) {
        _restoreSupabaseSession(access, refresh);
      }

      _listenToSupabase();

      // Proactively refresh if token is expiring within 5 minutes.
      if (refresh != null && (access == null || _isExpiringSoon(access))) {
        _backgroundRefresh(refresh);
      }
    } catch (_) {
      // Storage read error — assume authenticated so we don't force a logout.
      _setStatus(AuthStatus.authenticated);
      _listenToSupabase();
    }
  }

  // ── RESTORE SUPABASE SESSION ──────────────────────────────────────────
  // Silently push stored tokens into the Supabase client so it can manage
  // its own refresh cycle. Called on cold start and after every refresh.
  // setSession() in this supabase_flutter version takes only the refresh token.
  // Supabase will exchange it internally and restore the full session.
  void _restoreSupabaseSession(String access, String refresh) {
    try {
      Supabase.instance.client.auth.setSession(refresh);
    } catch (_) {
      // Tokens may be expired — background refresh handles it.
    }
  }

  // ── RESUME REFRESH ────────────────────────────────────────────────────
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

  // ── BACKGROUND REFRESH ────────────────────────────────────────────────
  Future<void> _backgroundRefresh(String refreshToken) async {
    final result = await _silentRefresh(refreshToken);

    if (result == true) {
      _refreshFailures = 0;
      return;
    }

    if (result == false) {
      _refreshFailures++;
      if (_refreshFailures >= _maxRefreshFailures) {
        await _clearSession();
      }
    }
    // result == null means network error — keep user logged in, retry later.
  }

  // ── API INTERCEPTOR HANDLER ───────────────────────────────────────────
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
      _refreshFailures = 0;
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

  // ── SILENT REFRESH ────────────────────────────────────────────────────
  Future<bool?> _silentRefresh(String refreshToken) async {
    if (_refreshInFlight) return null;
    _refreshInFlight = true;

    try {
      final deviceId = await deviceService.getDeviceId();

      final res = await http.post(
        Uri.parse('$kApiBaseUrl/auth/refresh'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
        },
        body: json.encode({'refresh_token': refreshToken}),
      ).timeout(const Duration(seconds: 15));

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

        // FIX 4: Keep Supabase's in-memory session in sync with new tokens.
        if (newAccess != null && newRefresh != null) {
          _restoreSupabaseSession(newAccess, newRefresh);
        }

        _refreshFailures = 0;
        return true;
      }

      // Hard auth failure — refresh token is invalid/revoked.
      if (res.statusCode == 401 || res.statusCode == 403) {
        return false;
      }

      // Server error / network hiccup — don't log the user out.
      return null;
    } catch (_) {
      // Network unreachable — keep the user logged in.
      return null;
    } finally {
      _refreshInFlight = false;
    }
  }

  // ── TOKEN EXPIRY CHECKS ───────────────────────────────────────────────

  // FIX 3: Refresh proactively 5 minutes before expiry, not after.
  // This prevents the 1-second window where a request hits an expired token.
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
      return now >= (exp - 300); // 5-minute buffer
    } catch (_) {
      return true;
    }
  }

  // Kept for backward-compat callers; delegates to _isExpiringSoon.
  bool _isExpired(String token) => _isExpiringSoon(token);

  // ── SUPABASE SESSION SYNC ─────────────────────────────────────────────
  // FIX 2: The old code called _clearSession() immediately on signedOut.
  // Supabase fires signedOut when *its* internal JWT expires (~1 hr) and it
  // can't auto-refresh (e.g. network hiccup, or our tokens were restored but
  // Supabase hadn't refreshed its copy yet). The correct behaviour is:
  //   • session != null  → save the new/refreshed tokens, stay logged in
  //   • signedOut        → try our own silent refresh FIRST; only clear
  //                        session if that fails _maxRefreshFailures times
  //   • anything else    → ignore (initialSession with null, etc.)
  void _listenToSupabase() {
    _supabaseSub?.cancel();
    _supabaseSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) async {
        final session = data.session;
        final event   = data.event;

        if (session != null) {
          // Supabase refreshed or confirmed the session — persist the tokens.
          await Future.wait([
            storageService.write(key: _kAccess,  value: session.accessToken),
            if (session.refreshToken != null)
              storageService.write(key: _kRefresh, value: session.refreshToken!),
            storageService.write(key: _kUserId, value: session.user.id),
          ]);
          _refreshFailures       = 0;
          _supabaseSignOutFailures = 0;
          _setStatus(AuthStatus.authenticated);
          return;
        }

        // session == null below this point.

        if (event == AuthChangeEvent.signedOut) {
          // Don't trust this event blindly — Supabase fires it for network
          // hiccups too. Try our own refresh before giving up.
          if (!_refreshInFlight) {
            final storedRefresh = await storageService.read(key: _kRefresh);
            if (storedRefresh != null) {
              final result = await _silentRefresh(storedRefresh);
              if (result == true) {
                // Recovered — stay logged in.
                _supabaseSignOutFailures = 0;
                _refreshFailures        = 0;
                return;
              }
              if (result == null) {
                // Network error — don't log out, retry on next resume.
                return;
              }
            }
          }

          // result == false (or no refresh token) → genuine auth failure.
          _supabaseSignOutFailures++;
          _refreshFailures++;
          if (_supabaseSignOutFailures >= _maxRefreshFailures ||
              _refreshFailures        >= _maxRefreshFailures) {
            await _clearSession();
          }
          // Otherwise hold on — could be a transient failure.
        }

        // All other events with null session (e.g. initialSession with no
        // prior Supabase storage) are silently ignored.
      },
      onError: (_) {/* Supabase stream errors are non-fatal */},
    );
  }

  // ── LOGIN ─────────────────────────────────────────────────────────────
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
  }) async {
    _refreshFailures        = 0;
    _supabaseSignOutFailures = 0;

    await Future.wait([
      storageService.write(key: _kAccess,  value: accessToken),
      storageService.write(key: _kRefresh, value: refreshToken),
      storageService.write(key: _kUserId,  value: userId),
    ]);

    // FIX 4: Sync new login credentials into Supabase immediately.
    _restoreSupabaseSession(accessToken, refreshToken);

    _status = AuthStatus.authenticated;
    notifyListeners();

    _listenToSupabase();
  }

  void onLoginSuccess() {
    _refreshFailures        = 0;
    _supabaseSignOutFailures = 0;
    _status = AuthStatus.authenticated;
    notifyListeners();
    _listenToSupabase();
  }

  // ── LOGOUT ────────────────────────────────────────────────────────────
  Future<void> onLogout() async {
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
    _refreshFailures        = 0;
    _supabaseSignOutFailures = 0;
    _setStatus(AuthStatus.unauthenticated);
  }

  void _setStatus(AuthStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _supabaseSub?.cancel();
    super.dispose();
  }
}

final authService = AuthService();
