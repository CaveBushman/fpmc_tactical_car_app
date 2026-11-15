import 'package:flutter/material.dart';

import '../models/messaging.dart';
import '../theme.dart';

/// A priority order from the commanders' panel waiting for "Rozumím",
/// above every tab so it is not missed while the map is open. Shows the
/// newest one; older waiting orders are counted.
class HqOrderBanner extends StatelessWidget {
  const HqOrderBanner({
    required this.orders,
    required this.onAcknowledge,
    this.onShow,
    super.key,
  });

  /// Waiting orders, newest first.
  final List<MeshMessage> orders;
  final ValueChanged<MeshMessage> onAcknowledge;

  /// Opens the order in the messages.
  final ValueChanged<MeshMessage>? onShow;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const SizedBox.shrink();
    }
    final order = orders.first;
    final more = orders.length - 1;
    final title = [
      'ROZKAZ Z VELITELSTVÍ',
      ?order.targetLabel,
      order.timeLabel(DateTime.now()),
      if (more > 0) '+$more další',
    ].join(' · ');
    return Container(
      key: const ValueKey('hq-order-banner'),
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      decoration: BoxDecoration(
        color: signalAmber,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onShow == null ? null : () => onShow!(order),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(
              children: [
                const Icon(Icons.campaign, color: Colors.black, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        order.body,
                        key: const ValueKey('hq-order-text'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  key: const ValueKey('hq-order-ack'),
                  onPressed: () => onAcknowledge(order),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: signalAmber,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text(
                    'Rozumím',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
