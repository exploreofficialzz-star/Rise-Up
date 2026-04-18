// frontend/lib/utils/storage_service.dart
// v2.0 — Dual-storage for web resilience
//
// CHANGE vs v1:
//  Web dual-storage backup:
//    flutter_secure_storage on web uses IndexedDB, which can be temporarily
//    unavailable during a service worker swap (every new Flutter web deploy).
//    During that brief window, token reads return null → app looks like a fresh
//    install → user gets sent to login.
//
//    Fix: for the three auth token keys (access_token, refresh_token, user_id),
//    ALSO write to SharedPreferences (localStorage on web) as a backup.
//    Reads try secure storage first; if it returns null, fall back to the
//    SharedPreferences copy. Deletes clear both stores.
//
//    On mobile (Android/iOS) this backup is skipped — Keychain/Keystore is
//    already resilient across updates and the backup is unnecessary overhead.
//
//  All other behaviour (profile cache, deleteAll, etc.) is unchanged.

import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static final StorageService _i = StorageService._();
  factory StorageService() => _i;
  StorageService._();

  late final FlutterSecureStorage _storage;

  // Auth token keys that get the web backup treatment
  static const _kWebBackupPrefix = '__riseup_auth_bk_';
  static const _webBackupKeys = {
    'access_token',
    'refresh_token',
    'user_id',
  };

  void init() {
    if (kIsWeb) {
      _storage = const FlutterSecureStorage(
        webOptions: WebOptions(
          dbName:    'riseup_secure',
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

  // ── Write ──────────────────────────────────────────────────────────────────
  Future<void> write({required String key, required String value}) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('[Storage] write error for $key: $e');
    }

    // Web backup: also write auth tokens to SharedPreferences (localStorage).
    // This ensures tokens survive the IndexedDB unavailability window that
    // occurs during a Flutter web service worker swap on deployment.
    if (kIsWeb && _webBackupKeys.contains(key)) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('$_kWebBackupPrefix$key', value);
      } catch (e) {
        debugPrint('[Storage] web backup write error for $key: $e');
      }
    }
  }

  // ── Read ───────────────────────────────────────────────────────────────────
  Future<String?> read({required String key}) async {
    // Primary: secure storage (IndexedDB on web, Keychain/Keystore on mobile)
    try {
      final val = await _storage.read(key: key);
      if (val != null) return val;
    } catch (e) {
      debugPrint('[Storage] read error for $key: $e');
    }

    // Web fallback: try SharedPreferences backup if secure storage returned null
    if (kIsWeb && _webBackupKeys.contains(key)) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final backup = prefs.getString('$_kWebBackupPrefix$key');
        if (backup != null) {
          debugPrint('[Storage] using web backup for $key');
          // Opportunistically restore to secure storage
          try {
            await _storage.write(key: key, value: backup);
          } catch (_) {}
          return backup;
        }
      } catch (e) {
        debugPrint('[Storage] web backup read error for $key: $e');
      }
    }

    return null;
  }

  // ── Delete ─────────────────────────────────────────────────────────────────
  Future<void> delete({required String key}) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('[Storage] delete error for $key: $e');
    }

    // Web: also clear the backup
    if (kIsWeb && _webBackupKeys.contains(key)) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('$_kWebBackupPrefix$key');
      } catch (_) {}
    }
  }

  // ── Delete all ─────────────────────────────────────────────────────────────
  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      debugPrint('[Storage] deleteAll error: $e');
    }

    // Web: clear all backup keys too
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        for (final key in _webBackupKeys) {
          await prefs.remove('$_kWebBackupPrefix$key');
        }
      } catch (_) {}
    }
  }

  // ── Profile cache ──────────────────────────────────────────────────────────
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
