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

  /// Last communication group chosen by [userName].
  Future<String?> groupFor(String userName) =>
      _get((prefs) => prefs.getString('${prefix}group.$userName'));

  Future<void> setGroupFor(String userName, String groupId) =>
      _set((prefs) => prefs.setString('${prefix}group.$userName', groupId));

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
