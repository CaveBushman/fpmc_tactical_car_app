import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../controllers/offline_maps_controller.dart';
import '../services/offline_tiles/tile_math.dart';
import '../theme.dart';
import 'common_widgets.dart';

/// System screen section: tile source, stored offline tiles and download of
/// the area around the current position.
class OfflineMapsSection extends StatefulWidget {
  const OfflineMapsSection({
    required this.controller,
    required this.center,
    this.visibleBounds,
    super.key,
  });

  final OfflineMapsController controller;
  final LatLng center;

  /// Area currently shown on the map, offered as a named download.
  final TileBounds? visibleBounds;

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
                      label: const Text('Stáhnout okolí'),
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
            if (controller.canDownload && widget.visibleBounds != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: progress != null
                    ? null
                    : () => _downloadVisible(controller, widget.visibleBounds!),
                icon: const Icon(Icons.crop_free),
                label: Text(
                  'Stáhnout zobrazenou oblast '
                  '(${controller.initialized ? controller.estimateMissingIn(widget.visibleBounds!) : '-'} dlaždic)',
                ),
              ),
            ],
            if (controller.areas.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Offline oblasti',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.86),
                  fontWeight: FontWeight.w800,
                ),
              ),
              for (final area in controller.areas)
                ListTile(
                  key: ValueKey('offline-area-${area.id}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    area.complete ? Icons.map_outlined : Icons.warning_amber,
                    color: area.complete ? sand : dangerRed,
                  ),
                  title: Text(area.name),
                  subtitle: Text(
                    '${area.tileCount} dlaždic · zoom ${area.minZoom}–${area.maxZoom} · '
                    '${area.createdAt.day}.${area.createdAt.month}.${area.createdAt.year}'
                    '${area.complete ? '' : ' · neúplná'}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Smazat oblast ${area.name}',
                    onPressed: progress != null
                        ? null
                        : () => controller.deleteArea(area),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _downloadVisible(
    OfflineMapsController controller,
    TileBounds bounds,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _AreaNameDialog(),
    );
    if (name != null) {
      await controller.downloadArea(name, bounds);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} kB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// Owns its text controller so it is disposed only after the dialog's exit
/// animation, not while the field is still on screen.
class _AreaNameDialog extends StatefulWidget {
  const _AreaNameDialog();

  @override
  State<_AreaNameDialog> createState() => _AreaNameDialogState();
}

class _AreaNameDialogState extends State<_AreaNameDialog> {
  final TextEditingController _name = TextEditingController(
    text: 'Oblast operace',
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Scrolls when the keyboard leaves little room (phone in landscape).
      scrollable: true,
      backgroundColor: panelGreen,
      title: const Text('Název offline oblasti'),
      content: TextField(
        controller: _name,
        autofocus: true,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Zrušit'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_name.text),
          child: const Text('Stáhnout'),
        ),
      ],
    );
  }
}
