import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class EncryptedPttFrame {
  const EncryptedPttFrame({
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;

  Map<String, String> toJson() {
    return {
      'nonce': base64Encode(nonce),
      'cipherText': base64Encode(cipherText),
      'mac': base64Encode(mac),
    };
  }
}

class PttCryptoService {
  PttCryptoService({AesGcm? algorithm}) : _algorithm = algorithm ?? AesGcm.with256bits();

  final AesGcm _algorithm;

  Future<SecretKey> deriveChannelKey({
    required String passphrase,
    required List<int> salt,
  }) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 210000,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  Future<EncryptedPttFrame> encryptVoiceFrame({
    required SecretKey key,
    required List<int> opusFrame,
    required List<int> aad,
  }) async {
    final secretBox = await _algorithm.encrypt(
      opusFrame,
      secretKey: key,
      aad: aad,
    );
    return EncryptedPttFrame(
      nonce: secretBox.nonce,
      cipherText: secretBox.cipherText,
      mac: secretBox.mac.bytes,
    );
  }

  Future<Uint8List> decryptVoiceFrame({
    required SecretKey key,
    required EncryptedPttFrame frame,
    required List<int> aad,
  }) async {
    final clear = await _algorithm.decrypt(
      SecretBox(
        frame.cipherText,
        nonce: frame.nonce,
        mac: Mac(frame.mac),
      ),
      secretKey: key,
      aad: aad,
    );
    return Uint8List.fromList(clear);
  }
}
