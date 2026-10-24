import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:latlong2/latlong.dart';

import '../controllers/offline_maps_controller.dart';
import '../controllers/ptt_controller.dart';
import '../models/messaging.dart';
import '../models/mission_event.dart';
import '../services/backend_client.dart';
import '../services/offline_tiles/tile_math.dart';
import '../widgets/offline_maps_section.dart';

import '../services/location_service.dart';
import '../services/mesh_packet_repository.dart';
import '../services/meshtastic_ble_service.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/position_widgets.dart';

class SystemsPage extends StatelessWidget {
  const SystemsPage({
    required this.meshConnected,
    required this.ptt,
    this.onPttReconnect,
    this.nightMode = false,
    this.onNightModeChanged,
    this.nightModeAuto = false,
    this.onNightModeAutoChanged,
    this.mgrsGrid = true,
    this.onMgrsGridChanged,
    this.batterySaver = false,
    this.onBatterySaverChanged,
    this.dangerAlerts = true,
    this.onDangerAlertsChanged,
    this.lostContactAlerts = true,
    this.onLostContactAlertsChanged,
    this.hideSystemBars = true,
    this.onHideSystemBarsChanged,
    this.quickMessages = const [],
    this.onQuickMessagesChanged,
    this.sharePositionToMesh = true,
    this.onSharePositionToMeshChanged,
    this.trackPoints = 0,
    this.missionEvents = const [],
    this.trackLengthKm = 0,
    this.onExportMission,
    this.onClearTrack,
    this.onCopyPacketRecording,
    this.radioChannels = const [],
    this.channelWarnings = const [],
    this.volumeKeyPtt = false,
    this.onVolumeKeyPttChanged,
    required this.onBleConnect,
    required this.bleState,
    required this.packetDiagnostics,
    required this.fontScale,
    required this.onFontScaleChanged,
    this.locationState = LocationState.idle,
    this.onLocationStart,
    this.onLocationSettings,
    this.offlineMaps,
    this.mapCenter,
    this.visibleMapBounds,
    super.key,
  });

  final bool meshConnected;
  final PttController ptt;
  final VoidCallback? onPttReconnect;
  final bool nightMode;
  final ValueChanged<bool>? onNightModeChanged;
  final bool nightModeAuto;
  final ValueChanged<bool>? onNightModeAutoChanged;
  final bool mgrsGrid;
  final ValueChanged<bool>? onMgrsGridChanged;
  final bool batterySaver;
  final ValueChanged<bool>? onBatterySaverChanged;
  final bool dangerAlerts;
  final ValueChanged<bool>? onDangerAlertsChanged;
  final bool lostContactAlerts;
  final ValueChanged<bool>? onLostContactAlertsChanged;
  final bool hideSystemBars;
  final ValueChanged<bool>? onHideSystemBarsChanged;
  final List<String> quickMessages;
  final ValueChanged<List<String>>? onQuickMessagesChanged;
  final bool sharePositionToMesh;
  final ValueChanged<bool>? onSharePositionToMeshChanged;
  final int trackPoints;

  /// Mission log, newest first.
  final List<MissionEvent> missionEvents;
  final double trackLengthKm;
  final VoidCallback? onExportMission;
  final VoidCallback? onClearTrack;
  final String Function()? onCopyPacketRecording;
  final List<RadioChannel> radioChannels;
  final List<String> channelWarnings;
  final bool volumeKeyPtt;
  final ValueChanged<bool>? onVolumeKeyPttChanged;
  final VoidCallback onBleConnect;
  final MeshtasticBleState bleState;
  final MeshPacketDiagnostics packetDiagnostics;
  final double fontScale;
  final ValueChanged<double> onFontScaleChanged;
  final LocationState locationState;
  final VoidCallback? onLocationStart;
  final VoidCallback? onLocationSettings;
  final OfflineMapsController? offlineMaps;

  /// Centre for offline area downloads (own position).
  final LatLng? mapCenter;
  final TileBounds? visibleMapBounds;

