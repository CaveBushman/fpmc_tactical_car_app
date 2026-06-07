import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/services/meshtastic_message_encoder.dart';

void main() {
  test('encodes group text as ToRadio broadcast packet', () {
    const encoder = MeshtasticMessageEncoder();

    final bytes = encoder.encodeGroupText(text: 'OK', channelIndex: 2);

    expect(bytes, [
      0x0A,
      0x0F,
      0x15,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0x18,
      0x02,
      0x22,
      0x06,
      0x08,
      0x01,
      0x12,
      0x02,
      0x4F,
      0x4B,
    ]);
  });

  test('encodes direct text with destination and ack request', () {
    const encoder = MeshtasticMessageEncoder();

    final bytes = encoder.encodeDirectText(
      text: 'DM',
      destinationNode: 0xA1100002,
      channelIndex: 1,
    );

    expect(bytes, [
      0x0A,
      0x11,
      0x15,
      0x02,
      0x00,
      0x10,
      0xA1,
      0x18,
      0x01,
      0x22,
      0x06,
      0x08,
      0x01,
      0x12,
      0x02,
      0x44,
      0x4D,
      0x50,
      0x01,
    ]);
  });
}
