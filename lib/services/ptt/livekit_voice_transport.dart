import 'dart:async';
import 'dart:typed_data';

import 'package:livekit_client/livekit_client.dart';

import '../backend_client.dart';
import 'voice_transport.dart';

const _floorTopic = 'ptt-floor';

/// LiveKit room with shared-key E2EE (AES-GCM frame encryption); the key
/// comes from the backend, so the SFU only relays ciphertext.
class LiveKitVoiceTransport implements VoiceTransport {
  final StreamController<VoiceEvent> _events = StreamController.broadcast();
  Room? _room;
  EventsListener<RoomEvent>? _listener;

  @override
  Stream<VoiceEvent> get events => _events.stream;

  @override
  Future<void> connect(PttJoinInfo info) async {
    await disconnect();
    final keyProvider = await BaseKeyProvider.create();
    // Older key first: the latest index set becomes the sending key.
    for (final key in info.keys) {
      await keyProvider.setRawKey(
        Uint8List.fromList(key.bytes),
        keyIndex: key.id % 16,
      );
    }
    final room = Room(
      roomOptions: RoomOptions(
        encryption: E2EEOptions(keyProvider: keyProvider),
        defaultAudioCaptureOptions: const AudioCaptureOptions(
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        ),
      ),
    );
    final listener = room.createListener()
      ..on<RoomDisconnectedEvent>(
        (event) => _add(VoiceDisconnected(event.reason?.name)),
      )
      ..on<ParticipantDisconnectedEvent>(
        (event) => _add(VoiceParticipantLeft(event.participant.identity)),
      )
      ..on<ActiveSpeakersChangedEvent>((event) {
        _add(
          VoiceSpeakersChanged({
            for (final speaker in event.speakers)
              if (speaker is RemoteParticipant) speaker.identity,
          }),
        );
      })
      ..on<DataReceivedEvent>((event) {
        final from = event.participant?.identity;
        if (event.topic == _floorTopic && from != null) {
          _add(VoiceDataReceived(from: from, data: event.data));
        }
      });
    _room = room;
    _listener = listener;
    await room.connect(info.liveKitUrl, info.token);
    await room.localParticipant?.setMicrophoneEnabled(false);
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    await _room?.localParticipant?.setMicrophoneEnabled(enabled);
  }

  @override
  Future<void> sendData(List<int> data) async {
    await _room?.localParticipant?.publishData(
      data,
      reliable: true,
      topic: _floorTopic,
    );
  }

  @override
  Future<void> disconnect() async {
    await _listener?.dispose();
    _listener = null;
    final room = _room;
    _room = null;
    if (room != null) {
      await room.disconnect();
      await room.dispose();
    }
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }

  void _add(VoiceEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }
}
