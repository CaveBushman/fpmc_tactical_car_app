
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
    required this.time,
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
  final String time;
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
      time: time,
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

  Map<String, dynamic> toJson() {
    return {
      'sender': sender,
      'body': body,
      'time': time,
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
      time: json['time']?.toString() ?? '--:--',
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

  static const demoMessages = [
    MeshMessage(
      sender: 'RAVEN-2',
      body: 'Na pozici. Vidim trasu k bodu BRAVO.',
      time: '14:22',
      groupId: 'alpha',
      priority: false,
    ),
    MeshMessage(
      sender: 'SCOUT-3',
      body: 'Posilam novou pozici pres Meshtastic.',
      time: '14:19',
      groupId: 'alpha',
    ),
    MeshMessage(
      sender: 'PTT SERVER',
      body: 'ALPHA voice channel online. Floor control aktivni.',
      time: '14:18',
      groupId: 'alpha',
      internetVoice: true,
    ),
    MeshMessage(
      sender: 'MED-4',
      body: 'Baterie nizka, zustavam u vozidla.',
      time: '14:14',
      groupId: 'med',
      priority: true,
    ),
    MeshMessage(
      sender: 'COMMAND',
      body: 'BRAVO zustava jako zalozni presunovy kanal.',
      time: '14:11',
      groupId: 'bravo',
    ),
    MeshMessage(
      sender: 'HQ',
      body: 'Kontrola spojeni a prihlaseni posadek.',
      time: '14:05',
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
  });

  final String id;
  final String name;
  final String transportLabel;
  final IconData icon;
  final int channelIndex;
  final bool encrypted;

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
