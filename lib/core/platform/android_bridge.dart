import 'dart:io';

import 'package:flutter/services.dart';

/// Android-only native helpers (see MainActivity.kt).
class AndroidBridge {
  static const _ch = MethodChannel('aktifdesk/native');

  static bool get supported => Platform.isAndroid;

  /// Installed Moonlight package (com.limelight / .debug / root), or null.
  static Future<String?> moonlightPackage() async {
    if (!supported) return null;
    return _ch.invokeMethod<String>('moonlightPackage');
  }

  /// Start a stream in Moonlight for an already-paired host/app.
  static Future<bool> launchMoonlight({
    required String pcUuid,
    String? pcName,
    int? appId,
    String? appName,
  }) async {
    if (!supported) return false;
    return await _ch.invokeMethod<bool>('launchMoonlight', {
          'uuid': pcUuid,
          'pcName': pcName,
          'appId': appId?.toString(),
          'appName': appName,
        }) ??
        false;
  }

  static Future<void> openMoonlight() async {
    if (!supported) return;
    await _ch.invokeMethod('openMoonlight');
  }

  static Future<void> openMoonlightStore() async {
    if (!supported) return;
    await _ch.invokeMethod('openStore', {'package': 'com.limelight'});
  }

  /// Keep the phone screen on (used while remotely holding AFK mode).
  static Future<void> setKeepScreenOn(bool on) async {
    if (!supported) return;
    await _ch.invokeMethod('keepScreenOn', {'on': on});
  }

  /// Hold a Wi-Fi MulticastLock so UDP discovery broadcasts from the PC are
  /// delivered while AktifDesk is open (some devices filter them otherwise).
  static Future<bool> acquireMulticastLock() async {
    if (!supported) return false;
    return await _ch.invokeMethod<bool>('multicastLock', {'on': true}) ?? false;
  }

  /// Best-effort wake + unlock. Secure locks cannot be dismissed without
  /// elevated privileges; see returned map.
  ///
  /// Keys: `ok` (bool), `secure` (bool?), `message` (String?).
  static Future<Map<String, Object?>> requestUnlock() async {
    if (!supported) {
      return {'ok': false, 'message': 'Android değil'};
    }
    final r = await _ch.invokeMethod<Map>('requestUnlock');
    return (r ?? const {}).map((k, v) => MapEntry('$k', v));
  }

  /// Launch an installed package or open an http(s) URL.
  static Future<bool> launchApp({String? packageName, String? url}) async {
    if (!supported) return false;
    return await _ch.invokeMethod<bool>('launchApp', {
          'package': packageName,
          'url': url,
        }) ??
        false;
  }

  /// Scaffold for future MediaProjection screen capture. Always returns false
  /// until a media backend is bundled.
  static Future<Map<String, Object?>> requestScreenCapture() async {
    if (!supported) {
      return {'ok': false, 'reason': 'not_android'};
    }
    final r = await _ch.invokeMethod<Map>('requestScreenCapture');
    return (r ?? const {'ok': false, 'reason': 'not_implemented'})
        .map((k, v) => MapEntry('$k', v));
  }
}
