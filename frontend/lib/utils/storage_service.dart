// frontend/lib/utils/storage_service.dart
//
// Changes vs original:
//  • cacheProfile()   — saves profile JSON for instant offline display
//  • getCachedProfile() — reads cached profile (never shows system default)
//  • clearProfileCache() — called on logout
// ─────────────────────────────────────────────────────────────
//  StorageService — Platform-safe key-value storage
//  • Mobile: flutter_secure_storage (encrypted)
//  • Web:    flutter_secure_storage with web options (localStorage)
// ─────────────────────────────────────────────────────────────
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static final StorageService _i = StorageService._();
  factory StorageService() => _i;
  StorageService._();

  late final FlutterSecureStorage _storage;

  void init() {
    if (kIsWeb) {
      _storage = const FlutterSecureStorage(
        webOptions: WebOptions(
          dbName: 'riseup_secure',
          publicKey: 'riseup_pub_key',
        ),
      );
    } else {
      _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock),
      );
    }
  }

  Future<void> write({required String key, required String value}) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('[Storage] write error for $key: $e');
    }
  }

  Future<String?> read({required String key}) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('[Storage] read error for $key: $e');
      return null;
    }
  }

  Future<void> delete({required String key}) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('[Storage] delete error for $key: $e');
    }
  }

  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      debugPrint('[Storage] deleteAll error: $e');
    }
  }

  // ── Profile cache ────────────────────────────────────────────────────
  // Stores the last successfully loaded profile so:
  //   • The profile screen never falls back to system defaults on network error
  //   • The app feels instant — cached data shows while fresh data loads
  static const _kCachedProfile = '_cached_profile';

  Future<void> cacheProfile(Map<String, dynamic> profile) async {
    try {
      await write(key: _kCachedProfile, value: jsonEncode(profile));
    } catch (e) {
      debugPrint('[Storage] cacheProfile error: $e');
    }
  }

  Future<Map<String, dynamic>?> getCachedProfile() async {
    try {
      final raw = await read(key: _kCachedProfile);
      if (raw == null || raw.isEmpty) return null;
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (e) {
      debugPrint('[Storage] getCachedProfile error: $e');
      return null;
    }
  }

  Future<void> clearProfileCache() async {
    await delete(key: _kCachedProfile);
  }
}

final storageService = StorageService();
