import 'package:latlong2/latlong.dart';

import 'geo.dart' as geo;

/// One recorded point of the own trail.
class TrackPoint {
  const TrackPoint({
    required this.latitude,
    required this.longitude,
    required this.altitudeM,
    required this.at,
  });

  final double latitude;
  final double longitude;
  final int altitudeM;
  final DateTime at;

  LatLng get latLng => LatLng(latitude, longitude);

  Map<String, dynamic> toJson() => {
    'lat': latitude,
    'lon': longitude,
    'alt': altitudeM,
    'at': at.toUtc().toIso8601String(),
  };

  static TrackPoint fromJson(Map<String, dynamic> json) => TrackPoint(
    latitude: (json['lat'] as num).toDouble(),
    longitude: (json['lon'] as num).toDouble(),
    altitudeM: (json['alt'] as num?)?.toInt() ?? 0,
    at: DateTime.parse(json['at'] as String),
  );
}

/// Length of a trail in kilometres.
double trackLengthKm(List<TrackPoint> track) {
  var total = 0.0;
  for (var i = 1; i < track.length; i++) {
    total += geo.distanceKm(track[i - 1].latLng, track[i].latLng);
  }
  return total;
}
