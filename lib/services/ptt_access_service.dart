import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'auth_service.dart';

class PttChannelAccess {
  const PttChannelAccess({
    required this.channel,
    required this.keyBytes,
  });

  final String channel;
  final List<int> keyBytes;
}

class PttAccessService {
  const PttAccessService();

  PttChannelAccess authorize({
    required AuthSession session,
    required String groupId,
  }) {
    if (!session.allowedGroupIds.contains(groupId)) {
      throw StateError('User ${session.userName} is not allowed to access PTT group $groupId.');
    }

    final material = utf8.encode('1stpmc:${session.pttToken}:$groupId');
    final digest = sha256.convert(material);
    return PttChannelAccess(
      channel: groupId.toUpperCase(),
      keyBytes: digest.bytes,
    );
  }
}
