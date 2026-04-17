// frontend/lib/services/auth_service.dart
// v5.0 — Production-grade resilient auth (no random logout)

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

  bool _refreshInFlight = false;
  int _refreshFailures = 0;
  static const int _maxRefreshFailures = 3;

  StreamSubscription<AuthState>? _supabaseSub;

  // ── INIT ─────────────────────────────────────────────
  Future<void> initialize() async {
    try {
      final access  = await storageService.read(key: _kAccess);
      final refresh = await storageService.read(key: _kRefresh);

      if (access == null && refresh == null) {
        _setStatus(AuthStatus.unauthenticated);
        _listenToSupabase();
        return;
      }

      _setStatus(AuthStatus.authenticated);
      _listenToSupabase();

      if (refresh != null) {
        final needsRefresh = access == null || _isExpired(access);
        if (needsRefresh) {
          _backgroundRefresh(refresh);
        }
      }
    } catch (_) {
      _setStatus(AuthStatus.authenticated);
      _listenToSupabase();
    }
  }

  // ── BACKGROUND REFRESH ─────────────────────────────
  Future<void> _backgroundRefresh(String refreshToken) async {
    final result = await _silentRefresh(refreshToken);

    if (result == true) {
      _refreshFailures = 0;
      return;
    }

    if (result == false) {
      _refreshFailures++;

      if (_refreshFailures >= _maxRefreshFailures) {
        debugPrint('Max refresh failures → logout');
        await _clearSession();
      } else {
        debugPrint('Refresh rejected → retry later');
      }
    }
  }

  // ── API INTERCEPTOR ─────────────────────────────
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

      return true;
    }

    return true;
  }

  // ── REFRESH CALL ─────────────────────────────
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
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final body = json.decode(res.body);

        await Future.wait([
          storageService.write(key: _kAccess, value: body['access_token']),
          if (body['refresh_token'] != null)
            storageService.write(key: _kRefresh, value: body['refresh_token']),
          if (body['user_id'] != null)
            storageService.write(key: _kUserId, value: body['user_id']),
        ]);

        return true;
      }

      if (res.statusCode == 401 || res.statusCode == 403) {
        debugPrint('Refresh rejected by server');
        return false;
      }

      return null;
    } catch (_) {
      return null;
    } finally {
      _refreshInFlight = false;
    }
  }

  // ── JWT CHECK ─────────────────────────────
  bool _isExpired(String token) {
    try {
      final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1])))
      );
      final exp = payload['exp'];
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return exp == null || now >= exp;
    } catch (_) {
      return true;
    }
  }

  // ── SUPABASE SYNC ─────────────────────────────
  void _listenToSupabase() {
    try {
      _supabaseSub?.cancel();
      _supabaseSub =
          Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
        final session = data.session;

        if (session != null) {
          await Future.wait([
            storageService.write(key: _kAccess, value: session.accessToken),
            if (session.refreshToken != null)
              storageService.write(
                  key: _kRefresh, value: session.refreshToken!),
            storageService.write(key: _kUserId, value: session.user.id),
          ]);
          _setStatus(AuthStatus.authenticated);
        } else {
          await _clearSession();
        }
      });
    } catch (_) {}
  }

  // ── LOGIN ─────────────────────────────
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
  }) async {
    await Future.wait([
      storageService.write(key: _kAccess, value: accessToken),
      storageService.write(key: _kRefresh, value: refreshToken),
      storageService.write(key: _kUserId, value: userId),
    ]);

    _setStatus(AuthStatus.authenticated);
    _listenToSupabase();
  }

  // ── LOGOUT ─────────────────────────────
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
    ]);
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
