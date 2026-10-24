import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../controllers/offline_maps_controller.dart';
import '../controllers/ptt_controller.dart';
import '../controllers/tactical_controller.dart';
import '../models/member_status.dart';
import '../models/messaging.dart';
import '../models/navigation.dart';
import '../theme.dart';
import '../widgets/navigation_widgets.dart';
import '../widgets/rendezvous_banner.dart';
import '../widgets/sos_widgets.dart';
import 'map_page.dart';

/// Simplified screen for a phone in a car holder: map, nearest target, last
/// message, three quick reports and a large hold-to-talk button. Keeps the
/// display on while open.
class CarModeScreen extends StatefulWidget {
  const CarModeScreen({
    required this.controller,
    required this.offlineMaps,
    super.key,
  });

  final TacticalController controller;
  final OfflineMapsController offlineMaps;

  @override
  State<CarModeScreen> createState() => _CarModeScreenState();
}

class _CarModeScreenState extends State<CarModeScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_setWakelock(true));
  }

  @override
  void dispose() {
    unawaited(_setWakelock(false));
    // Never leave the microphone open when leaving the screen mid-press.
    if (widget.controller.pttActive) {
      widget.controller.setPttActive(false);
    }
    super.dispose();
  }

  Future<void> _setWakelock(bool enabled) async {
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (_) {
      // Not available (tests, unsupported platform).
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final controller = widget.controller;
            final map = MeshMap(
              nodes: controller.nodes,
              waypoints: controller.waypoints,
              tileSource: widget.offlineMaps.source,
              offlineStore: widget.offlineMaps.store,
              track: [for (final point in controller.track) point.latLng],
              showGrid: controller.mgrsGrid,
              baseCode: controller.baseWaypoint?.code,
              navTarget: controller.navTarget?.position,
              peerTrails: controller.peerTrails,
              courseDeg: controller.courseDeg,
              statusOf: (callSign) => controller.statusOf(callSign)?.status,
              headingUp: controller.mapHeadingUp,
              onHeadingUpChanged: controller.setMapHeadingUp,
            );
            final panel = Column(
              children: [
                SosBanners(
                  ownActive: controller.sosActive,
                  alerts: controller.activeSosAlerts,
                  onCancelOwn: () => unawaited(controller.stopSos()),
                  onAcknowledge: (alert) =>
                      unawaited(controller.acknowledgeSos(alert)),
                ),
                MemberStatusBanners(
                  alerts: controller.urgentStatuses,
                  onAcknowledge: controller.acknowledgeStatus,
                  onNavigate: controller.navigateToMember,
                ),
                RendezvousBanner(
                  meeting: controller.rendezvous,
                  isOwn:
                      controller.rendezvous?.setBy ==
                      controller.selfNode.callSign,
                  solution: controller.rendezvousSolution,
                  speedKmh: controller.travelSpeedKmh,
                  onNavigate: () => controller.navigateTo(
                    NavTarget.waypoint(controller.rendezvous!.code),
                  ),
                  onClose: () {
                    if (controller.rendezvous?.setBy ==
                        controller.selfNode.callSign) {
                      unawaited(controller.cancelRendezvous());
                    } else {
                      controller.dismissRendezvous();
                    }
                  },
                ),
                LostContactBanners(
                  contacts: controller.lostContacts,
                  onAcknowledge: controller.acknowledgeLostContact,
                  onNavigate: (contact) =>
                      controller.navigateTo(NavTarget.node(contact.nodeNum)),
                ),
                DangerBanners(
                  warnings: controller.dangerWarnings,
                  onDismiss: controller.dismissDanger,
                ),
                Expanded(child: _CarPanel(controller: controller)),
              ],
            );
            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > constraints.maxHeight) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: map),
                      SizedBox(
                        width: (constraints.maxWidth * 0.4).clamp(280, 420),
                        child: panel,
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 4, child: map),
                    Expanded(flex: 5, child: panel),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _CarPanel extends StatelessWidget {
  const _CarPanel({required this.controller});

  final TacticalController controller;

  @override
  Widget build(BuildContext context) {
    final ptt = controller.ptt;
    final self = controller.selfNode;
    final solutions = TacticalNavSolution.fromMission(
      self: self,
      nodes: controller.nodes,
      waypoints: controller.waypoints,
    );
    final chosen = controller.navTarget;
    final nearest = chosen ?? (solutions.isEmpty ? null : solutions.first);
    final groupId = controller.selectedGroup.id;
    final lastMessage = controller.messages
        .where((message) => message.groupId == groupId)
        .firstOrNull;

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${ptt.channel} · ${_statusLabel(ptt)}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ptt.status == PttStatus.error
                        ? dangerRed
                        : Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _OwnStatusButton(
                status: controller.ownStatus,
                onPressed: () => _pickStatus(context),
              ),
              IconButton(
                tooltip: controller.nightMode
                    ? 'Vypnout noční režim'
                    : 'Zapnout noční režim',
                iconSize: 28,
                onPressed: () => controller.setNightMode(!controller.nightMode),
                icon: Icon(
                  controller.nightMode
                      ? Icons.nightlight
                      : Icons.nightlight_outlined,
                  color: Colors.white70,
                ),
              ),
              IconButton(
                tooltip: 'Ukončit režim auta',
                iconSize: 32,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close, color: Colors.white70),
              ),
            ],
          ),
          if (nearest != null)
            InkWell(
              key: const ValueKey('car-pick-target'),
              onTap: () => _pickTarget(context, solutions),
              child: Row(
                children: [
                  if (chosen != null)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.navigation, color: signalAmber),
                    ),
                  Expanded(
                    child: Text(
                      '${nearest.label}  AZ ${nearest.bearingDeg.toStringAsFixed(0)}°  '
                      '${formatDistance(nearest.distanceKm)}  '
                      '${nearest.etaLabelAt(controller.travelSpeedKmh)}',
                      key: const ValueKey('car-nearest'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: chosen != null
                            ? signalAmber
                            : nearest.priority
                            ? dangerRed
                            : sand,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (chosen != null)
                    IconButton(
                      tooltip: 'Ukončit navigaci',
                      iconSize: 28,
                      onPressed: controller.clearNavTarget,
                      icon: const Icon(Icons.close, color: Colors.white70),
                    )
                  else
                    const Icon(Icons.expand_more, color: Colors.white54),
                ],
              ),
            ),
          const SizedBox(height: 6),
          if (lastMessage != null)
            Text(
              '${lastMessage.sender}: ${lastMessage.body}',
              key: const ValueKey('car-last-message'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              _QuickButton(
                label: 'ZPRÁVA',
                onPressed: () => _pickQuickMessage(context),
              ),
              const SizedBox(width: 8),
              _QuickButton(
                label: 'NA POZICI',
                onPressed: () => _send(
                  context,
                  'NA POZICI | MGRS ${self.mgrs} | LAT ${self.latitude.toStringAsFixed(6)} | LON ${self.longitude.toStringAsFixed(6)}',
                ),
              ),
              const SizedBox(width: 8),
              _QuickButton(
                label: controller.sosActive ? 'ZRUŠIT SOS' : 'SOS',
                danger: true,
                onPressed: () async {
                  if (controller.sosActive) {
                    await controller.stopSos();
                  } else if (await confirmSosStart(context)) {
                    await controller.startSos();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(child: _BigPttButton(controller: controller)),
        ],
      ),
    );
  }

  Future<void> _pickStatus(BuildContext context) async {
    final index = await showBigChoices(
      context,
      title: 'Můj stav',
      choices: [
        for (final status in MemberStatus.values)
          BigChoice(
            label: status.label,
            icon: status.icon,
            color: status.urgent ? dangerRed : panelGreen,
            selected: status == controller.ownStatus,
          ),
      ],
    );
    if (index != null) {
      await controller.setOwnStatus(MemberStatus.values[index]);
    }
  }

  Future<void> _pickQuickMessage(BuildContext context) async {
    final texts = ['OK', ...controller.quickMessages.where((t) => t != 'OK')];
    final index = await showBigChoices(
      context,
      title: 'Poslat skupině ${controller.selectedGroup.name}',
      choices: [for (final text in texts) BigChoice(label: text)],
    );
    if (index != null && context.mounted) {
      _send(context, texts[index]);
    }
  }

  Future<void> _pickTarget(
    BuildContext context,
    List<TacticalNavSolution> solutions,
  ) async {
    final base = controller.baseWaypoint;
    final options = solutions.take(12).toList();
    final index = await showBigChoices(
      context,
      title: 'Navigovat k',
      choices: [
        if (base != null)
          BigChoice(
            label: 'ZÁKLADNA ${base.code}',
            icon: Icons.home,
            color: rangerGreen,
            selected: controller.navTarget?.label == base.code,
          ),
        for (final solution in options)
          BigChoice(
            label:
                '${solution.label}  AZ ${solution.bearingDeg.toStringAsFixed(0)}°  '
                '${formatDistance(solution.distanceKm)}',
            icon: solution.icon,
            color: solution.priority ? dangerRed : panelGreen,
            selected: controller.navTarget?.label == solution.label,
          ),
      ],
    );
    if (index == null) {
      return;
    }
    if (base != null && index == 0) {
      controller.navigateToBase();
    } else {
      controller.navigateTo(options[index - (base == null ? 0 : 1)].target);
    }
  }

  void _send(BuildContext context, String text, {bool priority = false}) {
    unawaited(
      controller.sendMeshText(
        MeshMessageDraft(
          text: text,
          groupId: controller.selectedGroup.id,
          priority: priority,
        ),
      ),
    );
  }

  String _statusLabel(PttController ptt) => switch (ptt.status) {
    PttStatus.offline => 'PTT OFFLINE',
    PttStatus.connecting => 'PŘIPOJUJI',
    PttStatus.ready => ptt.isDemo ? 'PŘIPRAVENO (DEMO)' : 'PŘIPRAVENO',
    PttStatus.transmitting => 'VYSÍLÁM',
    PttStatus.receiving => 'MLUVÍ ${ptt.speaker ?? '?'}',
    PttStatus.disabled => 'PTT VYPNUTO',
    PttStatus.error => 'CHYBA SPOJENÍ',
  };
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SizedBox(
        height: 64,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: danger ? dangerRed : panelGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          child: FittedBox(child: Text(label)),
        ),
      ),
    );
  }
}

