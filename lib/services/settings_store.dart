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

  /// Night mode follows civil twilight at the own position (default off).
  Future<bool> nightModeAuto() async =>
      await _get((prefs) => prefs.getBool('${prefix}nightModeAuto')) ?? false;

  Future<void> setNightModeAuto(bool value) =>
      _set((prefs) => prefs.setBool('${prefix}nightModeAuto', value));

  /// Send the phone GPS position into the mesh (default on).
  Future<bool> sharePositionToMesh() async =>
      await _get((prefs) => prefs.getBool('${prefix}sharePositionToMesh')) ??
      true;

  Future<void> setSharePositionToMesh(bool value) =>
      _set((prefs) => prefs.setBool('${prefix}sharePositionToMesh', value));

  Future<bool> mgrsGrid() async =>
      await _get((prefs) => prefs.getBool('${prefix}mgrsGrid')) ?? true;

  Future<void> setMgrsGrid(bool value) =>
      _set((prefs) => prefs.setBool('${prefix}mgrsGrid', value));

  /// Sparser GPS and position sharing (default off).
  Future<bool> batterySaver() async =>
      await _get((prefs) => prefs.getBool('${prefix}batterySaver')) ?? false;

  Future<void> setBatterySaver(bool value) =>
      _set((prefs) => prefs.setBool('${prefix}batterySaver', value));

  /// Warn near DANGER points (default on).
  Future<bool> dangerAlerts() async =>
      await _get((prefs) => prefs.getBool('${prefix}dangerAlerts')) ?? true;

  Future<void> setDangerAlerts(bool value) =>
      _set((prefs) => prefs.setBool('${prefix}dangerAlerts', value));

  /// Full screen: Android status and navigation bars hidden (default on).
  Future<bool> hideSystemBars() async =>
      await _get((prefs) => prefs.getBool('${prefix}hideSystemBars')) ?? true;

  Future<void> setHideSystemBars(bool value) =>
      _set((prefs) => prefs.setBool('${prefix}hideSystemBars', value));

  /// Map turned so the direction of travel points up (default off).
  Future<bool> mapHeadingUp() async =>
      await _get((prefs) => prefs.getBool('${prefix}mapHeadingUp')) ?? false;

  Future<void> setMapHeadingUp(bool value) =>
      _set((prefs) => prefs.setBool('${prefix}mapHeadingUp', value));

  static const defaultQuickMessages = [
    'PŘESUN',
    'ZASTAVENÍ',
    'BEZ ZMĚN',
    'POTŘEBUJI PODPORU',
    'NÁVRAT',
  ];

  /// One-tap message templates for the Messages tab.
  Future<List<String>> quickMessages() async =>
      await _get((prefs) => prefs.getStringList('${prefix}quickMessages')) ??
      defaultQuickMessages;

  Future<void> setQuickMessages(List<String> value) =>
      _set((prefs) => prefs.setStringList('${prefix}quickMessages', value));

  /// Alert when a teammate goes LOST (default on).
  Future<bool> lostContactAlerts() async =>
      await _get((prefs) => prefs.getBool('${prefix}lostContactAlerts')) ??
      true;

  Future<void> setLostContactAlerts(bool value) =>
      _set((prefs) => prefs.setBool('${prefix}lostContactAlerts', value));

  /// User name of the last successful login on this device (prefilled).
  Future<String?> lastUserName() =>
      _get((prefs) => prefs.getString('${prefix}lastUserName'));

  Future<void> setLastUserName(String value) =>
      _set((prefs) => prefs.setString('${prefix}lastUserName', value));

  /// Last communication group chosen by [userName].
  Future<String?> groupFor(String userName) =>
      _get((prefs) => prefs.getString('${prefix}group.$userName'));

  Future<void> setGroupFor(String userName, String groupId) =>
      _set((prefs) => prefs.setString('${prefix}group.$userName', groupId));

  /// Code of the point [userName] marked as their base.
  Future<String?> baseFor(String userName) =>
      _get((prefs) => prefs.getString('${prefix}base.$userName'));

  /// Null clears the base.
  Future<void> setBaseFor(String userName, String? code) => _set(
    (prefs) => code == null
        ? prefs.remove('${prefix}base.$userName')
        : prefs.setString('${prefix}base.$userName', code),
  );

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
