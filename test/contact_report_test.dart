import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tactical_car_app/models/geo.dart';
import 'package:tactical_car_app/models/reports.dart';

void main() {
  test('MGRS parses back to the formatted point', () {
    const prague = LatLng(50.087451, 14.420671);
    final mgrs = formatMgrs(prague.latitude, prague.longitude);
    final parsed = parseMgrs(mgrs)!;
    expect(distanceKm(prague, parsed), lessThan(0.002));
    expect(parseMgrs('nonsense'), isNull);
  });

  test('destination is consistent with distance and bearing', () {
    const start = LatLng(50.0, 14.0);
    final end = destination(start, 90, 1000);
    expect(distanceKm(start, end), closeTo(1.0, 0.001));
    expect(bearingDeg(start, end), closeTo(90, 0.1));
  });

  test('parses a CONTACT report into an estimated position', () {
    final report = ContactReport.parse(
      'CONTACT | MGRS 33U VR 58556 48514 | DIR 090 | DIST 300 m | TYPE VOZIDLO | SIZE 2 | pozorovano, bez palby',
    )!;

    expect(report.bearingDeg, 90);
    expect(report.distanceM, 300);
    expect(report.contactType, 'VOZIDLO');
    expect(report.size, '2');
    expect(report.note, 'pozorovano, bez palby');
    expect(distanceKm(report.observer, report.position), closeTo(0.3, 0.002));
    expect(bearingDeg(report.observer, report.position), closeTo(90, 0.5));
  });

  test('skips reports that cannot be plotted', () {
    expect(ContactReport.parse('NA POZICI | MGRS 33U VR 1 2'), isNull);
    expect(
      ContactReport.parse(
        'CONTACT | MGRS 33U VR 58556 48514 | DIR SV | DIST 300 m',
      ),
      isNull,
    );
    expect(
      ContactReport.parse('CONTACT | MGRS xx | DIR 90 | DIST 300 m'),
      isNull,
    );
  });
}
