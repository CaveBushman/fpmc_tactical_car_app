
import 'package:flutter/material.dart';

import '../services/encrypted_ptt_service.dart';
import '../services/location_service.dart';
import '../services/mesh_packet_repository.dart';
import '../services/meshtastic_ble_service.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/position_widgets.dart';

class SystemsPage extends StatelessWidget {
  const SystemsPage({
    required this.meshConnected,
    required this.internetVoiceOnline,
    required this.onVoiceChanged,
    required this.onBleConnect,
    required this.bleState,
    required this.packetDiagnostics,
    required this.pttState,
    required this.fontScale,
    required this.onFontScaleChanged,
    this.locationState = LocationState.idle,
    this.onLocationStart,
    this.onLocationSettings,
    super.key,
  });

  final bool meshConnected;
  final bool internetVoiceOnline;
  final ValueChanged<bool> onVoiceChanged;
  final VoidCallback onBleConnect;
  final MeshtasticBleState bleState;
  final MeshPacketDiagnostics packetDiagnostics;
  final EncryptedPttState pttState;
  final double fontScale;
  final ValueChanged<double> onFontScaleChanged;
  final LocationState locationState;
  final VoidCallback? onLocationStart;
  final VoidCallback? onLocationSettings;

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
            SwitchListTile(
              value: internetVoiceOnline,
              onChanged: onVoiceChanged,
              title: const Text('Simulace PTT'),
              subtitle: const Text(
                'Hlasový server (WebRTC/LiveKit) zatím není napojen',
              ),
            ),
            MonoLine(label: 'Kanál', value: pttState.channel),
            MonoLine(
              label: 'Šifrování',
              value: pttState.encrypted ? 'AES-GCM 256 aktivní' : 'vypnuto',
            ),
            const MonoLine(label: 'Režim', value: 'Push-to-talk floor control'),
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
        const SystemSection(
          title: 'Mapy',
          icon: Icons.map_outlined,
          children: [
            MonoLine(label: 'Podklad', value: 'OpenStreetMap raster tiles'),
            MonoLine(label: 'Cache', value: 'automatická, 512 MB, 30 dní'),
            MonoLine(label: 'Offline', value: 'použije uložené dlaždice'),
          ],
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
