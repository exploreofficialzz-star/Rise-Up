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
}

final storageService = StorageService();
