import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../controllers/offline_maps_controller.dart';
import '../theme.dart';
import 'common_widgets.dart';

/// System screen section: tile source, stored offline tiles and download of
/// the area around the current position.
class OfflineMapsSection extends StatefulWidget {
  const OfflineMapsSection({
    required this.controller,
    required this.center,
    super.key,
  });

  final OfflineMapsController controller;
  final LatLng center;

  @override
  State<OfflineMapsSection> createState() => _OfflineMapsSectionState();
}

class _OfflineMapsSectionState extends State<OfflineMapsSection> {
  static const _radii = [2.0, 5.0, 10.0, 25.0];
  double _radiusKm = 5;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final source = controller.source;
        final progress = controller.progress;
        final missing = controller.initialized
            ? controller.estimateMissing(widget.center, _radiusKm)
            : null;
        return SystemSection(
          title: 'Mapy',
          icon: Icons.map_outlined,
          children: [
            MonoLine(label: 'Podklad', value: source.name),
            MonoLine(
              label: 'Offline',
              value: controller.isSupported
                  ? '${controller.tileCount} dlaždic / ${_formatBytes(controller.sizeBytes)}'
                  : 'na tomto zařízení nepodporováno',
            ),
            const MonoLine(
              label: 'Cache',
              value: 'prohlížené dlaždice, 512 MB, 30 dní',
            ),
            const SizedBox(height: 8),
            if (!source.allowsBulkDownload)
              Text(
                '${source.name} nepovoluje hromadné stahování. Pro offline '
                'balíčky nastav vlastní zdroj dlaždic (TILE_URL).',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              )
            else ...[
              Text(
                'Okruh kolem vlastní pozice',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.86)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final radius in _radii)
                    ChoiceChip(
                      label: Text('${radius.toStringAsFixed(0)} km'),
                      selected: _radiusKm == radius,
                      onSelected: progress != null
                          ? null
                          : (_) => setState(() => _radiusKm = radius),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              MonoLine(
                label: 'Ke stažení',
                value: missing == null
                    ? '-'
                    : '$missing dlaždic (zoom ${OfflineMapsController.minZoom}–${OfflineMapsController.maxDownloadZoom})',
              ),
            ],
            if (progress != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress.fraction,
                color: sand,
                backgroundColor: Colors.white12,
              ),
              const SizedBox(height: 4),
              MonoLine(
                label: 'Průběh',
                value:
                    '${progress.done}/${progress.total}'
                    '${progress.failed > 0 ? ', chyby ${progress.failed}' : ''}',
              ),
            ],
            if (controller.lastError != null) ...[
              const SizedBox(height: 6),
              Text(
                controller.lastError!,
                style: const TextStyle(color: dangerRed, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (progress != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: controller.cancelDownload,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Zrušit'),
                    ),
                  )
                else
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: controller.canDownload && (missing ?? 0) > 0
                          ? () => controller.downloadAround(
                              widget.center,
                              _radiusKm,
                            )
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: rangerGreen,
                      ),
                      icon: const Icon(Icons.download_for_offline_outlined),
                      label: const Text('Stáhnout oblast'),
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Smazat offline mapy',
                  onPressed: controller.tileCount == 0 || progress != null
                      ? null
                      : controller.clear,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} kB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
