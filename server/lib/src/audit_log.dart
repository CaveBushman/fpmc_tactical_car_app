import 'dart:convert';
import 'dart:io';

/// Append-only JSON-lines audit trail of security relevant events.
class AuditLog {
  AuditLog({this.file});

  final File? file;
  final List<Map<String, dynamic>> recent = [];

  void record(
    String event, {
    String? user,
    Map<String, Object?> details = const {},
  }) {
    final entry = {
      'at': DateTime.now().toUtc().toIso8601String(),
      'event': event,
      'user': ?user,
      ...details,
    };
    recent.add(entry);
    if (recent.length > 500) {
      recent.removeAt(0);
    }
    final file = this.file;
    if (file != null) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        '${jsonEncode(entry)}\n',
        mode: FileMode.append,
        flush: true,
      );
    }
  }
}
