// ─────────────────────────────────────────────────────────────
//  StorageService — Platform-safe key-value storage
//  • Mobile: flutter_secure_storage (encrypted)
//  • Web:    flutter_secure_storage with web options (localStorage)
// ─────────────────────────────────────────────────────────────
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static final StorageService _i = StorageService._();
  factory StorageService() => _i;
  StorageService._();

  late final FlutterSecureStorage _storage;

  void init() {
    if (kIsWeb) {
      // Web: use localStorage (not encrypted but functional)
      _storage = const FlutterSecureStorage(
        webOptions: WebOptions(
          dbName: 'riseup_secure',
          publicKey: 'riseup_pub_key',
        ),
      );
    } else {
      _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
      );
    }
  }

  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  Future<String?> read({required String key}) =>
      _storage.read(key: key);

  Future<void> delete({required String key}) =>
      _storage.delete(key: key);

  Future<void> deleteAll() => _storage.deleteAll();
}

final storageService = StorageService();
