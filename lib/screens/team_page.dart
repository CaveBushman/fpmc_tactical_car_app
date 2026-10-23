
import 'package:flutter/material.dart';

import '../models/mesh_node.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/node_widgets.dart';

class TeamPage extends StatefulWidget {
  const TeamPage({required this.nodes, required this.onCheckIn, super.key});

  final List<MeshNode> nodes;
  final ValueChanged<MeshNode> onCheckIn;

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text;
    final filteredNodes = widget.nodes
        .where((node) => node.matchesSearch(query))
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TacticalSearchField(
            controller: _searchController,
            label: 'Vyhledat uživatele',
            hint: 'Callsign, MGRS, node ID, stav',
          ),
        ),
        Expanded(
          child: filteredNodes.isEmpty
              ? EmptySearchState(query: query)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: filteredNodes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final node = filteredNodes[index];
                    return NodeCard(
                      node: node,
                      onCheckIn: node.isSelf
                          ? null
                          : () => widget.onCheckIn(node),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class EmptySearchState extends StatelessWidget {
  const EmptySearchState({required this.query, super.key});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_search_outlined,
              color: sand.withValues(alpha: 0.75),
              size: 38,
            ),
            const SizedBox(height: 10),
            Text(
              'Nenalezen žádný uživatel',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              query,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: sand,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
