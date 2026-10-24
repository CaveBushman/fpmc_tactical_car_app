import 'dart:async';

import '../services/settings_store.dart';

/// The user's display and behaviour settings. Setting a value saves it;
/// [load] reads them all back and [reset] returns to the defaults (the
/// store itself is wiped separately).
class UserPreferences {
  UserPreferences(this.store);

  final SettingsStore store;

  double _fontScale = 1.0;
  bool _volumeKeyPtt = false;
  bool _nightMode = false;
  bool _nightModeAuto = false;
  bool _sharePositionToMesh = true;
  bool _mgrsGrid = true;
  bool _batterySaver = false;
  bool _dangerAlerts = true;
  bool _hideSystemBars = true;
  bool _mapHeadingUp = false;
  List<String> _quickMessages = SettingsStore.defaultQuickMessages;

  double get fontScale => _fontScale;
  set fontScale(double value) {
    _fontScale = value;
    unawaited(store.setFontScale(value));
  }

  bool get volumeKeyPtt => _volumeKeyPtt;
  set volumeKeyPtt(bool value) {
    _volumeKeyPtt = value;
    unawaited(store.setVolumeKeyPtt(value));
  }

  bool get nightMode => _nightMode;
  set nightMode(bool value) {
    _nightMode = value;
    unawaited(store.setNightMode(value));
  }

  bool get nightModeAuto => _nightModeAuto;
  set nightModeAuto(bool value) {
    _nightModeAuto = value;
    unawaited(store.setNightModeAuto(value));
  }

  bool get sharePositionToMesh => _sharePositionToMesh;
  set sharePositionToMesh(bool value) {
    _sharePositionToMesh = value;
    unawaited(store.setSharePositionToMesh(value));
  }

  bool get mgrsGrid => _mgrsGrid;
  set mgrsGrid(bool value) {
    _mgrsGrid = value;
    unawaited(store.setMgrsGrid(value));
  }

  bool get batterySaver => _batterySaver;
  set batterySaver(bool value) {
    _batterySaver = value;
    unawaited(store.setBatterySaver(value));
  }

  bool get dangerAlerts => _dangerAlerts;
  set dangerAlerts(bool value) {
    _dangerAlerts = value;
    unawaited(store.setDangerAlerts(value));
  }

  bool get hideSystemBars => _hideSystemBars;
  set hideSystemBars(bool value) {
    _hideSystemBars = value;
    unawaited(store.setHideSystemBars(value));
  }

  bool get mapHeadingUp => _mapHeadingUp;
  set mapHeadingUp(bool value) {
    _mapHeadingUp = value;
    unawaited(store.setMapHeadingUp(value));
  }

  List<String> get quickMessages => _quickMessages;
  set quickMessages(List<String> value) {
    _quickMessages = List.unmodifiable(value);
    unawaited(store.setQuickMessages(_quickMessages));
  }

  Future<void> load() async {
    _fontScale = ((await store.fontScale()) ?? 1.0).clamp(0.85, 1.35);
    _volumeKeyPtt = await store.volumeKeyPtt();
    _nightMode = await store.nightMode();
    _nightModeAuto = await store.nightModeAuto();
    _sharePositionToMesh = await store.sharePositionToMesh();
    _mgrsGrid = await store.mgrsGrid();
    _batterySaver = await store.batterySaver();
    _dangerAlerts = await store.dangerAlerts();
    _hideSystemBars = await store.hideSystemBars();
    _mapHeadingUp = await store.mapHeadingUp();
    _quickMessages = List.unmodifiable(await store.quickMessages());
  }

  void reset() {
    _fontScale = 1.0;
    _volumeKeyPtt = false;
    _nightMode = false;
    _nightModeAuto = false;
    _sharePositionToMesh = true;
    _mgrsGrid = true;
    _batterySaver = false;
    _dangerAlerts = true;
    _hideSystemBars = true;
    _mapHeadingUp = false;
    _quickMessages = SettingsStore.defaultQuickMessages;
  }
}
