import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Baked-in public relay endpoint. **Not a secret** — only the hostname of the
/// Railway WebSocket bridge. Auth is pairing codes + short-lived session keys;
/// [RAILWAY_TOKEN] and other deploy secrets must never ship in the APK.
///
/// Tamper resistance (honest limits):
/// * URL + expected host hash are compile-time constants (optionally overridden
///   only via `--dart-define=AKTIFDESK_RELAY_URL=…` at **build** time).
/// * Runtime settings / SharedPreferences / deeplinks cannot change the URL.
/// * [assertIntegrity] fails closed if the effective host does not match the
///   SHA-256 digest baked beside it.
/// * R8/ProGuard obfuscation slows casual string scraping; it is not DRM.
class RelayConfig {
  RelayConfig._();

  /// Build-time override (CI). Empty → use [bakedUrl].
  static const String _defineUrl = String.fromEnvironment('AKTIFDESK_RELAY_URL');

  /// Default public WSS path on Railway (non-secret).
  static const String bakedUrl =
      'wss://aktifdesk-relay-production.up.railway.app/aktifdesk-relay';

  /// SHA-256 hex of the UTF-8 hostname only (no scheme/path).
  static const String expectedHostSha256 =
      'b7d1b23c1589973146068d914c2015f743d176e4daedcdc61576187c7bb265a0';

  static const String expectedHost = 'aktifdesk-relay-production.up.railway.app';

  /// Effective URL used by the app — never read from preferences.
  static String get url {
    final d = _defineUrl.trim();
    return d.isEmpty ? bakedUrl : d;
  }

  static String? hostOf(String raw) {
    try {
      var s = raw.trim();
      if (s.startsWith('https://')) s = 'wss://${s.substring(8)}';
      if (s.startsWith('http://')) s = 'ws://${s.substring(7)}';
      final u = Uri.parse(s);
      if (u.host.isEmpty) return null;
      return u.host.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  static String hashHost(String host) =>
      sha256.convert(utf8.encode(host.toLowerCase())).toString();

  /// Returns null when OK; otherwise an error string (fail closed).
  static String? integrityError([String? candidate]) {
    final effective = candidate ?? url;
    final host = hostOf(effective);
    if (host == null) return 'Relay URL geçersiz';
    // Only wss in release-minded builds; ws allowed solely for localhost tests.
    final scheme = Uri.tryParse(effective)?.scheme;
    if (scheme == 'ws') {
      if (host == '127.0.0.1' || host == 'localhost') return null;
      return 'Relay yalnızca wss:// olmalı';
    }
    if (scheme != 'wss') return 'Relay şeması wss:// olmalı';
    final digest = hashHost(host);
    // If build-time define points at a different host, require matching define hash.
    const defineHash = String.fromEnvironment('AKTIFDESK_RELAY_HOST_SHA256');
    final expected = defineHash.trim().isEmpty ? expectedHostSha256 : defineHash.trim();
    if (digest != expected) {
      return 'Relay adresi bütünlük kontrolünü geçemedi (tamper)';
    }
    return null;
  }

  static void assertIntegrity() {
    final err = integrityError();
    if (err != null) {
      throw StateError(err);
    }
  }

  static bool get isIntegrityOk => integrityError() == null;
}
