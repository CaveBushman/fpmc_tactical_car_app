import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Native side missing (tests, other embedders) or failing must never break
/// the app: these calls are best effort.
Future<void> _invoke(
  MethodChannel channel,
  String method, [
  Object? arguments,
]) async {
  try {
    await channel.invokeMethod<void>(method, arguments);
  } on MissingPluginException {
    // No native implementation registered.
  } on PlatformException catch (error) {
    debugPrint('Native call $method failed: ${error.message}');
  }
}

Stream<Object?> _safeEvents(EventChannel channel) =>
    channel.receiveBroadcastStream().handleError((Object _) {});

/// Hardware / notification PTT input from the Android side.
enum NativePttButton { down, up, toggle }

/// Android foreground service + hardware PTT keys (no-op elsewhere).
abstract class NativePttBridge {
  factory NativePttBridge.platform() =>
      _isAndroid ? MethodChannelPttBridge() : NoopPttBridge();

  Stream<NativePttButton> get buttons;

  /// Service errors, e.g. a refused microphone permission.
  Stream<String> get errors;
  Future<void> show({required String channel, required String status});
  Future<void> hide();
  Future<void> setVolumeKeyPtt(bool enabled);
}

class NoopPttBridge implements NativePttBridge {
  @override
  Stream<NativePttButton> get buttons => const Stream.empty();

  @override
  Stream<String> get errors => const Stream.empty();

  @override
  Future<void> show({required String channel, required String status}) async {}

  @override
  Future<void> hide() async {}

  @override
  Future<void> setVolumeKeyPtt(bool enabled) async {}
}

class MethodChannelPttBridge implements NativePttBridge {
  static const _methods = MethodChannel('tactical/ptt_native');
  static const _events = EventChannel('tactical/ptt_buttons');

  late final Stream<String> _raw = _safeEvents(
    _events,
  ).map((event) => '$event');
  bool _shown = false;

  @override
  Stream<NativePttButton> get buttons => _raw
      .map(
        (event) => switch (event) {
          'down' => NativePttButton.down,
          'up' => NativePttButton.up,
          'toggle' => NativePttButton.toggle,
          _ => null,
        },
      )
      .where((button) => button != null)
      .cast<NativePttButton>();

  @override
  Stream<String> get errors => _raw
      .where((event) => event.startsWith('service_error:'))
      .map((event) => event.substring('service_error:'.length));

  @override
  Future<void> show({required String channel, required String status}) async {
    await _invoke(_methods, _shown ? 'update' : 'start', {
      'channel': channel,
      'status': status,
    });
    _shown = true;
  }

  @override
  Future<void> hide() async {
    if (!_shown) {
      return;
    }
    _shown = false;
    await _invoke(_methods, 'stop');
  }

  @override
  Future<void> setVolumeKeyPtt(bool enabled) =>
      _invoke(_methods, 'setVolumeKeyPtt', enabled);
}

class CarTargetData {
  const CarTargetData({
    required this.title,
    required this.kind,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.bearingDeg,
    required this.priority,
  });

  final String title;
  final String kind;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final double bearingDeg;
  final bool priority;

  Map<String, Object> toMap() => {
    'title': title,
    'kind': kind,
    'latitude': latitude,
    'longitude': longitude,
    'distanceKm': distanceKm,
    'bearingDeg': bearingDeg,
    'priority': priority,
  };
}

class CarReply {
  const CarReply({required this.groupId, required this.text});

  final String groupId;
  final String text;
}

/// Android Auto targets and car-readable message notifications.
abstract class CarBridge {
  factory CarBridge.platform() =>
      _isAndroid ? MethodChannelCarBridge() : NoopCarBridge();

  Stream<CarReply> get replies;
  Future<void> updateTargets(List<CarTargetData> targets);
  Future<void> notifyMessage({
    required String groupId,
    required String groupName,
    required String sender,
    required String body,
    required DateTime sentAt,
  });
  Future<void> clearMessages();
}

class NoopCarBridge implements CarBridge {
  @override
  Stream<CarReply> get replies => const Stream.empty();

  @override
  Future<void> updateTargets(List<CarTargetData> targets) async {}

  @override
  Future<void> notifyMessage({
    required String groupId,
    required String groupName,
    required String sender,
    required String body,
    required DateTime sentAt,
  }) async {}

  @override
  Future<void> clearMessages() async {}
}

class MethodChannelCarBridge implements CarBridge {
  static const _methods = MethodChannel('tactical/car');
  static const _events = EventChannel('tactical/car_events');

  @override
  late final Stream<CarReply> replies = _safeEvents(_events)
      .where((event) => event is Map && event['type'] == 'reply')
      .map(
        (event) => CarReply(
          groupId: '${(event as Map)['groupId']}',
          text: '${event['text']}',
        ),
      );

  @override
  Future<void> updateTargets(List<CarTargetData> targets) =>
      _invoke(_methods, 'updateTargets', [for (final t in targets) t.toMap()]);

  @override
  Future<void> notifyMessage({
    required String groupId,
    required String groupName,
    required String sender,
    required String body,
    required DateTime sentAt,
  }) => _invoke(_methods, 'notifyMessage', {
    'groupId': groupId,
    'groupName': groupName,
    'sender': sender,
    'body': body,
    'timestamp': sentAt.millisecondsSinceEpoch,
  });

  @override
  Future<void> clearMessages() => _invoke(_methods, 'clearMessages');
}
