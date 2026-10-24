import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stable random id of this installation, used by the backend to bind
/// accounts to devices. Kept in secure storage and not wiped on logout.
class DeviceIdentity {
  const DeviceIdentity({this.storageKey = 'device_id_v1'});

  final String storageKey;

  static const _storage = FlutterSecureStorage();

  Future<String> id() async {
    try {
      final existing = await _storage.read(key: storageKey);
      if (existing != null && existing.isNotEmpty) {
        return existing;
      }
      final random = Random.secure();
      final created = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await _storage.write(key: storageKey, value: created);
      return created;
    } catch (_) {
      // No secure storage: a per-run id still lets login work.
      return _fallback;
    }
  }

  static final String _fallback = List.generate(
    16,
    (_) => Random().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  /// Human-readable label shown to admins next to the binding.
  String get name => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iPhone',
    _ => kIsWeb ? 'Web' : defaultTargetPlatform.name,
  };
}
