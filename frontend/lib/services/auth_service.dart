// frontend/lib/services/auth_service.dart
// v2.0 — Facebook-style device-bound silent refresh
//
// Flow:
//  1. initialize() called in main() before runApp()
//  2. Valid token     → authenticated immediately → /home
//  3. Expired token   → silent refresh via /auth/refresh + device ID
//  4. Refresh success → new tokens stored → /home (user never sees login)
//  5. Refresh fail    → clear tokens → /login (only on explicit revocation)
//  6. No network      → keep tokens, go /home, retry next open
//  7. Explicit logout → clear tokens, keep device ID → /login
//  8. Supabase events → always kept in sync

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
  // ── Singleton ────────────────────────────────────────────────────────
  static final AuthService _i = AuthService._();
  factory AuthService() => _i;
  AuthService._();

  // ── Storage keys ─────────────────────────────────────────────────────
  static const _kAccess  = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kUserId  = 'user_id';

  // ── State ─────────────────────────────────────────────────────────────
  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status          => _status;
  bool get isAuthenticated       => _status == AuthStatus.authenticated;
  bool get isUnauthenticated     => _status == AuthStatus.unauthenticated;

  StreamSubscription<AuthState>? _supabaseSub;

  // ── Boot ──────────────────────────────────────────────────────────────
  /// Called once in main() before runApp().
  ///
  /// Decision tree (Facebook/Instagram/YouTube model):
  ///   No tokens at all       → unauthenticated  (first install or logout)
  ///   Token valid            → authenticated    (straight to home)
  ///   Token expired          → try silent refresh
  ///     Refresh OK           → authenticated    (user never sees login)
  ///     Refresh revoked      → unauthenticated  (server explicitly rejected)
  ///     Network error        → authenticated    (don't punish offline opens)
  Future<void> initialize() async {
    try {
      final access  = await storageService.read(key: _kAccess);
      final refresh = await storageService.read(key: _kRefresh);

      // ── 1. No tokens — brand new install or explicit logout ──────────
      if (access == null && refresh == null) {
        _setStatus(AuthStatus.unauthenticated);
        _listenToSupabase();
        return;
      }

      // ── 2. Access token exists and is not expired ────────────────────
      if (access != null && !_isTokenExpired(access)) {
        _setStatus(AuthStatus.authenticated);
        _listenToSupabase();
        return;
      }

      // ── 3. Access token expired — try silent refresh ─────────────────
      if (refresh != null) {
        final refreshed = await _silentRefresh(refresh);
        // refreshed == null means network error → keep user logged in
        if (refreshed == null) {
          // No network: optimistically authenticated, retry next open
          _setStatus(AuthStatus.authenticated);
        } else {
          _setStatus(
            refreshed
                ? AuthStatus.authenticated
                : AuthStatus.unauthenticated,
          );
        }
        _listenToSupabase();
        return;
      }

      // ── 4. Access expired, no refresh token ──────────────────────────
      _setStatus(AuthStatus.unauthenticated);
    } catch (_) {
      // Storage read failed — don't lock user out
      _setStatus(AuthStatus.unauthenticated);
    }

    _listenToSupabase();
  }

  // ── JWT helpers ───────────────────────────────────────────────────────

  /// Decodes the JWT exp claim and returns true if it's in the past.
  bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final map = json.decode(payload) as Map<String, dynamic>;
      final exp = map['exp'] as int?;
      if (exp == null) return false;
      // Add 30-second buffer to avoid edge-case races
      return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= (exp - 30);
    } catch (_) {
      return true; // Malformed token — treat as expired
    }
  }

  /// Hits POST /auth/refresh with the refresh token + device ID.
  ///
  /// Returns:
  ///   true  — refreshed successfully, new tokens saved
  ///   false — server explicitly rejected (revoked/invalid) → go to login
  ///   null  — network error → caller decides (keep user logged in)
  Future<bool?> _silentRefresh(String refreshToken) async {
    try {
      final deviceId = await deviceService.getDeviceId();

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/auth/refresh'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID':  deviceId,
        },
        body: json.encode({'refresh_token': refreshToken}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = json.decode(response.body) as Map<String, dynamic>;
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

      if (response.statusCode == 401 || response.statusCode == 403) {
        // Server explicitly revoked — clear and force login
        await _clearTokens();
        return false;
      }

      // 5xx or unexpected — treat as network error, don't log out
      return null;
    } on TimeoutException {
      return null; // Network timeout — keep user in
    } catch (_) {
      return null; // Any other network failure — keep user in
    }
  }

  // ── Supabase session sync ─────────────────────────────────────────────
  void _listenToSupabase() {
    try {
      _supabaseSub?.cancel();
      _supabaseSub = Supabase.instance.client.auth.onAuthStateChange.listen(
        (data) async {
          final session = data.session;
          final event   = data.event;

          if (session != null) {
            // Supabase auto-refreshed — sync new tokens so Dio always
            // sends a valid JWT on every request
            await Future.wait([
              storageService.write(
                key: _kAccess, value: session.accessToken),
              if (session.refreshToken != null)
                storageService.write(
                  key: _kRefresh, value: session.refreshToken!),
              storageService.write(
                key: _kUserId, value: session.user.id),
            ]);
            _setStatus(AuthStatus.authenticated);
          } else if (event == AuthChangeEvent.signedOut) {
            await _clearSession();
          }
        },
        onError: (_) {
          // Supabase error — keep current status, let ApiService handle
        },
      );
    } catch (_) {
      // Supabase not yet initialised — backend JWT auth still works
    }
  }

  // ── Called from screens / ApiService ─────────────────────────────────

  /// Call after successful login to persist tokens + bind device.
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
    // Ensure device ID is generated and bound on first login
    await deviceService.getDeviceId();
    _setStatus(AuthStatus.authenticated);
    _listenToSupabase();
  }

  /// Called after successful login when tokens are already stored
  /// (e.g. login screen writes them directly before calling this).
  void onLoginSuccess() {
    _setStatus(AuthStatus.authenticated);
    _listenToSupabase();
  }

  /// Called by Dio interceptor when a 401 cannot be recovered via refresh.
  /// Clears tokens → GoRouter redirects to /login.
  Future<void> onAuthenticationFailed() async {
    await _clearSession();
  }

  /// Explicit user logout — clears tokens but NOT device ID.
  /// Device ID persists so the backend still recognises this device.
  Future<void> onLogout() async {
    _supabaseSub?.cancel();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    await _clearSession();
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  /// Clears tokens only — device ID intentionally kept.
  Future<void> _clearTokens() async {
    await Future.wait([
      storageService.delete(key: _kAccess),
      storageService.delete(key: _kRefresh),
      storageService.delete(key: _kUserId),
    ]);
  }

  /// Full session wipe (logout / auth failed).
  Future<void> _clearSession() async {
    await storageService.deleteAll();
    _setStatus(AuthStatus.unauthenticated);
  }

  void _setStatus(AuthStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners(); // GoRouter's refreshListenable picks this up
  }

  @override
  void dispose() {
    _supabaseSub?.cancel();
    super.dispose();
  }
}

// Global singleton — imported by ApiService, router, screens
final authService = AuthService();
