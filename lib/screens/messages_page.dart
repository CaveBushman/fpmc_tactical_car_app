import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../models/geo.dart';
import '../models/mesh_node.dart';
import '../models/messaging.dart';
import '../models/navigation.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({
    required this.messages,
    required this.groups,
    required this.nodes,
    required this.selfNode,
    required this.waypoints,
    required this.selectedGroupIndex,
    required this.onGroupSelected,
    required this.onSend,
    this.onRetry,
    this.onAcknowledge,
    this.onSos,
    this.unreadIn,
    this.quickMessages = const [],
    this.directTo,
    this.onDirectConsumed,
    this.onShowOnMap,
    this.onNavigateToSender,
    super.key,
  });

  final List<MeshMessage> messages;
  final List<CommunicationGroup> groups;
  final List<MeshNode> nodes;
  final MeshNode selfNode;
  final List<TacticalWaypoint> waypoints;
  final int selectedGroupIndex;
  final ValueChanged<int> onGroupSelected;
  final Future<void> Function(MeshMessageDraft draft) onSend;
  final ValueChanged<MeshMessage>? onRetry;

  /// Confirms a priority order from the commanders' panel ("Rozumím").
  final ValueChanged<MeshMessage>? onAcknowledge;

  /// Starts (or, while active, cancels) the repeated distress call.
  final VoidCallback? onSos;

  /// Unread incoming messages per group id.
  final int Function(String groupId)? unreadIn;

  /// One-tap templates sent to the selected group.
  final List<String> quickMessages;

  /// Request from elsewhere (team card): open a direct message to this
  /// callsign; [onDirectConsumed] is called once it is applied.
  final String? directTo;
  final VoidCallback? onDirectConsumed;

  /// Message actions: show a position from the text on the map, navigate
  /// to the sender.
  final ValueChanged<LatLng>? onShowOnMap;
  final ValueChanged<String>? onNavigateToSender;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _nodeSearchController = TextEditingController();
  final TextEditingController _messageSearchController =
      TextEditingController();
  bool _priorityOnly = false;
  bool _directMode = false;
  int _selectedNodeIndex = 0;

  @override
  void initState() {
    super.initState();
    _nodeSearchController.addListener(() {
      if (!mounted) {
        return;
      }
      setState(() => _selectedNodeIndex = 0);
    });
    _messageSearchController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    _applyDirectTo();
  }

  /// Switches the composer to a direct message for [MessagesPage.directTo].
  void _applyDirectTo() {
    final callSign = widget.directTo;
    if (callSign == null) {
      return;
    }
    _directTo(callSign);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onDirectConsumed?.call(),
    );
  }

  void _directTo(String callSign) {
    _directMode = true;
    _nodeSearchController.text = callSign;
    _selectedNodeIndex = 0;
  }

  @override
  void didUpdateWidget(covariant MessagesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.directTo != null && widget.directTo != oldWidget.directTo) {
      _applyDirectTo();
    }
    if (_selectedNodeIndex >= _filteredDirectNodes.length) {
      _selectedNodeIndex = 0;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _nodeSearchController.dispose();
    _messageSearchController.dispose();
    super.dispose();
  }

  List<MeshNode> get _filteredDirectNodes {
    return widget.nodes
        .where((node) => node.matchesSearch(_nodeSearchController.text))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final selectedGroup = widget.groups[widget.selectedGroupIndex];
    final query = _messageSearchController.text;
    final filteredMessages = widget.messages
        .where(
          (message) =>
              message.groupId == selectedGroup.id &&
              (!_priorityOnly || message.priority) &&
              message.matchesSearch(query),
        )
        .toList();
    final filteredDirectNodes = _filteredDirectNodes;
    final header = <Widget>[
      SizedBox(
        height: 72,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          scrollDirection: Axis.horizontal,
          itemCount: widget.groups.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final group = widget.groups[index];
            final selected = index == widget.selectedGroupIndex;
            return ChoiceChip(
              selected: selected,
              onSelected: (_) => widget.onGroupSelected(index),
              avatar: UnreadBadge(
                key: ValueKey('unread-${group.id}'),
                count: widget.unreadIn?.call(group.id) ?? 0,
                child: Icon(
                  group.icon,
                  size: 18,
                  color: selected ? sand : sand.withValues(alpha: 0.82),
                ),
              ),
              label: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    group.transportLabel,
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              selectedColor: rangerGreen.withValues(alpha: 0.95),
              backgroundColor: panelGreen,
              side: BorderSide(
                color: selected
                    ? tacticalKhaki.withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.12),
              ),
            );
          },
        ),
      ),
      MessageComposer(
        controller: _textController,
        nodeSearchController: _nodeSearchController,
        directMode: _directMode,
        nodes: filteredDirectNodes,
        selectedNodeIndex: _selectedNodeIndex,
        selectedGroup: selectedGroup,
        onModeChanged: (value) => setState(() => _directMode = value),
        onNodeChanged: (index) => setState(() => _selectedNodeIndex = index),
        onSend: _send,
      ),
      if (widget.quickMessages.isNotEmpty)
        SizedBox(
          height: 44,
          child: ListView.separated(
            key: const ValueKey('quick-messages'),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            scrollDirection: Axis.horizontal,
            itemCount: widget.quickMessages.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final text = widget.quickMessages[index];
              return ActionChip(
                label: Text(
                  text,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                backgroundColor: panelGreen,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                onPressed: () => _sendQuickMessage(text),
              );
            },
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: QuickActionButton(
                label: 'OK',
                icon: Icons.check_circle_outline,
                onPressed: () => _sendQuickMessage('OK'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: QuickActionButton(
                label: 'NA POZICI',
                icon: Icons.place_outlined,
                onPressed: _sendPositionReport,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: QuickActionButton(
                label: 'SOS',
                icon: Icons.warning_amber_outlined,
                danger: true,
                onPressed:
                    widget.onSos ??
                    () => _sendQuickMessage('SOS', priority: true),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: ReportActionButton(
                label: 'CONTACT',
                icon: Icons.radar_outlined,
                onPressed: _showContactReportSheet,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ReportActionButton(
                label: 'MEDEVAC',
                icon: Icons.medical_services_outlined,
                danger: true,
                onPressed: _showMedevacReportSheet,
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: ReportActionButton(
          label: 'SITREP',
          icon: Icons.assignment_turned_in_outlined,
          onPressed: _showSitrepReportSheet,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TacticalSearchField(
                key: const ValueKey('message-search'),
                controller: _messageSearchController,
                label: 'Hledat ve zprávách',
                hint: 'Text, odesílatel',
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              key: const ValueKey('priority-only'),
              avatar: const Icon(Icons.priority_high, size: 16),
              label: const Text('Prioritní'),
              selected: _priorityOnly,
              onSelected: (value) => setState(() => _priorityOnly = value),
            ),
          ],
        ),
      ),
      if (filteredMessages.isEmpty &&
          (query.trim().isNotEmpty || _priorityOnly))
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Text(
            'Žádná zpráva neodpovídá hledání.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
        ),
    ];
    Widget messageCard(MeshMessage message) {
      final onRetry = widget.onRetry;
      final onAcknowledge = widget.onAcknowledge;
      return MessageCard(
        message: message,
        onRetry: onRetry == null ? null : () => onRetry(message),
        onAcknowledge: onAcknowledge == null
            ? null
            : () => onAcknowledge(message),
        onLongPress: () => _showMessageActions(message),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Too short for the fixed controls plus a usable list (phone in
        // landscape): scroll everything together instead.
        if (constraints.maxHeight <
            MediaQuery.textScalerOf(context).scale(600)) {
          return ListView(
            key: const ValueKey('messages-scroll'),
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              ...header,
              for (final message in filteredMessages)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: messageCard(message),
                ),
            ],
          );
        }
        return Column(
          children: [
            ...header,
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: filteredMessages.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) =>
                    messageCard(filteredMessages[index]),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Long press on a message: map, reply, navigate, copy.
  Future<void> _showMessageActions(MeshMessage message) async {
    final position = coordinatesInText(message.body);
    final own = message.sender == widget.selfNode.callSign;
    final known = widget.nodes.any((node) => node.callSign == message.sender);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: panelGreen,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (position != null && widget.onShowOnMap != null)
              ListTile(
                key: const ValueKey('message-show-on-map'),
                leading: const Icon(Icons.map_outlined),
                title: const Text('Ukázat na mapě'),
                subtitle: Text(
                  formatMgrs(position.latitude, position.longitude),
                ),
                onTap: () => Navigator.of(context).pop('map'),
              ),
            if (!own && known)
              ListTile(
                key: const ValueKey('message-reply-direct'),
                leading: const Icon(Icons.reply),
                title: Text('Odpovědět soukromě ${message.sender}'),
                onTap: () => Navigator.of(context).pop('reply'),
              ),
            if (!own && known && widget.onNavigateToSender != null)
              ListTile(
                leading: const Icon(Icons.navigation_outlined),
                title: Text('Navigovat k ${message.sender}'),
                onTap: () => Navigator.of(context).pop('navigate'),
              ),
            ListTile(
              key: const ValueKey('message-copy'),
              leading: const Icon(Icons.copy),
              title: const Text('Kopírovat text'),
              onTap: () => Navigator.of(context).pop('copy'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    switch (action) {
      case 'map':
        widget.onShowOnMap?.call(position!);
      case 'reply':
        setState(() => _directTo(message.sender));
      case 'navigate':
        widget.onNavigateToSender?.call(message.sender);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.body));
    }
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      return;
    }

    final filteredDirectNodes = _filteredDirectNodes;
    if (_directMode && filteredDirectNodes.isEmpty) {
      return;
    }
    final directNode = _directMode
        ? filteredDirectNodes[_selectedNodeIndex]
        : null;
    await widget.onSend(
      MeshMessageDraft(
        text: text,
        groupId: widget.groups[widget.selectedGroupIndex].id,
        directNode: directNode,
      ),
    );
    _textController.clear();
  }

  Future<void> _sendQuickMessage(String text, {bool priority = false}) async {
    await widget.onSend(
      MeshMessageDraft(
        text: text,
        groupId: widget.groups[widget.selectedGroupIndex].id,
        priority: priority,
      ),
    );
  }

  Future<void> _sendPositionReport() async {
    final self = widget.selfNode;
    final text =
        'NA POZICI | MGRS ${self.mgrs} | LAT ${self.latitude.toStringAsFixed(6)} | LON ${self.longitude.toStringAsFixed(6)}';
    await _sendQuickMessage(text);
  }

  Future<void> _showContactReportSheet() async {
    final bearingController = TextEditingController(text: '090');
    final distanceController = TextEditingController(text: '300');
    final sizeController = TextEditingController(text: '2-4');
    final noteController = TextEditingController(text: 'pozorovano, bez palby');
    var contactType = 'OSOBA';
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: panelGreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return TacticalReportSheet(
            title: 'CONTACT',
            icon: Icons.radar_outlined,
            danger: true,
            children: [
              ReportField(controller: bearingController, label: 'Směr'),
              ReportField(
                controller: distanceController,
                label: 'Vzdálenost m',
              ),
              DropdownButtonFormField<String>(
                initialValue: contactType,
                decoration: const InputDecoration(
                  labelText: 'Typ kontaktu',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'OSOBA', child: Text('OSOBA')),
                  DropdownMenuItem(value: 'VOZIDLO', child: Text('VOZIDLO')),
                  DropdownMenuItem(value: 'DRON', child: Text('DRON')),
                  DropdownMenuItem(value: 'NEZNÁMÝ', child: Text('NEZNÁMÝ')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setSheetState(() => contactType = value);
                  }
                },
              ),
              ReportField(controller: sizeController, label: 'Síla / počet'),
              ReportField(controller: noteController, label: 'Poznámka'),
            ],
            onSend: () => Navigator.of(context).pop(true),
          );
        },
      ),
    );
    if (sent == true) {
      final text =
          'CONTACT | MGRS ${widget.selfNode.mgrs} | DIR ${bearingController.text.trim()} | DIST ${distanceController.text.trim()} m | TYPE $contactType | SIZE ${sizeController.text.trim()} | ${noteController.text.trim()}';
      await _sendQuickMessage(text, priority: true);
    }
    bearingController.dispose();
    distanceController.dispose();
    sizeController.dispose();
    noteController.dispose();
  }

  Future<void> _showMedevacReportSheet() async {
    final casualtyController = TextEditingController(text: '1');
    final noteController = TextEditingController(text: 'nutny odsun');
    // Prefer a MEDEVAC point; otherwise evacuate from our own position.
    final self = widget.selfNode;
    final medevacWaypoint = widget.waypoints.firstWhere(
      (waypoint) => waypoint.type == TacticalWaypointType.medevac,
      orElse: () => TacticalWaypoint(
        code: 'POZICE',
        type: TacticalWaypointType.medevac,
        latitude: self.latitude,
        longitude: self.longitude,
        note: '',
      ),
    );
    var status = 'URGENT';
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: panelGreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return TacticalReportSheet(
            title: 'MEDEVAC',
            icon: Icons.medical_services_outlined,
            danger: true,
            children: [
              _ReportStaticLine(label: 'Bod', value: medevacWaypoint.code),
              _ReportStaticLine(label: 'MGRS', value: medevacWaypoint.mgrs),
              ReportField(controller: casualtyController, label: 'Zranění'),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(
                  labelText: 'Priorita',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'URGENT', child: Text('URGENT')),
                  DropdownMenuItem(value: 'PRIORITY', child: Text('PRIORITY')),
                  DropdownMenuItem(value: 'ROUTINE', child: Text('ROUTINE')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setSheetState(() => status = value);
                  }
                },
              ),
              ReportField(controller: noteController, label: 'Poznámka'),
            ],
            onSend: () => Navigator.of(context).pop(true),
          );
        },
      ),
    );
    if (sent == true) {
      final text =
          'MEDEVAC | WP ${medevacWaypoint.code} | MGRS ${medevacWaypoint.mgrs} | WIA ${casualtyController.text.trim()} | STATUS $status | ${noteController.text.trim()}';
      await _sendQuickMessage(text, priority: true);
    }
    casualtyController.dispose();
    noteController.dispose();
  }

  Future<void> _showSitrepReportSheet() async {
    final batteryController = TextEditingController(
      text: switch (widget.selfNode.batteryPercent) {
        null => '?',
        > 100 => 'EXT',
        final percent => '$percent%',
      },
    );
    final ammoController = TextEditingController(text: 'OK');
    final fuelController = TextEditingController(text: 'OK');
    final noteController = TextEditingController(text: 'bez zmen');
    var teamStatus = 'GREEN';
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: panelGreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return TacticalReportSheet(
            title: 'SITREP',
            icon: Icons.assignment_turned_in_outlined,
            children: [
              _ReportStaticLine(label: 'MGRS', value: widget.selfNode.mgrs),
              DropdownButtonFormField<String>(
                initialValue: teamStatus,
                decoration: const InputDecoration(
                  labelText: 'Stav týmu',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'GREEN', child: Text('GREEN')),
                  DropdownMenuItem(value: 'AMBER', child: Text('AMBER')),
                  DropdownMenuItem(value: 'RED', child: Text('RED')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setSheetState(() => teamStatus = value);
                  }
                },
              ),
              ReportField(controller: batteryController, label: 'Baterie'),
              ReportField(controller: ammoController, label: 'Munice'),
              ReportField(controller: fuelController, label: 'Palivo'),
              ReportField(controller: noteController, label: 'Poznámka'),
            ],
            onSend: () => Navigator.of(context).pop(true),
          );
        },
      ),
    );
    if (sent == true) {
      final text =
          'SITREP | MGRS ${widget.selfNode.mgrs} | TEAM $teamStatus | BAT ${batteryController.text.trim()} | AMMO ${ammoController.text.trim()} | FUEL ${fuelController.text.trim()} | ${noteController.text.trim()}';
      await _sendQuickMessage(text, priority: teamStatus != 'GREEN');
    }
    batteryController.dispose();
    ammoController.dispose();
    fuelController.dispose();
    noteController.dispose();
  }
}

