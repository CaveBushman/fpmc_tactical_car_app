import 'package:flutter/material.dart';

import 'mesh_node.dart';

enum MessageDelivery {
  /// Incoming message.
  received,

  /// Being written to the T-Beam.
  sending,

  /// Could not be handed to the T-Beam (not connected); can be retried.
  notSent,

  /// Handed to the T-Beam; for direct messages an ACK is still pending.
  sent,

  /// Destination acknowledged the direct message.
  delivered,

  /// Mesh reported a routing error (NAK / max retransmit); can be retried.
  failed,
}

class MeshMessage {
  const MeshMessage({
    required this.sender,
    required this.body,
    required this.sentAt,
    required this.groupId,
    this.targetLabel,
    this.delivery = MessageDelivery.received,
    this.priority = false,
    this.internetVoice = false,
    this.packetId,
    this.fromNode,
    this.toNode,
  });

  final String sender;
  final String body;

  /// When the message was sent or received (UTC-normalised on save).
  final DateTime sentAt;
  final String groupId;
  final String? targetLabel;
  final MessageDelivery delivery;
  final bool priority;
  final bool internetVoice;

  /// Meshtastic packet id and sender node, used to drop duplicate deliveries
  /// and to match routing ACKs to outgoing messages.
  final int? packetId;
  final int? fromNode;

  /// Destination node of an outgoing direct message (null = group).
  final int? toNode;

  bool get canRetry =>
      delivery == MessageDelivery.notSent || delivery == MessageDelivery.failed;

  MeshMessage copyWith({MessageDelivery? delivery, int? packetId}) {
    return MeshMessage(
      sender: sender,
      body: body,
      sentAt: sentAt,
      groupId: groupId,
      targetLabel: targetLabel,
      delivery: delivery ?? this.delivery,
      priority: priority,
      internetVoice: internetVoice,
      packetId: packetId ?? this.packetId,
      fromNode: fromNode,
      toNode: toNode,
    );
  }

  /// `HH:mm` for today, `d.M. HH:mm` for older messages (local time).
  String timeLabel(DateTime now) {
    final local = sentAt.toLocal();
    final nowLocal = now.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    final clock = '${two(local.hour)}:${two(local.minute)}';
    final sameDay =
        local.year == nowLocal.year &&
        local.month == nowLocal.month &&
        local.day == nowLocal.day;
    return sameDay ? clock : '${local.day}.${local.month}. $clock';
  }

  static DateTime _parseSentAt(Map<String, dynamic> json) {
    final parsed = DateTime.tryParse(json['sentAt']?.toString() ?? '');
    if (parsed != null) {
      return parsed;
    }
    // Older snapshots stored only "HH:mm": assume the most recent such time.
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})$',
    ).firstMatch(json['time']?.toString() ?? '');
    if (match == null) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    final now = DateTime.now();
    var value = DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
    if (value.isAfter(now)) {
      value = value.subtract(const Duration(days: 1));
    }
    return value;
  }

  Map<String, dynamic> toJson() {
    return {
      'sender': sender,
      'body': body,
      'sentAt': sentAt.toUtc().toIso8601String(),
      'groupId': groupId,
      'targetLabel': targetLabel,
      'delivery': delivery.name,
      'priority': priority,
      'internetVoice': internetVoice,
      'packetId': packetId,
      'fromNode': fromNode,
      'toNode': toNode,
    };
  }

  static MeshMessage fromJson(Map<String, dynamic> json) {
    var delivery = MessageDelivery.values.firstWhere(
      (value) => value.name == json['delivery'],
      orElse: () => json['pending'] == true
          ? MessageDelivery.notSent
          : MessageDelivery.received,
    );
    // A write interrupted by an app restart never reached the radio.
    if (delivery == MessageDelivery.sending) {
      delivery = MessageDelivery.notSent;
    }
    return MeshMessage(
      sender: json['sender']?.toString() ?? 'UNKNOWN',
      body: json['body']?.toString() ?? '',
      sentAt: _parseSentAt(json),
      groupId: json['groupId']?.toString() ?? 'alpha',
      targetLabel: json['targetLabel']?.toString(),
      delivery: delivery,
      priority: json['priority'] == true,
      internetVoice: json['internetVoice'] == true,
      packetId: (json['packetId'] as num?)?.toInt(),
      fromNode: (json['fromNode'] as num?)?.toInt(),
      toNode: (json['toNode'] as num?)?.toInt(),
    );
  }

  static List<MeshMessage> demoMessages(DateTime now) => [
    MeshMessage(
      sender: 'RAVEN-2',
      body: 'Na pozici. Vidim trasu k bodu BRAVO.',
      sentAt: now.subtract(const Duration(minutes: 3)),
      groupId: 'alpha',
      priority: false,
    ),
    MeshMessage(
      sender: 'SCOUT-3',
      body: 'Posilam novou pozici pres Meshtastic.',
      sentAt: now.subtract(const Duration(minutes: 6)),
      groupId: 'alpha',
    ),
    MeshMessage(
      sender: 'PTT SERVER',
      body: 'ALPHA voice channel online. Floor control aktivni.',
      sentAt: now.subtract(const Duration(minutes: 7)),
      groupId: 'alpha',
      internetVoice: true,
    ),
    MeshMessage(
      sender: 'MED-4',
      body: 'Baterie nizka, zustavam u vozidla.',
      sentAt: now.subtract(const Duration(minutes: 11)),
      groupId: 'med',
      priority: true,
    ),
    MeshMessage(
      sender: 'COMMAND',
      body: 'BRAVO zustava jako zalozni presunovy kanal.',
      sentAt: now.subtract(const Duration(minutes: 14)),
      groupId: 'bravo',
    ),
    MeshMessage(
      sender: 'HQ',
      body: 'Kontrola spojeni a prihlaseni posadek.',
      sentAt: now.subtract(const Duration(minutes: 20)),
      groupId: 'command',
    ),
  ];
}

