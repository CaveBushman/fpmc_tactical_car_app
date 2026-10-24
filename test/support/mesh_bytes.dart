import 'dart:convert';

/// Minimal protobuf builders for hand-crafted Meshtastic FromRadio frames.
List<int> pbMessage(int field, List<int> value) => pbBytes(field, value);

List<int> pbString(int field, String value) =>
    pbBytes(field, utf8.encode(value));

List<int> pbBytes(int field, List<int> value) => [
  ..._key(field, 2),
  ..._rawVarint(value.length),
  ...value,
];

List<int> pbVarint(int field, int value) => [
  ..._key(field, 0),
  ..._rawVarint(value),
];

List<int> pbFixed32(int field, int value) {
  final unsigned = value & 0xFFFFFFFF;
  return [
    ..._key(field, 5),
    unsigned & 0xFF,
    (unsigned >> 8) & 0xFF,
    (unsigned >> 16) & 0xFF,
    (unsigned >> 24) & 0xFF,
  ];
}

List<int> fromRadioText({
  required int from,
  required String text,
  int to = 0xFFFFFFFF,
  int channel = 0,
  int? packetId,
}) {
  return pbMessage(2, [
    ...pbFixed32(1, from),
    ...pbFixed32(2, to),
    ...pbVarint(3, channel),
    ...pbMessage(4, [...pbVarint(1, 1), ...pbString(2, text)]),
    if (packetId != null) ...pbFixed32(6, packetId),
  ]);
}

List<int> fromRadioNodeInfo({
  required int nodeNum,
  String? shortName,
  double? latitude,
  double? longitude,
}) {
  return pbMessage(4, [
    ...pbVarint(1, nodeNum),
    if (shortName != null) ...pbMessage(2, pbString(3, shortName)),
    if (latitude != null && longitude != null)
      ...pbMessage(3, [
        ...pbFixed32(1, (latitude * 1e7).round()),
        ...pbFixed32(2, (longitude * 1e7).round()),
      ]),
  ]);
}

List<int> fromRadioTelemetry({required int from, required int battery}) {
  return pbMessage(2, [
    ...pbFixed32(1, from),
    ...pbFixed32(2, 0xFFFFFFFF),
    ...pbMessage(4, [
      ...pbVarint(1, 67),
      ...pbMessage(2, pbMessage(2, pbVarint(1, battery))),
    ]),
  ]);
}

List<int> fromRadioWaypoint({
  required int from,
  required int id,
  double latitude = 50.09,
  double longitude = 14.43,
  String name = '',
  String description = '',
  int expire = 0,
}) {
  return pbMessage(2, [
    ...pbFixed32(1, from),
    ...pbFixed32(2, 0xFFFFFFFF),
    ...pbMessage(4, [
      ...pbVarint(1, 8),
      ...pbMessage(2, [
        ...pbVarint(1, id),
        ...pbFixed32(2, (latitude * 1e7).round()),
        ...pbFixed32(3, (longitude * 1e7).round()),
        if (expire != 0) ...pbVarint(4, expire),
        if (name.isNotEmpty) ...pbString(6, name),
        if (description.isNotEmpty) ...pbString(7, description),
      ]),
    ]),
  ]);
}

List<int> fromRadioChannel({
  required int index,
  required int role,
  String name = '',
}) => pbMessage(10, [
  ...pbVarint(1, index),
  if (name.isNotEmpty) ...pbMessage(2, pbString(3, name)),
  ...pbVarint(3, role),
]);

List<int> fromRadioMyInfo(int nodeNum) => pbMessage(3, pbVarint(1, nodeNum));

List<int> _key(int field, int wireType) => _rawVarint((field << 3) | wireType);

List<int> _rawVarint(int value) {
  final bytes = <int>[];
  var remaining = value;
  while (remaining >= 0x80) {
    bytes.add((remaining & 0x7F) | 0x80);
    remaining >>= 7;
  }
  bytes.add(remaining);
  return bytes;
}
