import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/relay/relay_config.dart';

/// Persisted app settings. Relay URL is **not** stored here (baked + integrity).
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);
  final SharedPreferences _prefs;

  static Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    // Migrate away any previously stored relay URL override (security).
    await p.remove('settings.relayUrl');
    return AppSettings._(p);
  }

  static const _kRemoteLink = 'settings.uzakBaglanti';
  static const _kDeviceName = 'device.name';
  static const _kTutorialDone = 'onboarding.tutorialDone';

  bool get uzakBaglanti => _prefs.getBool(_kRemoteLink) ?? false;
  String get deviceName => _prefs.getString(_kDeviceName) ?? 'AktifDesk Telefon';
  bool get tutorialDone => _prefs.getBool(_kTutorialDone) ?? false;

  /// Baked WSS endpoint when integrity passes; never from preferences.
  String? get relayUrl => RelayConfig.isIntegrityOk ? RelayConfig.url : null;

  bool get relayEnabled => uzakBaglanti && relayUrl != null;

  Future<void> setUzakBaglanti(bool on) async {
    await _prefs.setBool(_kRemoteLink, on);
    notifyListeners();
  }

  Future<void> setDeviceName(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    await _prefs.setString(_kDeviceName, n);
    notifyListeners();
  }

  Future<void> setTutorialDone(bool done) async {
    await _prefs.setBool(_kTutorialDone, done);
    notifyListeners();
  }
}
