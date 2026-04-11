// frontend/lib/services/auth_service.dart
//
// Central auth-state manager — the Facebook-style "stay logged in" brain.
//
// How it works:
//  1. main.dart calls authService.initialize() BEFORE runApp().
//     It reads the stored token from secure storage synchronously so
//     the very first GoRouter render already has the correct status.
//  2. GoRouter uses refreshListenable: authService so whenever status
//     changes (login, logout, 401+failed-refresh) the router re-evaluates
//     its redirect callback and navigates instantly.
//  3. When Supabase auto-refreshes a token it writes the new tokens back
//     to our storage so ApiService always sends a fresh JWT.
//  4. When ApiService cannot refresh a 401 it calls
//     authService.onAuthenticationFailed() — this clears storage and flips
//     status to unauthenticated, which makes GoRouter redirect to /login.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/storage_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthService extends ChangeNotifier {
  // ── Singleton ──────────────────────────────────────────────────────────
  static final AuthService _i = AuthService._();
  factory AuthService() => _i;
  AuthService._();

  // ── State ──────────────────────────────────────────────────────────────
  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status   => _status;
  bool get isAuthenticated  => _status == AuthStatus.authenticated;
  bool get isUnauthenticated => _status == AuthStatus.unauthenticated;

  StreamSubscription<AuthState>? _supabaseSub;

  // ── Boot ───────────────────────────────────────────────────────────────
  /// Called once in main() before runApp().
  /// Reads local storage (fast, <5 ms on device) so the first router
  /// render already knows whether to show /home or /login.
  Future<void> initialize() async {
    try {
      final token = await storageService.read(key: 'access_token');
      if (token != null && token.isNotEmpty) {
        // Optimistically authenticated — ApiService will validate on first
        // real request and call onAuthenticationFailed() if invalid.
        _setStatus(AuthStatus.authenticated);
      } else {
        _setStatus(AuthStatus.unauthenticated);
      }
    } catch (_) {
      _setStatus(AuthStatus.unauthenticated);
    }

    // Subscribe to Supabase token-refresh events so tokens are always fresh.
    _listenToSupabase();
  }

  // ── Supabase session sync ──────────────────────────────────────────────
  void _listenToSupabase() {
    try {
      _supabaseSub?.cancel();
      _supabaseSub = Supabase.instance.client.auth.onAuthStateChange.listen(
        (data) async {
          final session = data.session;
          final event   = data.event;

          if (session != null) {
            // Supabase auto-refreshed — sync new tokens to our storage so
            // ApiService Dio interceptor always sends a valid JWT.
            await Future.wait([
              storageService.write(
                  key: 'access_token', value: session.accessToken),
              if (session.refreshToken != null)
                storageService.write(
                    key: 'refresh_token', value: session.refreshToken!),
              storageService.write(
                  key: 'user_id', value: session.user.id),
            ]);
            _setStatus(AuthStatus.authenticated);
          } else if (event == AuthChangeEvent.signedOut) {
            await _clearSession();
          }
        },
        onError: (_) {
          // Supabase error — keep current status, let ApiService handle it.
        },
      );
    } catch (_) {
      // Supabase not initialised or already has no session — backend JWT
      // auth still works fine.
    }
  }

  // ── Callbacks from ApiService & screens ───────────────────────────────

  /// Call this after a successful login to immediately flip status
  /// and start listening to Supabase.
  void onLoginSuccess() {
    _setStatus(AuthStatus.authenticated);
    _listenToSupabase();
  }

  /// Called by the Dio interceptor when a 401 cannot be recovered.
  /// Clears ALL stored credentials and triggers GoRouter → /login.
  Future<void> onAuthenticationFailed() async {
    await _clearSession();
  }

  /// Call this when the user explicitly logs out.
  Future<void> onLogout() async {
    _supabaseSub?.cancel();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    await _clearSession();
  }

  // ── Helpers ────────────────────────────────────────────────────────────
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
