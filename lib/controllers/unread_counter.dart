/// Incoming messages per group not yet seen on the Messages tab.
class UnreadCounter {
  final Map<String, int> _counts = {};

  int countIn(String groupId) => _counts[groupId] ?? 0;

  int total(Iterable<String> groupIds) =>
      groupIds.fold(0, (sum, id) => sum + countIn(id));

  void add(String groupId) => _counts[groupId] = countIn(groupId) + 1;

  /// Returns whether anything was unread.
  bool markRead(String groupId) => _counts.remove(groupId) != null;

  void clear() => _counts.clear();
}
