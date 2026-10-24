import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../controllers/offline_maps_controller.dart';
import '../controllers/ptt_controller.dart';
import '../controllers/tactical_controller.dart';
import '../models/messaging.dart';
import '../models/navigation.dart';
import '../theme.dart';
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
            );
            final panel = _CarPanel(controller: controller);
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
    final nearest = solutions.isEmpty ? null : solutions.first;
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
            Text(
              '${nearest.label}  AZ ${nearest.bearingDeg.toStringAsFixed(0)}°  '
              '${nearest.distanceKm.toStringAsFixed(1)} km',
              key: const ValueKey('car-nearest'),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: nearest.priority ? dangerRed : sand,
                fontSize: 22,
                fontWeight: FontWeight.w900,
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
              _QuickButton(label: 'OK', onPressed: () => _send(context, 'OK')),
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
                label: 'SOS',
                danger: true,
                onPressed: () => _send(context, 'SOS', priority: true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(child: _BigPttButton(controller: controller)),
        ],
      ),
    );
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
