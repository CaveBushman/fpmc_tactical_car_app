import 'dart:convert';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import '../models/messaging.dart';
import '../models/navigation.dart';
import '../models/track.dart';

/// GPX 1.1 with mission waypoints and the own trail (QGIS, Google Earth,
/// OsmAnd, Garmin BaseCamp…).
String buildMissionGpx({
  required String missionName,
  required List<TrackPoint> track,
  required List<TacticalWaypoint> waypoints,
  required DateTime exportedAt,
}) {
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<gpx version="1.1" creator="Tactical Mesh" '
      'xmlns="http://www.topografix.com/GPX/1/1">',
    )
    ..writeln('  <metadata>')
    ..writeln('    <name>${_xml(missionName)}</name>')
    ..writeln('    <time>${exportedAt.toUtc().toIso8601String()}</time>')
    ..writeln('  </metadata>');
  for (final waypoint in waypoints) {
    buffer
      ..writeln(
        '  <wpt lat="${waypoint.latitude.toStringAsFixed(7)}" '
        'lon="${waypoint.longitude.toStringAsFixed(7)}">',
      )
      ..writeln('    <name>${_xml(waypoint.code)}</name>');
    final description = [
      waypoint.note,
      'MGRS ${waypoint.mgrs}',
      if (waypoint.sharedBy != null) 'od ${waypoint.sharedBy}',
    ].where((part) => part.isNotEmpty).join(' | ');
    buffer
      ..writeln('    <desc>${_xml(description)}</desc>')
      ..writeln('    <type>${_xml(waypoint.typeLabel)}</type>')
      ..writeln('  </wpt>');
  }
  if (track.isNotEmpty) {
    buffer
      ..writeln('  <trk>')
      ..writeln('    <name>${_xml(missionName)} – stopa</name>')
      ..writeln('    <trkseg>');
    for (final point in track) {
      buffer
        ..writeln(
          '      <trkpt lat="${point.latitude.toStringAsFixed(7)}" '
          'lon="${point.longitude.toStringAsFixed(7)}">',
        )
        ..writeln('        <ele>${point.altitudeM}</ele>')
        ..writeln('        <time>${point.at.toUtc().toIso8601String()}</time>')
        ..writeln('      </trkpt>');
    }
    buffer
      ..writeln('    </trkseg>')
      ..writeln('  </trk>');
  }
  buffer.writeln('</gpx>');
  return buffer.toString();
}

/// Message log as semicolon-separated CSV (opens in Czech Excel locales),
/// oldest first.
String buildMessagesCsv({
  required List<MeshMessage> messages,
  required List<CommunicationGroup> groups,
}) {
  String groupName(String id) =>
      groups.where((group) => group.id == id).firstOrNull?.name ?? id;
  final rows = <List<String>>[
    [
      'cas_utc',
      'skupina',
      'od',
      'komu',
      'text',
      'doruceni',
      'cesta',
      'priorita',
    ],
    for (final message in messages.reversed)
      [
        message.sentAt.toUtc().toIso8601String(),
        groupName(message.groupId),
        message.sender,
        message.targetLabel ?? '',
        message.body,
        message.delivery.name,
        message.viaInternet ? 'internet' : 'LoRa',
        message.priority ? 'ano' : 'ne',
      ],
  ];
  return rows.map((row) => row.map(_csv).join(';')).join('\r\n');
}

String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _csv(String value) {
  // Cells starting like formulas could execute in spreadsheet apps.
  final safe = RegExp(r'^[=+\-@\t\r]').hasMatch(value) ? "'$value" : value;
  final needsQuotes =
      safe.contains(';') ||
      safe.contains('"') ||
      safe.contains('\n') ||
      safe.contains('\r');
  return needsQuotes ? '"${safe.replaceAll('"', '""')}"' : safe;
}

class ExportFile {
  const ExportFile({
    required this.name,
    required this.mimeType,
    required this.content,
  });

  final String name;
  final String mimeType;
  final String content;
}

/// Hands export files to the system share sheet (replaceable in tests).
abstract class MissionSharer {
  factory MissionSharer.system() = _SystemMissionSharer;

  Future<void> share(List<ExportFile> files, {required String subject});
}

class _SystemMissionSharer implements MissionSharer {
  @override
  Future<void> share(List<ExportFile> files, {required String subject}) async {
    await SharePlus.instance.share(
      ShareParams(
        subject: subject,
        files: [
          for (final file in files)
            XFile.fromData(
              Uint8List.fromList(utf8.encode(file.content)),
              mimeType: file.mimeType,
              name: file.name,
            ),
        ],
        fileNameOverrides: [for (final file in files) file.name],
      ),
    );
  }
}
