/// SOS signalling carried in ordinary team text messages, so it works over
/// LoRa and the internet fallback alike and stays readable in other apps:
///
/// - call:   `SOS | RAVEN-1 | MGRS 33U VR 58556 48514 | LAT 50.087451 | LON 14.420671`
/// - cancel: `SOS ZRUŠENO | RAVEN-1`
/// - ack:    `SOS PŘIJATO | MEDIC -> RAVEN-1`
sealed class SosSignal {
  const SosSignal();

  static String call({
    required String callSign,
    required String mgrs,
    required double latitude,
    required double longitude,
  }) =>
      'SOS | $callSign | MGRS $mgrs | LAT ${latitude.toStringAsFixed(6)} | '
      'LON ${longitude.toStringAsFixed(6)}';

  static String cancel(String callSign) => 'SOS ZRUŠENO | $callSign';

  static String ack({required String from, required String to}) =>
      'SOS PŘIJATO | $from -> $to';

  static SosSignal? parse(String text) {
    final trimmed = text.trim();
    if (trimmed == 'SOS') {
      return const SosCall(); // legacy quick message without position
    }
    final parts = trimmed.split('|').map((part) => part.trim()).toList();
    switch (parts.first) {
      case 'SOS ZRUŠENO' when parts.length >= 2:
        return SosCancel(parts[1]);
      case 'SOS PŘIJATO' when parts.length >= 2:
        final names = parts[1].split('->').map((p) => p.trim()).toList();
        return names.length == 2 ? SosAck(from: names[0], to: names[1]) : null;
      case 'SOS':
        String? field(String key) {
          for (final part in parts) {
            if (part.startsWith('$key ')) {
              return part.substring(key.length + 1).trim();
            }
          }
          return null;
        }
        final latitude = double.tryParse(field('LAT') ?? '');
        final longitude = double.tryParse(field('LON') ?? '');
        final validPosition =
            latitude != null &&
            longitude != null &&
            latitude.abs() <= 90 &&
            longitude.abs() <= 180;
        return SosCall(
          callSign: parts.length >= 2 && !parts[1].contains(' ')
              ? parts[1]
              : null,
          mgrs: field('MGRS'),
          latitude: validPosition ? latitude : null,
          longitude: validPosition ? longitude : null,
        );
      default:
        return null;
    }
  }
}

class SosCall extends SosSignal {
  const SosCall({this.callSign, this.mgrs, this.latitude, this.longitude});

  /// Null for the legacy plain "SOS": use the message sender.
  final String? callSign;
  final String? mgrs;
  final double? latitude;
  final double? longitude;
}

class SosCancel extends SosSignal {
  const SosCancel(this.callSign);

  final String callSign;
}

class SosAck extends SosSignal {
  const SosAck({required this.from, required this.to});

  final String from;
  final String to;
}

/// A teammate's active distress call as shown to this operator.
class SosAlert {
  const SosAlert({
    required this.callSign,
    required this.lastAt,
    this.mgrs,
    this.latitude,
    this.longitude,
    this.acknowledged = false,
  });

  final String callSign;
  final DateTime lastAt;
  final String? mgrs;
  final double? latitude;
  final double? longitude;

  /// Hidden from the banner after "Beru"; the map point stays.
  final bool acknowledged;

  Map<String, dynamic> toJson() => {
    'callSign': callSign,
    'lastAt': lastAt.toUtc().toIso8601String(),
    'mgrs': ?mgrs,
    'lat': ?latitude,
    'lon': ?longitude,
    'acknowledged': acknowledged,
  };

  static SosAlert? fromJson(Map<String, dynamic> json) {
    final callSign = json['callSign'];
    final lastAt = DateTime.tryParse(json['lastAt']?.toString() ?? '');
    if (callSign is! String || lastAt == null) {
      return null;
    }
    return SosAlert(
      callSign: callSign,
      lastAt: lastAt.toLocal(),
      mgrs: json['mgrs'] as String?,
      latitude: (json['lat'] as num?)?.toDouble(),
      longitude: (json['lon'] as num?)?.toDouble(),
      acknowledged: json['acknowledged'] == true,
    );
  }

  SosAlert copyWith({bool? acknowledged}) => SosAlert(
    callSign: callSign,
    lastAt: lastAt,
    mgrs: mgrs,
    latitude: latitude,
    longitude: longitude,
    acknowledged: acknowledged ?? this.acknowledged,
  );
}
