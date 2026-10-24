import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/ptt_controller.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class UserSessionChip extends StatelessWidget {
  const UserSessionChip({
    required this.session,
    required this.onLogout,
    this.onEmergencyWipe,
    this.compact = false,
    super.key,
  });

  final AuthSession session;
  final VoidCallback onLogout;
  final VoidCallback? onEmergencyWipe;

  /// Icon only (narrow phones); name and role are in the menu.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Uživatel',
      onSelected: (value) {
        if (value == 'logout') {
          onLogout();
        } else if (value == 'wipe') {
          onEmergencyWipe?.call();
        }
      },
      itemBuilder: (context) => [
        if (compact)
          PopupMenuItem(
            enabled: false,
            child: Text('${session.displayName} / ${session.role}'),
          ),
        const PopupMenuItem(value: 'logout', child: Text('Odhlásit')),
        if (onEmergencyWipe != null)
          const PopupMenuItem(
            value: 'wipe',
            child: Text(
              'Nouzově smazat data',
              style: TextStyle(color: dangerRed, fontWeight: FontWeight.w800),
            ),
          ),
      ],
      child: compact
          ? const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.verified_user_outlined, size: 22, color: sand),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: panelGreen,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    size: 16,
                    color: sand,
                  ),
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
    this.unreadMessages = 0,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final int unreadMessages;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      backgroundColor: const Color(0xFF171B13),
      indicatorColor: rangerGreen.withValues(alpha: 0.85),
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      labelType: NavigationRailLabelType.none,
      minWidth: 64,
      destinations: [
        const NavigationRailDestination(
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map),
          label: Text('Mapa'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.groups_2_outlined),
          selectedIcon: Icon(Icons.groups_2),
          label: Text('Tým'),
        ),
        NavigationRailDestination(
          icon: UnreadBadge(
            count: unreadMessages,
            child: const Icon(Icons.chat_bubble_outline),
          ),
          selectedIcon: UnreadBadge(
            count: unreadMessages,
            child: const Icon(Icons.chat_bubble),
          ),
          label: const Text('Zprávy'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Systém'),
        ),
      ],
    );
  }
}

/// Red count over an icon; hidden at zero, "99+" above 99.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({required this.count, required this.child, super.key});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      backgroundColor: dangerRed,
      textColor: Colors.white,
      label: Text(count > 99 ? '99+' : '$count'),
      child: child,
    );
  }
}

class AppBrand extends StatelessWidget {
  const AppBrand({this.compact = false, super.key});

  /// Logo only, for narrow screens.
  final bool compact;

  static const _name = 'FIRST PRIVATE MILITARY COMPANY';

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: compact ? 30 : 36,
          width: compact ? 48 : 58,
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
        if (!compact) ...[
          const SizedBox(width: 10),
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final style = DefaultTextStyle.of(
                  context,
                ).style.merge(const TextStyle(fontWeight: FontWeight.w800));
                final oneLine = TextPainter(
                  text: TextSpan(text: _name, style: style),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 1,
                )..layout();
                final fits = oneLine.width <= constraints.maxWidth;
                oneLine.dispose();
                if (fits) {
                  return Text(_name, maxLines: 1, style: style);
                }
                // Too narrow for one line: two smaller lines, shrunk
                // further only if even those do not fit.
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'FIRST PRIVATE\nMILITARY COMPANY',
                    semanticsLabel: _name,
                    style: style.copyWith(
                      fontSize: (style.fontSize ?? 20) * 0.72,
                      height: 1.1,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// T-Beam / PTT / transmit state as three icons for the app bar, so the
/// status stays visible on every tab without a separate strip.
class StatusIcons extends StatelessWidget {
  const StatusIcons({
    required this.meshConnected,
    required this.voiceOnline,
    required this.pttActive,
    this.dense = false,
    super.key,
  });

  final bool meshConnected;
  final bool voiceOnline;
  final bool pttActive;

  /// Tighter spacing for narrow phones.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    Widget icon(IconData data, String tooltip, Color color) => Tooltip(
      message: tooltip,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: dense ? 1 : 3),
        child: Icon(data, size: dense ? 18 : 20, color: color),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon(
          meshConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
          meshConnected ? 'T-Beam 868 připojen' : 'T-Beam 868 nepřipojen',
          meshConnected ? sand : dangerRed,
        ),
        icon(
          voiceOnline ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
          voiceOnline ? 'PTT připojeno' : 'PTT nepřipojeno',
          voiceOnline ? sand : dangerRed,
        ),
        icon(
          pttActive ? Icons.mic : Icons.mic_none,
          pttActive ? 'Vysílám' : 'Příjem',
          pttActive ? signalAmber : sand,
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

class PttBar extends StatelessWidget {
  const PttBar({
    required this.status,
    required this.onChanged,
    required this.channel,
    required this.userName,
    this.speaker,
    this.demo = false,
    this.compact = false,
    super.key,
  });

  final PttStatus status;
  final ValueChanged<bool> onChanged;
  final String channel;
  final String userName;

  /// Identity of the member holding the floor while [status] is receiving.
  final String? speaker;

  /// Demo mode: no voice server, the button only changes local state.
  final bool demo;
  final bool compact;

  bool get active => status == PttStatus.transmitting;
  bool get enabled =>
      status == PttStatus.ready || status == PttStatus.transmitting;

  String get _statusLabel => switch (status) {
    PttStatus.offline => 'PTT OFFLINE',
    PttStatus.connecting => 'PTT $channel | PŘIPOJUJI',
    PttStatus.ready =>
      'PTT $channel | PŘIPRAVENO | ${demo ? 'DEMO BEZ ZVUKU' : 'E2EE'}',
    PttStatus.transmitting => 'PTT $channel | VYSÍLÁM',
    PttStatus.receiving => 'PTT $channel | MLUVÍ ${speaker ?? '?'}',
    PttStatus.disabled => 'PTT $channel | PRO SKUPINU VYPNUTO',
    PttStatus.error => 'PTT $channel | CHYBA SPOJENÍ',
  };

  @override
  Widget build(BuildContext context) {
    final receiving = status == PttStatus.receiving;
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
                  _statusLabel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: switch (status) {
                      PttStatus.error || PttStatus.offline => dangerRed,
                      PttStatus.disabled => Colors.white54,
                      PttStatus.receiving => blueForce,
                      _ => Colors.white,
                    },
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
                    active
                        ? Icons.mic
                        : (receiving ? Icons.hearing : Icons.mic_none),
                    color: active ? Colors.black : Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    active ? 'TALK' : (receiving ? 'OBSAZENO' : 'PTT'),
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
