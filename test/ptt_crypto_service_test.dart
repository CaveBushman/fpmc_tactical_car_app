import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/services/encrypted_ptt_service.dart';

void main() {
  test('encrypts and decrypts PTT voice frames', () async {
    final service = EncryptedPttService(channel: 'ALPHA')
      ..installChannelKey(List<int>.generate(32, (index) => index + 1));
    final clearFrame = List<int>.generate(80, (index) => index % 255);

    final encrypted = await service.encryptOutgoingFrame(clearFrame);
    final decrypted = await service.decryptIncomingFrame(encrypted);

    expect(encrypted.cipherText, isNot(clearFrame));
    expect(decrypted, clearFrame);

    await service.dispose();
  });
}
