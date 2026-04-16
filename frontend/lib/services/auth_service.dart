// frontend/lib/services/auth_service.dart
// v4.0 — True Facebook/Instagram/YouTube boot model
//
// KEY CHANGES from v3.0:
//
//  initialize() is now INSTANT and makes ZERO network calls.
//  Decision tree:
//    No tokens        → unauthenticated  (first install or explicit logout)
//    Tokens exist     → authenticated    (optimistic — always go to home)
//    Expired token    → authenticated    (background refresh fires silently)
//
//  Why this is correct:
//    Facebook/Instagram/YouTube never make you wait for a network round-trip
//    before showing the app. They read local tokens, assume you're in, and
//    silently refresh behind the scenes. If the refresh fails due to a network
//    error you're still kept in — you only get logged out if the server
//    explicitly rejects the refresh token (account revoked, password changed).
//
//  Result:
//    • App boot → instant (no HTTP call blocking runApp)
//    • Returning users → always go straight to home, never re-login
//    • Expired tokens → refreshed silently in background after app renders
//    • No tokens at all → login screen (correct: first install / post-logout)

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

  bool _refreshInFlight = false;

  StreamSubscription<AuthState>? _supabaseSub;

  // ── Boot ──────────────────────────────────────────────────────────────
  /// Called once in main() before runApp().
  ///
  /// INSTANT — reads local storage only, makes ZERO network calls.
  ///
  /// Decision tree (Facebook/Instagram/YouTube model):
  ///   No tokens at all  → unauthenticated  (first install or post-logout)
  ///   Any token exists  → authenticated    (optimistic — user goes home)
  ///
  /// Token validation and refresh happen silently in the background AFTER
  /// the app is already rendering. The user never waits for a network call
  /// before they see the UI.
  Future<void> initialize() async {
    try {
      final access  = await storageService.read(key: _kAccess);
      final refresh = await storageService.read(key: _kRefresh);

      // No tokens — first install or after explicit logout
      if (access == null && refresh == null) {
        _setStatus(AuthStatus.unauthenticated);
        _listenToSupabase();
        return;
      }

      // Tokens exist — user is authenticated (optimistic, like FB/IG/YT)
      // We NEVER block boot on a network call to validate them.
      _setStatus(AuthStatus.authenticated);
      _listenToSupabase();

      // Fire background refresh if the access token is expired or close to it.
      // This runs AFTER runApp() so it doesn't delay the splash screen.
      if (refresh != null) {
        final needsRefresh = access == null ||
            _isTokenExpiredOrExpiringSoon(access, bufferSeconds: 300);
        if (needsRefresh) {
          // Fire-and-forget — any failure is handled silently
          _backgroundRefresh(refresh);
        }
      }
    } catch (_) {
      // Storage read error — never lock user out on a storage glitch
      _setStatus(AuthStatus.authenticated);
      _listenToSupabase();
    }
  }

  // ── Background refresh (called post-boot) ─────────────────────────────
  /// Refreshes tokens silently after the app has already rendered.
  /// Only logs out if the server explicitly rejects the refresh token
  /// (401/403 = account revoked, password changed, etc.).
  /// Network errors are ignored — user stays logged in.
  Future<void> _backgroundRefresh(String refreshToken) async {
    final result = await _silentRefresh(refreshToken);
    // result == false means server explicitly rejected → must log out
    if (result == false) {
      await _clearSession();
    }
    // result == null (network error) or true → keep authenticated
  }

  // ── Proactive refresh on app resume ───────────────────────────────────
  /// Called by MainShell when app returns to foreground.
  /// Silently refreshes if the token has expired or is about to expire.
  Future<void> tryRefreshOnResume() async {
    if (_status != AuthStatus.authenticated) return;
    if (_refreshInFlight) return;

    final access  = await storageService.read(key: _kAccess);
    final refresh = await storageService.read(key: _kRefresh);

    if (refresh == null) return;

    final shouldRefresh = access == null ||
        _isTokenExpiredOrExpiringSoon(access, bufferSeconds: 300);

    if (shouldRefresh) {
      final result = await _silentRefresh(refresh);
      // Only log out if server explicitly rejected the refresh token
      if (result == false) {
        _setStatus(AuthStatus.unauthenticated);
      }
    }
  }

  // ── Called by ApiService 401 interceptor ─────────────────────────────
  /// Returns true if refresh succeeded (caller should retry the request).
  /// Returns false if user must re-authenticate.
  Future<bool> handleUnauthorized() async {
    if (_refreshInFlight) {
      await Future.delayed(const Duration(seconds: 2));
      return _status == AuthStatus.authenticated;
    }

    final refresh = await storageService.read(key: _kRefresh);
    if (refresh == null) {
      await _clearSession();
      return false;
    }

    final result = await _silentRefresh(refresh);

    if (result == true) return true;

    if (result == false) {
      await _clearSession();
      return false;
    }

    // null = network error — keep authenticated, don't force login
    return false;
  }

  // ── JWT helpers ───────────────────────────────────────────────────────

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
  ///   null  — network / timeout error → keep user logged in
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
        final body       = json.decode(response.body) as Map<String, dynamic>;
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
        onError: (_) {},
      );
    } catch (_) {}
  }

  // ── Public API ────────────────────────────────────────────────────────

  /// Call after a successful login to persist tokens.
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
    await deviceService.getDeviceId();
    _setStatus(AuthStatus.authenticated);
    _listenToSupabase();
  }

  /// Called after successful login when tokens are already written.
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

  Future<void> _clearTokens() async {
    await Future.wait([
      storageService.delete(key: _kAccess),
      storageService.delete(key: _kRefresh),
      storageService.delete(key: _kUserId),
    ]);
  }

  Future<void> _clearSession() async {
    await _clearTokens();
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

// Global singleton
final authService = AuthService();