  @override
  Widget build(BuildContext context) {
    final fix = locationState.lastFix;
    final needsSettings =
        locationState.status == LocationStatus.serviceDisabled ||
        locationState.status == LocationStatus.permissionDeniedForever;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        SystemSection(
          title: 'GPS',
          icon: Icons.gps_fixed,
          children: [
            MonoLine(label: 'Stav', value: locationState.status.description),
            MonoLine(
              label: 'Přesnost',
              value: fix == null ? '-' : '±${fix.accuracyM.round()} m',
            ),
            MonoLine(
              label: 'Poslední fix',
              value: fix == null ? '-' : _clockLabel(fix.timestamp.toLocal()),
            ),
            if (locationState.lastError != null)
              MonoLine(label: 'Chyba', value: locationState.lastError!),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: needsSettings ? onLocationSettings : onLocationStart,
              style: FilledButton.styleFrom(
                backgroundColor: rangerGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: Icon(
                needsSettings ? Icons.settings_outlined : Icons.gps_not_fixed,
                size: 18,
              ),
              label: Text(
                needsSettings ? 'Otevřít nastavení polohy' : 'Spustit GPS',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SystemSection(
          title: 'Nastavení',
          icon: Icons.format_size,
          children: [
            Text(
              'Velikost písma',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.86),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text(
                  'A',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                Expanded(
                  child: Slider(
                    value: fontScale,
                    min: 0.85,
                    max: 1.35,
                    divisions: 10,
                    label: '${(fontScale * 100).round()} %',
                    onChanged: onFontScaleChanged,
                  ),
                ),
                const Text(
                  'A',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            MonoLine(
              label: 'Aktuálně',
              value: '${(fontScale * 100).round()} %',
            ),
            if (onQuickMessagesChanged != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bolt),
                title: const Text('Rychlé zprávy'),
                subtitle: Text(
                  quickMessages.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final edited = await showDialog<List<String>>(
                    context: context,
                    builder: (_) => QuickMessagesDialog(initial: quickMessages),
                  );
                  if (edited != null) {
                    onQuickMessagesChanged!(edited);
                  }
                },
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: hideSystemBars,
              onChanged: onHideSystemBarsChanged,
              secondary: const Icon(Icons.fullscreen),
              title: const Text('Skrýt systémové lišty'),
              subtitle: const Text(
                'Celá obrazovka; lišty Androidu ukáže tah od okraje',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: mgrsGrid,
              onChanged: onMgrsGridChanged,
              secondary: const Icon(Icons.grid_4x4),
              title: const Text('Mřížka MGRS na mapě'),
              subtitle: const Text('1 km / 10 km / 100 km podle přiblížení'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: lostContactAlerts,
              onChanged: onLostContactAlertsChanged,
              secondary: const Icon(Icons.portable_wifi_off),
              title: const Text('Hlásit ztrátu spojení'),
              subtitle: const Text(
                'Pruh a vibrace, když se člen týmu 15 min neozve',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: dangerAlerts,
              onChanged: onDangerAlertsChanged,
              secondary: const Icon(Icons.dangerous_outlined),
              title: const Text('Varovat u nebezpečí'),
              subtitle: const Text('Pruh a vibrace do 300 m od bodu DANGER'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: batterySaver,
              onChanged: onBatterySaverChanged,
              secondary: const Icon(Icons.battery_saver),
              title: const Text('Úsporný režim'),
              subtitle: const Text(
                'Hrubší GPS, poloha týmu po 5 min / 250 m (mesh) '
                'a 2 min / 100 m (internet). SOS se neomezuje.',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: nightMode,
              onChanged: onNightModeChanged,
              secondary: const Icon(Icons.nightlight_outlined),
              title: const Text('Noční režim'),
              subtitle: const Text(
                'Tlumený červený displej, šetří adaptaci očí na tmu',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: nightModeAuto,
              onChanged: onNightModeAutoChanged,
              secondary: const Icon(Icons.brightness_auto_outlined),
              title: const Text('Automaticky podle soumraku'),
              subtitle: const Text(
                'Noční režim od konce soumraku do svítání v místě, kde jsi',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SystemSection(
          title: 'Meshtastic',
          icon: Icons.settings_input_antenna,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                meshConnected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                color: meshConnected ? sand : dangerRed,
              ),
              title: const Text('LILYGO T-Beam 868 MHz přes Bluetooth'),
              subtitle: Text(
                meshConnected
                    ? 'Připojeno: přijímá NodeInfo, Position a zprávy'
                    : 'Nepřipojeno: zprávy se odesílají jen lokálně',
              ),
            ),
            FilledButton.icon(
              onPressed: onBleConnect,
              style: FilledButton.styleFrom(
                backgroundColor: rangerGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.bluetooth_searching, size: 18),
              label: const Text('Vyhledat T-Beam'),
            ),
            const SizedBox(height: 8),
            MonoLine(label: 'BLE stav', value: _bleStatusLabel(bleState)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: sharePositionToMesh,
              onChanged: onSharePositionToMeshChanged,
              title: const Text('Posílat polohu telefonu do sítě'),
              subtitle: const Text(
                'Tým tě vidí i bez GPS fixu T-Beamu (max 1× za minutu / 50 m)',
              ),
            ),
            for (final channel in radioChannels)
              MonoLine(
                label: 'Kanál ${channel.index}',
                value:
                    '${channel.roleLabel}${channel.name.isEmpty ? '' : ' · ${channel.name}'}',
              ),
            for (final warning in channelWarnings)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: dangerRed, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        warning,
                        style: const TextStyle(color: dangerRed),
                      ),
                    ),
                  ],
                ),
              ),
            MonoLine(
              label: 'Pakety',
              value: '${packetDiagnostics.packetCount}',
            ),
            MonoLine(
              label: 'Dekódováno',
              value: '${packetDiagnostics.decodedEventCount} událostí',
            ),
            MonoLine(
              label: 'Poslední událost',
              value: packetDiagnostics.lastDecodedEvent?.label ?? '-',
            ),
            MonoLine(
              label: 'Poslední RX',
              value: _lastPacketLabel(packetDiagnostics),
            ),
            MonoLine(
              label: 'Raw hex',
              value: packetDiagnostics.lastPacketHex.isEmpty
                  ? '-'
                  : packetDiagnostics.lastPacketHex,
            ),
            if (onCopyPacketRecording != null &&
                packetDiagnostics.packetCount > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(
                      ClipboardData(text: onCopyPacketRecording!()),
                    );
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Záznam paketů zkopírován do schránky.'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.content_copy, size: 18),
                  label: const Text('Kopírovat záznam paketů'),
                ),
              ),
            const MonoLine(
              label: 'Transport',
              value: 'BLE / ToRadio / FromRadio protobuf',
            ),
            const MonoLine(label: 'Role', value: 'CLIENT'),
          ],
        ),
        const SizedBox(height: 10),
        SystemSection(
          title: 'Internet PTT',
          icon: Icons.record_voice_over,
          children: [
            MonoLine(
              label: 'Režim',
              value: ptt.isDemo
                  ? 'demo bez zvuku (BACKEND_URL nenastaven)'
                  : 'LiveKit, push-to-talk floor control',
            ),
            MonoLine(label: 'Kanál', value: ptt.channel),
            MonoLine(label: 'Stav', value: ptt.status.name),
            MonoLine(
              label: 'Šifrování',
              value: ptt.isDemo
                  ? '-'
                  : ptt.keyId == null
                  ? 'čeká na klíč'
                  : 'E2EE AES-GCM, klíč #${ptt.keyId}',
            ),
            if (ptt.error != null) MonoLine(label: 'Chyba', value: ptt.error!),
            const MonoLine(
              label: 'Na pozadí',
              value: 'Android: služba s notifikací, iOS: background audio',
            ),
            const MonoLine(
              label: 'HW tlačítko',
              value: 'tlačítko headsetu = přepnout vysílání',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: volumeKeyPtt,
              onChanged: onVolumeKeyPttChanged,
              title: const Text('Hlasitost dolů = PTT'),
              subtitle: const Text(
                'Držet pro vysílání, jen s otevřenou aplikací',
              ),
            ),
            if (!ptt.isDemo) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: ptt.status == PttStatus.connecting
                    ? null
                    : onPttReconnect,
                icon: const Icon(Icons.refresh),
                label: const Text('Znovu připojit PTT'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        const SystemSection(
          title: 'Car Mode',
          icon: Icons.directions_car_filled_outlined,
          children: [
            MonoLine(
              label: 'Android',
              value: 'nativní Kotlin Android Auto modul',
            ),
            MonoLine(label: 'iOS', value: 'nativní Swift CarPlay modul'),
            MonoLine(label: 'UI', value: 'mapa, tým, zprávy, PTT minimum'),
          ],
        ),
        const SizedBox(height: 10),
        const SizedBox(height: 10),
        SystemSection(
          title: 'Mise',
          icon: Icons.route_outlined,
          children: [
            MonoLine(
              label: 'Stopa',
              value:
                  '$trackPoints bodů · ${trackLengthKm.toStringAsFixed(2)} km',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onExportMission,
                    style: FilledButton.styleFrom(backgroundColor: rangerGreen),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Exportovat misi'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Smazat stopu',
                  onPressed: trackPoints == 0 ? null : onClearTrack,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (missionEvents.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final event in missionEvents.take(3))
                MissionEventTile(event: event, dense: true),
              TextButton.icon(
                key: const ValueKey('mission-log'),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: panelGreen,
                  builder: (_) => MissionLogSheet(events: missionEvents),
                ),
                icon: const Icon(Icons.list_alt, size: 18),
                label: Text('Deník mise (${missionEvents.length})'),
              ),
            ],
            Text(
              'GPX (body mise a stopa) + CSV zpráv a deníku událostí',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const AboutSection(),
        if (offlineMaps != null && mapCenter != null)
          OfflineMapsSection(
            controller: offlineMaps!,
            center: mapCenter!,
            visibleBounds: visibleMapBounds,
          ),
      ],
    );
  }

  String _bleStatusLabel(MeshtasticBleState state) {
    final device = state.deviceName == null ? '' : ' ${state.deviceName}';
    return switch (state.status) {
      MeshtasticBleStatus.idle => 'čeká',
      MeshtasticBleStatus.scanning => 'skenuje',
      MeshtasticBleStatus.connecting => 'připojuje$device',
      MeshtasticBleStatus.connected => 'připojeno$device',
      MeshtasticBleStatus.disconnected => 'odpojeno',
      MeshtasticBleStatus.error => 'chyba ${state.lastError ?? ''}',
    };
  }

  String _clockLabel(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  String _lastPacketLabel(MeshPacketDiagnostics diagnostics) {
    final lastPacketAt = diagnostics.lastPacketAt;
    if (lastPacketAt == null) {
      return '-';
    }
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(lastPacketAt.hour)}:${two(lastPacketAt.minute)}:${two(lastPacketAt.second)} / ${diagnostics.lastPacketSize} B';
  }
}

/// App version and build mode, so field reports can name the build.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SystemSection(
      title: 'O aplikaci',
      icon: Icons.info_outline,
      children: [
        FutureBuilder<PackageInfo>(
          future: _packageInfo(),
          builder: (context, snapshot) {
            final info = snapshot.data;
            return MonoLine(
              label: 'Verze',
              value: info == null
                  ? '-'
                  : '${info.version} (${info.buildNumber})',
            );
          },
        ),
        MonoLine(
          label: 'Backend',
          value: backendUrlFromEnvironment.isEmpty
              ? 'demo (bez serveru)'
              : backendUrlFromEnvironment,
        ),
        MonoLine(
          label: 'Build',
          value: kReleaseMode
              ? 'release'
              : (kProfileMode ? 'profile' : 'debug'),
        ),
      ],
    );
  }

  static Future<PackageInfo> _packageInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      return PackageInfo(
        appName: 'Tactical Mesh',
        packageName: '',
        version: '?',
        buildNumber: '?',
      );
    }
  }
}

/// Edits the one-tap message templates, one per line.
class QuickMessagesDialog extends StatefulWidget {
  const QuickMessagesDialog({required this.initial, super.key});

  final List<String> initial;

  @override
  State<QuickMessagesDialog> createState() => _QuickMessagesDialogState();
}

class _QuickMessagesDialogState extends State<QuickMessagesDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial.join('\n'),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Scrolls when the keyboard leaves little room (phone in landscape).
      scrollable: true,
      backgroundColor: panelGreen,
      title: const Text('Rychlé zprávy'),
      content: TextField(
        key: const ValueKey('quick-messages-input'),
        controller: _controller,
        minLines: 4,
        maxLines: 10,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
          helperText: 'Jedna zpráva na řádek; prázdné = výchozí',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Zrušit'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_controller.text.split('\n')),
          child: const Text('Uložit'),
        ),
      ],
    );
  }
}

/// One mission log line: time, kind and text.
class MissionEventTile extends StatelessWidget {
  const MissionEventTile({required this.event, this.dense = false, super.key});

  final MissionEvent event;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    String two(int value) => value.toString().padLeft(2, '0');
    final at = event.at;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 2 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${two(at.hour)}:${two(at.minute)}',
            style: const TextStyle(
              fontFamily: 'monospace',
              color: sand,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Icon(event.kind.icon, size: 16, color: Colors.white70),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              event.text,
              maxLines: dense ? 1 : 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The whole mission log, newest first.
class MissionLogSheet extends StatelessWidget {
  const MissionLogSheet({required this.events, super.key});

  final List<MissionEvent> events;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          children: [
            const Text(
              'Deník mise',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            for (final event in events) MissionEventTile(event: event),
          ],
        ),
      ),
    );
  }
}