class TacticalReportSheet extends StatelessWidget {
  const TacticalReportSheet({
    required this.title,
    required this.icon,
    required this.children,
    required this.onSend,
    this.danger = false,
    super.key,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final VoidCallback onSend;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? dangerRed : sand;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final child in children) ...[
              child,
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              onPressed: onSend,
              style: FilledButton.styleFrom(
                backgroundColor: danger ? dangerRed : rangerGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.send),
              label: Text('Odeslat $title'),
            ),
          ],
        ),
      ),
    );
  }
}

class ReportField extends StatelessWidget {
  const ReportField({required this.controller, required this.label, super.key});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _ReportStaticLine extends StatelessWidget {
  const _ReportStaticLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return MonoLine(label: label, value: value, allowWrap: true);
  }
}

class MessageComposer extends StatelessWidget {
  const MessageComposer({
    required this.controller,
    required this.nodeSearchController,
    required this.directMode,
    required this.nodes,
    required this.selectedNodeIndex,
    required this.selectedGroup,
    required this.onModeChanged,
    required this.onNodeChanged,
    required this.onSend,
    super.key,
  });

  final TextEditingController controller;
  final TextEditingController nodeSearchController;
  final bool directMode;
  final List<MeshNode> nodes;
  final int selectedNodeIndex;
  final CommunicationGroup selectedGroup;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<int> onNodeChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final canSendDirect = nodes.isNotEmpty;
    final selectedNode = canSendDirect ? nodes[selectedNodeIndex] : null;
    final canSend = !directMode || canSendDirect;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The composer may sit in a side panel; decide on its own width.
        final compactMode =
            constraints.maxWidth < MediaQuery.textScalerOf(context).scale(420);
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    SegmentedButton<bool>(
                      // Labels only where they fit next to the recipient field.
                      segments: [
                        ButtonSegment(
                          value: false,
                          icon: const Icon(Icons.groups_2, size: 17),
                          tooltip: 'Skupina',
                          label: compactMode ? null : const Text('Skupina'),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: const Icon(Icons.person_pin_circle, size: 17),
                          tooltip: 'Osoba',
                          label: compactMode ? null : const Text('Osoba'),
                        ),
                      ],
                      selected: {directMode},
                      onSelectionChanged: (value) =>
                          onModeChanged(value.single && canSendDirect),
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? Colors.white
                              : sand,
                        ),
                        backgroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? rangerGreen
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: directMode
                          ? canSendDirect
                                ? DropdownButtonFormField<int>(
                                    initialValue: selectedNodeIndex,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      labelText: 'Adresát',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: [
                                      for (
                                        var index = 0;
                                        index < nodes.length;
                                        index++
                                      )
                                        DropdownMenuItem(
                                          value: index,
                                          child: Text(
                                            '${nodes[index].callSign} / !${nodes[index].nodeNumHex}',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) {
                                        onNodeChanged(value);
                                      }
                                    },
                                  )
                                : const _TargetPill(
                                    icon: Icons.person_off_outlined,
                                    label: 'Adresát nenalezen',
                                  )
                          : _TargetPill(
                              icon: Icons.radio,
                              label:
                                  '${selectedGroup.name} / kanál ${selectedGroup.channelIndex}',
                            ),
                    ),
                  ],
                ),
                if (directMode) ...[
                  const SizedBox(height: 8),
                  TacticalSearchField(
                    controller: nodeSearchController,
                    label: 'Vyhledat adresáta',
                    hint: 'Callsign, MGRS, node ID, stav',
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSend(),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: directMode && selectedNode != null
                              ? 'Zpráva pro ${selectedNode.callSign}'
                              : directMode
                              ? 'Vyber adresáta'
                              : 'Zpráva skupině ${selectedGroup.name}',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: canSend ? onSend : null,
                      tooltip: 'Odeslat přes Meshtastic',
                      style: IconButton.styleFrom(
                        backgroundColor: rangerGreen,
                        foregroundColor: Colors.white,
                        fixedSize: const Size(48, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TargetPill extends StatelessWidget {
  const _TargetPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: panelGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: sand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class MessageCard extends StatelessWidget {
  const MessageCard({
    required this.message,
    this.onRetry,
    this.onAcknowledge,
    this.onLongPress,
    super.key,
  });

  final MeshMessage message;
  final VoidCallback? onRetry;

  /// Shown as "Rozumím" on priority orders from the panel.
  final VoidCallback? onAcknowledge;

  /// Opens the message actions.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    message.viaInternet
                        ? Icons.cloud_outlined
                        : Icons.settings_input_antenna,
                    size: 16,
                    color: message.priority ? signalAmber : sand,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            message.sender,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (message.targetLabel != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              message.targetLabel!,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: sand.withValues(alpha: 0.78),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        if (message.delivery != MessageDelivery.received) ...[
                          const SizedBox(width: 8),
                          DeliveryStatusIcon(delivery: message.delivery),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    message.timeLabel(DateTime.now()),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                message.body,
                style: const TextStyle(fontSize: 14, height: 1.25),
              ),
              if (message.needsAcknowledgement && onAcknowledge != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    key: ValueKey('ack-${message.hqMessageId}'),
                    onPressed: onAcknowledge,
                    style: FilledButton.styleFrom(
                      backgroundColor: signalAmber,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(0, 44),
                    ),
                    icon: const Icon(Icons.task_alt, size: 18),
                    label: const Text('Rozumím'),
                  ),
                ),
              ],
              if (message.acknowledgedAt case final at?
                  when message.hqMessageId != null) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Icon(Icons.task_alt, size: 14, color: blueForce),
                    const SizedBox(width: 4),
                    Text(
                      'Potvrzeno ${_clock(at)}',
                      style: const TextStyle(color: blueForce, fontSize: 12),
                    ),
                  ],
                ),
              ],
              if (message.canRetry && onRetry != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(foregroundColor: dangerRed),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Odeslat znovu'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Local `HH:mm`.
String _clock(DateTime at) {
  final local = at.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

class DeliveryStatusIcon extends StatelessWidget {
  const DeliveryStatusIcon({required this.delivery, super.key});

  final MessageDelivery delivery;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (delivery) {
      MessageDelivery.received => (Icons.call_received, sand, 'Přijato'),
      MessageDelivery.sending => (Icons.schedule, sand, 'Odesílám'),
      MessageDelivery.notSent => (
        Icons.cloud_off_outlined,
        dangerRed,
        'Neodesláno, T-Beam nepřipojen',
      ),
      MessageDelivery.sent => (Icons.done, sand, 'Předáno do T-Beamu'),
      MessageDelivery.delivered => (Icons.done_all, blueForce, 'Doručeno'),
      MessageDelivery.failed => (
        Icons.error_outline,
        dangerRed,
        'Doručení selhalo',
      ),
    };
    return Tooltip(
      message: label,
      child: Icon(icon, size: 14, color: color, semanticLabel: label),
    );
  }
}

class QuickActionButton extends StatelessWidget {
  const QuickActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.danger = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? dangerRed : rangerGreen;
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}

class ReportActionButton extends StatelessWidget {
  const ReportActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.danger = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? dangerRed : tacticalKhaki;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size.fromHeight(44),
        side: BorderSide(color: color.withValues(alpha: 0.72)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}