class _BigPttButton extends StatelessWidget {
  const _BigPttButton({required this.controller});

  final TacticalController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.ptt.status;
    final transmitting = status == PttStatus.transmitting;
    final receiving = status == PttStatus.receiving;
    final enabled = status == PttStatus.ready || transmitting;
    final color = transmitting
        ? signalAmber
        : receiving
        ? blueForce.withValues(alpha: 0.5)
        : enabled
        ? rangerGreen
        : Colors.grey.shade800;
    // Listener (not GestureDetector) so a long hold is never cancelled by
    // gesture arenas.
    return Listener(
      key: const ValueKey('car-ptt'),
      onPointerDown: enabled ? (_) => controller.setPttActive(true) : null,
      onPointerUp: (_) => controller.setPttActive(false),
      onPointerCancel: (_) => controller.setPttActive(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              transmitting
                  ? Icons.mic
                  : receiving
                  ? Icons.hearing
                  : Icons.mic_none,
              size: 56,
              color: transmitting ? Colors.black : Colors.white,
            ),
            Text(
              transmitting
                  ? 'VYSÍLÁM'
                  : receiving
                  ? 'OBSAZENO'
                  : 'PTT – DRŽ',
              style: TextStyle(
                color: transmitting ? Colors.black : Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Own status in the car-mode header; opens the big status picker.
class _OwnStatusButton extends StatelessWidget {
  const _OwnStatusButton({required this.status, required this.onPressed});

  final MemberStatus? status;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final current = status;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: OutlinedButton.icon(
        key: const ValueKey('car-own-status'),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: current == null
              ? Colors.white70
              : current.urgent
              ? dangerRed
              : Colors.white,
          side: BorderSide(
            color: current?.urgent == true ? dangerRed : Colors.white38,
          ),
          visualDensity: VisualDensity.compact,
        ),
        icon: Icon(current?.icon ?? Icons.person_outline, size: 20),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 96),
          child: Text(
            current?.label ?? 'STAV',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}

/// One option of [showBigChoices].
class BigChoice {
  const BigChoice({
    required this.label,
    this.icon,
    this.color = panelGreen,
    this.selected = false,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final bool selected;
}

/// Bottom sheet of large buttons that are easy to hit while driving;
/// returns the chosen index or null.
Future<int?> showBigChoices(
  BuildContext context, {
  required String title,
  required List<BigChoice> choices,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.black,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          for (final (index, choice) in choices.indexed) ...[
            SizedBox(
              height: 60,
              child: FilledButton.icon(
                key: ValueKey('big-choice-$index'),
                onPressed: () => Navigator.of(context).pop(index),
                style: FilledButton.styleFrom(
                  backgroundColor: choice.color,
                  foregroundColor: Colors.white,
                  alignment: Alignment.centerLeft,
                  side: choice.selected
                      ? const BorderSide(color: signalAmber, width: 3)
                      : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                icon: Icon(choice.icon ?? Icons.chevron_right),
                label: Text(choice.label, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    ),
  );
}
