import 'package:shared_preferences/shared_preferences.dart';

/// Non-sensitive user preferences (plain shared preferences; operational
/// data lives in the encrypted TacticalStateStore).
class SettingsStore {
  const SettingsStore({this.prefix = 'settings.'});

  final String prefix;

  Future<double?> fontScale() =>
      _get((prefs) => prefs.getDouble('${prefix}fontScale'));

  Future<void> setFontScale(double value) =>
      _set((prefs) => prefs.setDouble('${prefix}fontScale', value));

  Future<bool> volumeKeyPtt() async =>
      await _get((prefs) => prefs.getBool('${prefix}volumeKeyPtt')) ?? false;

  Future<void> setVolumeKeyPtt(bool value) =>
      _set((prefs) => prefs.setBool('${prefix}volumeKeyPtt', value));

  Future<bool> nightMode() async =>
      await _get((prefs) => prefs.getBool('${prefix}nightMode')) ?? false;

  Future<void> setNightMode(bool value) =>
      _set((prefs) => prefs.setBool('${prefix}nightMode', value));

  /// Send the phone GPS position into the mesh (default on).
  Future<bool> sharePositionToMesh() async =>
      await _get((prefs) => prefs.getBool('${prefix}sharePositionToMesh')) ??
      true;

  Future<void> setSharePositionToMesh(bool value) =>
      _set((prefs) => prefs.setBool('${prefix}sharePositionToMesh', value));

  /// Last communication group chosen by [userName].
  Future<String?> groupFor(String userName) =>
      _get((prefs) => prefs.getString('${prefix}group.$userName'));

  Future<void> setGroupFor(String userName, String groupId) =>
      _set((prefs) => prefs.setString('${prefix}group.$userName', groupId));

  /// Removes every stored preference (emergency wipe).
  Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().where((k) => k.startsWith(prefix))) {
        await prefs.remove(key);
      }
    } catch (_) {
      // Nothing stored or no preferences backend.
    }
  }

  Future<T?> _get<T>(T? Function(SharedPreferences prefs) read) async {
    try {
      return read(await SharedPreferences.getInstance());
    } catch (_) {
      return null;
    }
  }

  Future<void> _set(
    Future<bool> Function(SharedPreferences prefs) write,
  ) async {
    try {
      await write(await SharedPreferences.getInstance());
    } catch (_) {
      // Preferences are a convenience; failing to save is not fatal.
    }
  }
}
