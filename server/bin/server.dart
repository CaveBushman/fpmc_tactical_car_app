import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:tactical_server/tactical_server.dart';

/// Environment:
/// - `PORT` (default 8080)
/// - `SESSION_SECRET` – HMAC secret for app session tokens (≥ 32 chars)
/// - `LIVEKIT_URL` – URL the app connects to, e.g. wss://ptt.example.cz
/// - `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` – same as in livekit.yaml
/// - `USERS_FILE` (default config/users.json): initial users; afterwards
///   the editable copy in `DATA_DIR/users.json` is used
/// - `DATA_DIR` (default data)
/// - `MAX_DEVICES_PER_USER` (default 2, 0 = unlimited)
Future<void> main() async {
  String require(String name) {
    final value = Platform.environment[name];
    if (value == null || value.isEmpty) {
      stderr.writeln('Missing environment variable $name');
      exit(64);
    }
    return value;
  }

  final sessionSecret = require('SESSION_SECRET');
  if (sessionSecret.length < 32) {
    stderr.writeln('SESSION_SECRET must be at least 32 characters');
    exit(64);
  }
  final dataDir = Platform.environment['DATA_DIR'] ?? 'data';

  final api = TacticalApi(
    users: UserDirectory.fromFile(
      Platform.environment['USERS_FILE'] ?? 'config/users.json',
      stateFile: File('$dataDir/users.json'),
    ),
    maxDevicesPerUser:
        int.tryParse(Platform.environment['MAX_DEVICES_PER_USER'] ?? '') ?? 2,
    sessions: SessionIssuer(secret: sessionSecret),
    liveKit: LiveKitTokenIssuer(
      apiKey: require('LIVEKIT_API_KEY'),
      apiSecret: require('LIVEKIT_API_SECRET'),
    ),
    liveKitUrl: require('LIVEKIT_URL'),
    groups: GroupDirectory.load(File('$dataDir/groups.json')),
    keys: GroupKeyStore(file: File('$dataDir/group_keys.json')),
    audit: AuditLog(file: File('$dataDir/audit.jsonl')),
  );

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(api.handler);
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('tactical_server listening on :${server.port}');
}
