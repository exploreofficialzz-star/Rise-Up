// frontend/lib/services/device_service.dart
// Generates + persists a unique device ID used for refresh token binding

import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'storage_service.dart';

class DeviceService {
  DeviceService._();
  static final DeviceService instance = DeviceService._();

  static const _kDeviceIdKey = 'riseup_device_id';

  /// Returns a stable device ID — generated once, stored forever.
  /// Even after logout the device ID persists so the backend can
  /// recognise returning devices.
  Future<String> getDeviceId() async {
    // Return cached value if already fetched this session
    final stored = await storageService.read(key: _kDeviceIdKey);
    if (stored != null && stored.isNotEmpty) return stored;

    String id;
    try {
      final info = DeviceInfoPlugin();
      if (kIsWeb) {
        id = 'web-${const Uuid().v4()}';
      } else if (Platform.isAndroid) {
        final android = await info.androidInfo;
        id = android.id; // stable hardware ID
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
