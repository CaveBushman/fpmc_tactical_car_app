import 'dart:async';

import '../backend_client.dart';

sealed class VoiceEvent {
  const VoiceEvent();
}

class VoiceDisconnected extends VoiceEvent {
  const VoiceDisconnected(this.reason);

  final String? reason;
}

/// Identities currently detected as speaking (remote participants only).
class VoiceSpeakersChanged extends VoiceEvent {
  const VoiceSpeakersChanged(this.identities);

  final Set<String> identities;
}

/// Data channel topics used inside a group room (all E2EE).
abstract final class RoomTopic {
  /// PTT floor control.
  static const floor = 'ptt-floor';

  /// Member positions shared over the internet.
  static const position = 'position';

  /// Team text messages sent over the internet when no radio is connected.
  static const text = 'text';

  static const all = {floor, position, text};
}

class VoiceDataReceived extends VoiceEvent {
  const VoiceDataReceived({
    required this.from,
    required this.data,
    this.topic = RoomTopic.floor,
  });

  final String from;
  final List<int> data;
  final String topic;
}

class VoiceParticipantLeft extends VoiceEvent {
  const VoiceParticipantLeft(this.identity);

  final String identity;
}

/// Real-time voice room (LiveKit in production, a fake in tests).
abstract class VoiceTransport {
  Stream<VoiceEvent> get events;

  /// Joins the room with end-to-end encryption using [keys] (oldest first,
  /// the last one encrypts outgoing frames).
  Future<void> connect(PttJoinInfo info);
  Future<void> setMicrophoneEnabled(bool enabled);

  /// Reliable data message to everyone in the room (E2EE as well).
  Future<void> sendData(List<int> data, {String topic = RoomTopic.floor});
  Future<void> disconnect();
  Future<void> dispose();
}
