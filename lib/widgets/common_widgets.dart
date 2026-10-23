import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';

class UserSessionChip extends StatelessWidget {
  const UserSessionChip({
    required this.session,
    required this.onLogout,
    super.key,
  });

  final AuthSession session;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Uživatel',
      onSelected: (value) {
        if (value == 'logout') {
          onLogout();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'logout', child: Text('Odhlásit')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: panelGreen,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_user_outlined, size: 16, color: sand),
            const SizedBox(width: 6),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  session.role,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.62),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TacticalNavigationRail extends StatelessWidget {
  const TacticalNavigationRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      backgroundColor: const Color(0xFF171B13),
      indicatorColor: rangerGreen.withValues(alpha: 0.85),
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      labelType: NavigationRailLabelType.none,
      minWidth: 64,
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map),
          label: Text('Mapa'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.groups_2_outlined),
          selectedIcon: Icon(Icons.groups_2),
          label: Text('Tým'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble),
          label: Text('Zprávy'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Systém'),
        ),
      ],
    );
  }
}

class AppBrand extends StatelessWidget {
  const AppBrand({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 36,
          width: 58,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: rangerGreen.withValues(alpha: 0.8)),
          ),
          child: Image.asset(
            pmcLogoAsset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            'FIRST PRIVATE MILITARY COMPANY',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

/// Local and UTC clock. Ticks on its own so the rest of the screen does not
/// rebuild every second.
class TimeReadout extends StatefulWidget {
  const TimeReadout({this.clock = DateTime.now, super.key});

  final DateTime Function() clock;

  @override
  State<TimeReadout> createState() => _TimeReadoutState();
}

class _TimeReadoutState extends State<TimeReadout> {
  late DateTime _now;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _now = widget.clock();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = widget.clock()),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final utc = _now.toUtc();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'LOC ${_time(_now)}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        Text(
          'UTC ${_time(utc)}',
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  String _time(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}

class StatusStrip extends StatelessWidget {
  const StatusStrip({
    required this.meshConnected,
    required this.voiceOnline,
    required this.pttActive,
    super.key,
  });

  final bool meshConnected;
  final bool voiceOnline;
  final bool pttActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: panelGreen,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: StatusChip(
              icon: Icons.bluetooth_connected,
              label: 'T-Beam 868',
              ok: meshConnected,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatusChip(
              icon: Icons.cloud_done_outlined,
              label: 'PTT demo',
              ok: voiceOnline,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatusChip(
              icon: pttActive ? Icons.mic : Icons.mic_none,
              label: pttActive ? 'Vysílám' : 'Příjem',
              ok: !pttActive,
              alert: pttActive,
            ),
          ),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.icon,
    required this.label,
    required this.ok,
    this.alert = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool ok;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final color = alert ? signalAmber : (ok ? sand : dangerRed);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PttBar extends StatelessWidget {
  const PttBar({
    required this.active,
    required this.enabled,
    required this.onChanged,
    required this.channel,
    required this.userName,
    required this.encrypted,
    this.compact = false,
    super.key,
  });

  final bool active;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final String channel;
  final String userName;
  final bool encrypted;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, compact ? 6 : 8, 12, compact ? 8 : 10),
      color: const Color(0xFF10130D),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: signalAmber,
                    fontSize: compact ? 15 : 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  enabled
                      ? 'PTT $channel | ${active ? 'VYSILANI' : 'PRIPRAVENO'} | ${encrypted ? 'AES-GCM' : 'NEŠIFROVÁNO'}'
                      : 'PTT SERVER OFFLINE',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? Colors.white : dangerRed,
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTapDown: enabled ? (_) => onChanged(true) : null,
            onTapUp: enabled ? (_) => onChanged(false) : null,
            onTapCancel: enabled ? () => onChanged(false) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: compact ? 44 : 54,
              width: compact ? 132 : 150,
              decoration: BoxDecoration(
                color: !enabled
                    ? Colors.grey.shade800
                    : (active ? signalAmber : rangerGreen),
                borderRadius: BorderRadius.circular(8),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: signalAmber.withValues(alpha: 0.35),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    active ? Icons.mic : Icons.mic_none,
                    color: active ? Colors.black : Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    active ? 'TALK' : 'PTT',
                    style: TextStyle(
                      color: active ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.compact = false,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 8 : 10,
        ),
        child: Row(
          children: [
            Icon(icon, color: sand, size: compact ? 18 : 20),
            SizedBox(width: compact ? 8 : 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.62),
                    ),
                  ),
                  Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: compact ? 14 : 16,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SystemSection extends StatelessWidget {
  const SystemSection({
    required this.title,
    required this.icon,
    required this.children,
    super.key,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: sand),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const Divider(height: 22),
            ...children,
          ],
        ),
      ),
    );
  }
}

class MonoLine extends StatelessWidget {
  const MonoLine({
    required this.label,
    required this.value,
    this.labelWidth = 82,
    this.allowWrap = false,
    super.key,
  });

  final String label;
  final String value;
  final double labelWidth;
  final bool allowWrap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              overflow: allowWrap
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              softWrap: allowWrap,
              maxLines: allowWrap ? 2 : 1,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TacticalSearchField extends StatelessWidget {
  const TacticalSearchField({
    required this.controller,
    required this.label,
    required this.hint,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            labelText: label,
            hintText: hint,
            prefixIcon: const Icon(Icons.manage_search, color: sand),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Vymazat hledání',
                    onPressed: controller.clear,
                    icon: const Icon(Icons.close),
                  ),
            border: const OutlineInputBorder(),
          ),
        );
      },
    );
  }
}
