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

class VoiceDataReceived extends VoiceEvent {
  const VoiceDataReceived({required this.from, required this.data});

  final String from;
  final List<int> data;
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
  Future<void> sendData(List<int> data);
  Future<void> disconnect();
  Future<void> dispose();
}