class CommunicationGroup {
  const CommunicationGroup({
    required this.id,
    required this.name,
    required this.transportLabel,
    required this.icon,
    required this.channelIndex,
    this.encrypted = true,
    this.pttEnabled = true,
  });

  /// Group configured on the backend.
  factory CommunicationGroup.configured({
    required String id,
    required String name,
    required int channelIndex,
    bool pttEnabled = true,
    String description = '',
  }) => CommunicationGroup(
    id: id,
    name: name,
    channelIndex: channelIndex,
    pttEnabled: pttEnabled,
    transportLabel: description.isNotEmpty
        ? description
        : (pttEnabled ? 'Meshtastic + PTT' : 'Meshtastic'),
    icon: switch (id) {
      'alpha' => Icons.radio,
      'bravo' => Icons.settings_input_antenna,
      'med' => Icons.medical_services_outlined,
      'command' => Icons.admin_panel_settings_outlined,
      _ => Icons.groups_outlined,
    },
  );

  final String id;
  final String name;
  final String transportLabel;
  final IconData icon;

  /// Meshtastic channel slot (0–7) for the group's text traffic.
  final int channelIndex;
  final bool encrypted;
  final bool pttEnabled;

  static const demoGroups = [
    CommunicationGroup(
      id: 'alpha',
      name: 'ALPHA',
      transportLabel: 'Meshtastic + PTT',
      icon: Icons.radio,
      channelIndex: 0,
    ),
    CommunicationGroup(
      id: 'bravo',
      name: 'BRAVO',
      transportLabel: 'Meshtastic',
      icon: Icons.settings_input_antenna,
      channelIndex: 1,
    ),
    CommunicationGroup(
      id: 'med',
      name: 'MED',
      transportLabel: 'prioritní',
      icon: Icons.medical_services_outlined,
      channelIndex: 2,
    ),
    CommunicationGroup(
      id: 'command',
      name: 'COMMAND',
      transportLabel: 'šifrované',
      icon: Icons.admin_panel_settings_outlined,
      channelIndex: 3,
    ),
  ];
}

class MeshMessageDraft {
  const MeshMessageDraft({
    required this.text,
    required this.groupId,
    this.directNode,
    this.priority = false,
  });

  final String text;
  final String groupId;
  final MeshNode? directNode;
  final bool priority;
}

/// A channel slot as configured on the connected T-Beam.
class RadioChannel {
  const RadioChannel({
    required this.index,
    required this.name,
    required this.role,
  });

  final int index;
  final String name;

  /// 0 disabled, 1 primary, 2 secondary (Meshtastic Channel.Role).
  final int role;

  bool get enabled => role != 0;

  String get roleLabel => switch (role) {
    1 => 'PRIMARY',
    2 => 'SECONDARY',
    _ => 'VYPNUTO',
  };
}
