import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'ptt_crypto_service.dart';

class EncryptedPttState {
  const EncryptedPttState({
    required this.status,
    required this.channel,
    required this.encrypted,
    this.lastFrameAt,
    this.lastError,
  });

  final EncryptedPttStatus status;
  final String channel;
  final bool encrypted;
  final DateTime? lastFrameAt;
  final String? lastError;

  EncryptedPttState copyWith({
    EncryptedPttStatus? status,
    String? channel,
    bool? encrypted,
    DateTime? lastFrameAt,
    String? lastError,
  }) {
    return EncryptedPttState(
      status: status ?? this.status,
      channel: channel ?? this.channel,
      encrypted: encrypted ?? this.encrypted,
      lastFrameAt: lastFrameAt ?? this.lastFrameAt,
      lastError: lastError,
    );
  }
}

enum EncryptedPttStatus {
  offline,
  ready,
  transmitting,
  receiving,
  error,
}

class EncryptedPttService {
  EncryptedPttService({
    PttCryptoService? crypto,
    String channel = 'ALPHA',
  })  : _crypto = crypto ?? PttCryptoService(),
        _state = EncryptedPttState(status: EncryptedPttStatus.ready, channel: channel, encrypted: true);

  final PttCryptoService _crypto;
  final StreamController<EncryptedPttState> _stateController = StreamController.broadcast();
  EncryptedPttState _state;
  SecretKey? _channelKey;

  Stream<EncryptedPttState> get stateStream => _stateController.stream;
  EncryptedPttState get state => _state;

  Future<void> unlockChannel({
    required String passphrase,
    required String operationId,
  }) async {
    final salt = utf8.encode('1stpmc:$operationId:${_state.channel}');
    _channelKey = await _crypto.deriveChannelKey(passphrase: passphrase, salt: salt);
    _setState(_state.copyWith(status: EncryptedPttStatus.ready, encrypted: true));
  }

  void installChannelKey(List<int> keyBytes) {
    if (keyBytes.length != 32) {
      throw ArgumentError.value(keyBytes.length, 'keyBytes.length', 'AES-GCM 256 requires a 32 byte key.');
    }
    _channelKey = SecretKey(keyBytes);
    _setState(_state.copyWith(status: EncryptedPttStatus.ready, encrypted: true));
  }

  void switchChannel({
    required String channel,
    required List<int> keyBytes,
  }) {
    if (keyBytes.length != 32) {
      throw ArgumentError.value(keyBytes.length, 'keyBytes.length', 'AES-GCM 256 requires a 32 byte key.');
    }
    _channelKey = SecretKey(keyBytes);
    _setState(
      _state.copyWith(
        status: EncryptedPttStatus.ready,
        channel: channel,
        encrypted: true,
        lastError: null,
      ),
    );
  }

  void beginTransmit() {
    if (_channelKey == null) {
      _setState(_state.copyWith(status: EncryptedPttStatus.error, lastError: 'PTT encryption key is locked.'));
      return;
    }
    _setState(_state.copyWith(status: EncryptedPttStatus.transmitting));
  }

  void endTransmit() {
    _setState(_state.copyWith(status: EncryptedPttStatus.ready));
  }

  Future<EncryptedPttFrame> encryptOutgoingFrame(List<int> opusFrame) async {
    final key = _channelKey;
    if (key == null) {
      throw StateError('PTT encryption key is locked.');
    }
    final frame = await _crypto.encryptVoiceFrame(
      key: key,
      opusFrame: opusFrame,
      aad: utf8.encode(_state.channel),
    );
    _setState(_state.copyWith(lastFrameAt: DateTime.now(), encrypted: true));
    return frame;
  }

  Future<List<int>> decryptIncomingFrame(EncryptedPttFrame frame) async {
    final key = _channelKey;
    if (key == null) {
      throw StateError('PTT encryption key is locked.');
    }
    final clear = await _crypto.decryptVoiceFrame(
      key: key,
      frame: frame,
      aad: utf8.encode(_state.channel),
    );
    _setState(_state.copyWith(status: EncryptedPttStatus.receiving, lastFrameAt: DateTime.now(), encrypted: true));
    return clear;
  }

  Future<void> dispose() async {
    await _stateController.close();
  }

  void _setState(EncryptedPttState value) {
    _state = value;
    _stateController.add(value);
  }
}
