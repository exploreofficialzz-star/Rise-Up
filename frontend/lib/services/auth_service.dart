// frontend/lib/services/auth_service.dart
// v3.0 — Facebook/Instagram/YouTube persistent-session model
//
// Session lifecycle:
//  • Tokens stored on device and survive app restarts indefinitely
//  • On 401: silent refresh attempted FIRST — only logout if refresh is
//    explicitly rejected (401/403 from /auth/refresh)
//  • On network error: keep user logged in, retry next open
//  • On app resume: proactive background refresh if token expires in <5 min
//  • Explicit logout: clears tokens only, preserves device ID and all other
//    local data (preferences, cache, etc.)
//  • _clearSession NEVER calls deleteAll — only wipes auth tokens

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
  // ── Singleton ─────────────────────────────────────────────────────────
  static final AuthService _i = AuthService._();
  factory AuthService() => _i;
  AuthService._();

  // ── Storage keys ──────────────────────────────────────────────────────
  static const _kAccess  = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kUserId  = 'user_id';

  // ── State ─────────────────────────────────────────────────────────────
  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status      => _status;
  bool get isAuthenticated   => _status == AuthStatus.authenticated;
  bool get isUnauthenticated => _status == AuthStatus.unauthenticated;

  // Prevents concurrent refresh races (Dio retries + resume can collide)
  bool _refreshInFlight = false;

  StreamSubscription<AuthState>? _supabaseSub;

  // ── Boot ──────────────────────────────────────────────────────────────
  /// Called once in main() before runApp().
  ///
  /// Decision tree (Facebook/Instagram/YouTube model):
  ///   No tokens          → unauthenticated  (first install or after logout)
  ///   Valid token        → authenticated    (straight to home)
  ///   Expired token      → silent refresh
  ///     Refresh OK       → authenticated    (transparent to user)
  ///     Refresh revoked  → unauthenticated  (server explicitly rejected)
  ///     Network error    → authenticated    (offline-first: never punish)
  Future<void> initialize() async {
    try {
      final access  = await storageService.read(key: _kAccess);
      final refresh = await storageService.read(key: _kRefresh);

      // 1. No tokens — first install or post-explicit-logout
      if (access == null && refresh == null) {
        _setStatus(AuthStatus.unauthenticated);
        _listenToSupabase();
        return;
      }

      // 2. Valid access token — go straight home
      if (access != null && !_isTokenExpired(access)) {
        _setStatus(AuthStatus.authenticated);
        _listenToSupabase();
        // Proactively refresh in background if expiry is close
        _maybeProactiveRefresh(access, refresh);
        return;
      }

      // 3. Expired access token — attempt silent refresh
      if (refresh != null) {
        final result = await _silentRefresh(refresh);
        // null = network error → keep user logged in
        _setStatus(
          result == false
              ? AuthStatus.unauthenticated
              : AuthStatus.authenticated,
        );
        _listenToSupabase();
        return;
      }

      // 4. Expired access, no refresh token
      _setStatus(AuthStatus.unauthenticated);
    } catch (_) {
      // Storage failure — never lock user out; retry on next open
      _setStatus(AuthStatus.authenticated);
    }

    _listenToSupabase();
  }

  // ── Proactive background refresh ──────────────────────────────────────
  /// If the access token expires within 5 minutes, silently refresh it now
  /// so the user never hits a mid-session 401.
  void _maybeProactiveRefresh(String access, String? refresh) {
    if (refresh == null) return;
    try {
      final parts = access.split('.');
      if (parts.length != 3) return;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final exp = (json.decode(payload) as Map<String, dynamic>)['exp'] as int?;
      if (exp == null) return;
      final secondsLeft =
          exp - (DateTime.now().millisecondsSinceEpoch ~/ 1000);
      if (secondsLeft < 300) {
        // Fire-and-forget — don't await, don't change status on failure
        _silentRefresh(refresh).catchError((_) => null);
      }
    } catch (_) {}
  }

  /// Called by MainShell when the app returns to foreground.
  /// Refreshes token if it has expired or is about to expire.
  Future<void> tryRefreshOnResume() async {
    if (_status != AuthStatus.authenticated) return;
    if (_refreshInFlight) return;

    final access  = await storageService.read(key: _kAccess);
    final refresh = await storageService.read(key: _kRefresh);

    if (refresh == null) return;

    // Refresh if expired OR expiring within 5 minutes
    final shouldRefresh =
        access == null || _isTokenExpiredOrExpiringSoon(access, bufferSeconds: 300);

    if (shouldRefresh) {
      final result = await _silentRefresh(refresh);
      // Only log out if server explicitly rejected the refresh token
      if (result == false) {
        _setStatus(AuthStatus.unauthenticated);
      }
      // null (network error) or true → keep authenticated
    }
  }

  // ── Called by ApiService Dio interceptor ──────────────────────────────
  /// Invoked when a request receives a 401. Attempts a silent token refresh
  /// before giving up. Returns true if refresh succeeded (caller should
  /// retry the original request), false if the user must re-authenticate.
  Future<bool> handleUnauthorized() async {
    if (_refreshInFlight) {
      // Another refresh is already in progress — wait briefly then recheck
      await Future.delayed(const Duration(seconds: 2));
      return _status == AuthStatus.authenticated;
    }

    final refresh = await storageService.read(key: _kRefresh);
    if (refresh == null) {
      await _clearSession();
      return false;
    }

    final result = await _silentRefresh(refresh);

    if (result == true) {
      return true; // Caller retries request with new token
    }

    if (result == false) {
      // Server explicitly rejected — must re-authenticate
      await _clearSession();
      return false;
    }

    // null = network error — keep authenticated, don't force login
    return false;
  }

  // ── JWT helpers ───────────────────────────────────────────────────────

  /// Returns true if the token is expired (with 30-second race buffer).
  bool _isTokenExpired(String token) =>
      _isTokenExpiredOrExpiringSoon(token, bufferSeconds: 30);

  /// Returns true if the token is expired OR expires within [bufferSeconds].
  bool _isTokenExpiredOrExpiringSoon(String token,
      {required int bufferSeconds}) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final exp =
          (json.decode(payload) as Map<String, dynamic>)['exp'] as int?;
      if (exp == null) return false;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return now >= (exp - bufferSeconds);
    } catch (_) {
      return true;
    }
  }

  /// POST /auth/refresh — returns:
  ///   true  — refreshed OK, new tokens persisted
  ///   false — server explicitly rejected (401/403) → force login
  ///   null  — network/timeout error → keep user logged in
  Future<bool?> _silentRefresh(String refreshToken) async {
    if (_refreshInFlight) return null;
    _refreshInFlight = true;

    try {
      final deviceId = await deviceService.getDeviceId();

      final response = await http
          .post(
            Uri.parse('$kApiBaseUrl/auth/refresh'),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID':  deviceId,
            },
            body: json.encode({'refresh_token': refreshToken}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body      = json.decode(response.body) as Map<String, dynamic>;
        final newAccess  = body['access_token']  as String?;
        final newRefresh = body['refresh_token'] as String?;
        final userId     = body['user_id']       as String?;

        if (newAccess == null) return false;

        await Future.wait([
          storageService.write(key: _kAccess, value: newAccess),
          if (newRefresh != null)
            storageService.write(key: _kRefresh, value: newRefresh),
          if (userId != null)
            storageService.write(key: _kUserId, value: userId),
        ]);
        return true;
      }

      // Server explicitly rejected the refresh token
      if (response.statusCode == 401 || response.statusCode == 403) {
        await _clearTokens();
        return false;
      }

      // 5xx or unexpected — treat as network error, don't log out
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    } finally {
      _refreshInFlight = false;
    }
  }

  // ── Supabase session sync ─────────────────────────────────────────────
  void _listenToSupabase() {
    try {
      _supabaseSub?.cancel();
      _supabaseSub =
          Supabase.instance.client.auth.onAuthStateChange.listen(
        (data) async {
          final session = data.session;
          final event   = data.event;

          if (session != null) {
            // Supabase auto-refreshed — sync to local storage so all
            // HTTP clients (Dio + http package) send a valid JWT
            await Future.wait([
              storageService.write(
                  key: _kAccess, value: session.accessToken),
              if (session.refreshToken != null)
                storageService.write(
                    key: _kRefresh, value: session.refreshToken!),
              storageService.write(
                  key: _kUserId, value: session.user.id),
            ]);
            if (_status != AuthStatus.authenticated) {
              _setStatus(AuthStatus.authenticated);
            }
          } else if (event == AuthChangeEvent.signedOut) {
            await _clearSession();
          }
        },
        onError: (_) {
          // Supabase stream error — keep current status, ApiService handles
        },
      );
    } catch (_) {
      // Supabase not yet initialised — backend JWT auth still operates
    }
  }

  // ── Public API ────────────────────────────────────────────────────────

  /// Call after a successful login to persist tokens and bind device.
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
  }) async {
    await Future.wait([
      storageService.write(key: _kAccess,  value: accessToken),
      storageService.write(key: _kRefresh, value: refreshToken),
      storageService.write(key: _kUserId,  value: userId),
    ]);
    await deviceService.getDeviceId(); // Ensure device is bound at first login
    _setStatus(AuthStatus.authenticated);
    _listenToSupabase();
  }

  /// Called after successful login when tokens are already written to storage
  /// (e.g. the login screen writes them directly, then calls this).
  void onLoginSuccess() {
    _setStatus(AuthStatus.authenticated);
    _listenToSupabase();
  }

  /// Explicit user-initiated logout.
  /// Clears auth tokens only — device ID and all other local data preserved.
  Future<void> onLogout() async {
    _supabaseSub?.cancel();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    await _clearSession();
  }

  // ── Private helpers ───────────────────────────────────────────────────

  /// Clears auth tokens only.
  /// NEVER deletes the entire storage — preferences, cache, and device ID
  /// are preserved across logout just like Facebook and Instagram.
  Future<void> _clearTokens() async {
    await Future.wait([
      storageService.delete(key: _kAccess),
      storageService.delete(key: _kRefresh),
      storageService.delete(key: _kUserId),
    ]);
  }

  /// Clears the session and marks user as unauthenticated.
  /// Only wipes auth tokens — does NOT call storageService.deleteAll().
  Future<void> _clearSession() async {
    await _clearTokens();
    _setStatus(AuthStatus.unauthenticated);
  }

  void _setStatus(AuthStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners(); // GoRouter's refreshListenable reacts immediately
  }

  @override
  void dispose() {
    _supabaseSub?.cancel();
    super.dispose();
  }
}

// Global singleton — used by ApiService, router, and screens
final authService = AuthService();
