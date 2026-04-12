// frontend/lib/services/device_service.dart
// v1.1 — fixed import path for storage_service

import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../utils/storage_service.dart';

class DeviceService {
  DeviceService._();
  static final DeviceService instance = DeviceService._();

  static const _kDeviceIdKey = 'riseup_device_id';

  /// Returns a stable device ID — generated once, stored forever.
  /// Persists across logouts so the backend always recognises this device.
  Future<String> getDeviceId() async {
    final stored = await storageService.read(key: _kDeviceIdKey);
    if (stored != null && stored.isNotEmpty) return stored;

    String id;
    try {
      final info = DeviceInfoPlugin();
      if (kIsWeb) {
        id = 'web-${const Uuid().v4()}';
      } else if (Platform.isAndroid) {
        final android = await info.androidInfo;
        id = android.id;
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        id = ios.identifierForVendor ?? const Uuid().v4();
      } else {
        id = const Uuid().v4();
      }
    } catch (_) {
      id = const Uuid().v4();
    }

    await storageService.write(key: _kDeviceIdKey, value: id);
    return id;
  }
}

final deviceService = DeviceService.instance;
