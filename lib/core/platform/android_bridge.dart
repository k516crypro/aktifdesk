import 'dart:io';

import 'package:flutter/services.dart';

/// Android-only native helpers (see MainActivity.kt / AccessibilityService).
class AndroidBridge {
  static const _ch = MethodChannel('aktifdesk/native');

  static bool get supported => Platform.isAndroid;

  static Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    if (!supported) return null;
    try {
      return await _ch.invokeMethod<T>(method, args);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, Object?>> _invokeMap(String method, [Map<String, Object?>? args]) async {
    if (!supported) return const {'ok': false, 'reason': 'not_android'};
    try {
      final r = await _ch.invokeMethod<Map>(method, args);
      return (r ?? const {'ok': false}).map((k, v) => MapEntry('$k', v));
    } catch (e) {
      return {'ok': false, 'reason': 'bridge_error', 'message': '$e'};
    }
  }

  /// Installed Moonlight package (com.limelight / .debug / root), or null.
  static Future<String?> moonlightPackage() async {
    if (!supported) return null;
    return _invoke<String>('moonlightPackage');
  }

  /// Start a stream in Moonlight for an already-paired host/app.
  static Future<bool> launchMoonlight({
    required String pcUuid,
    String? pcName,
    int? appId,
    String? appName,
  }) async {
    if (!supported) return false;
    return await _invoke<bool>('launchMoonlight', {
          'uuid': pcUuid,
          'pcName': pcName,
          'appId': appId?.toString(),
          'appName': appName,
        }) ??
        false;
  }

  static Future<void> openMoonlight() async {
    if (!supported) return;
    await _invoke('openMoonlight');
  }

  static Future<void> openMoonlightStore() async {
    if (!supported) return;
    await _invoke('openStore', {'package': 'com.limelight'});
  }

  /// Keep the phone screen on (used while remotely holding AFK mode).
  static Future<void> setKeepScreenOn(bool on) async {
    if (!supported) return;
    await _invoke('keepScreenOn', {'on': on});
  }

  /// Hold a Wi-Fi MulticastLock so UDP discovery broadcasts from the PC are
  /// delivered while AktifDesk is open (some devices filter them otherwise).
  static Future<bool> acquireMulticastLock() async {
    if (!supported) return false;
    return await _invoke<bool>('multicastLock', {'on': true}) ?? false;
  }

  /// Best-effort wake + unlock. Secure locks cannot be dismissed without
  /// elevated privileges; see returned map.
  static Future<Map<String, Object?>> requestUnlock() async {
    if (!supported) {
      return {'ok': false, 'message': 'Android değil'};
    }
    return _invokeMap('requestUnlock');
  }

  /// Launch an installed package or open an http(s) URL.
  static Future<bool> launchApp({String? packageName, String? url}) async {
    if (!supported) return false;
    return await _invoke<bool>('launchApp', {
          'package': packageName,
          'url': url,
        }) ??
        false;
  }

  /// Scaffold for future MediaProjection screen capture. Errors are isolated.
  static Future<Map<String, Object?>> requestScreenCapture() async {
    if (!supported) {
      return {'ok': false, 'reason': 'not_android'};
    }
    return _invokeMap('requestScreenCapture');
  }

  /// Snapshot of host "Tam erişim" checklist permissions.
  static Future<Map<String, Object?>> permissionStatus() async {
    if (!supported) {
      return {
        'accessibility': false,
        'accessibilityRunning': false,
        'batteryOptimizationIgnored': false,
        'overlay': false,
        'notifications': false,
        'notificationListener': false,
        'foregroundService': false,
        'wakeLock': false,
        'screenCapture': false,
      };
    }
    return _invokeMap('permissionStatus');
  }

  /// Open the matching Settings screen (`accessibility`, `battery`, `overlay`, …).
  static Future<bool> openPermissionSettings(String which) async {
    if (!supported) return false;
    return await _invoke<bool>('openPermissionSettings', {'which': which}) ?? false;
  }

  static Future<void> requestRuntimePermissions() async {
    if (!supported) return;
    await _invoke('requestRuntimePermissions');
  }

  static Future<void> startHostForeground({bool waiting = true}) async {
    if (!supported) return;
    await _invoke('startHostForeground', {'waiting': waiting});
  }

  static Future<void> updateHostForeground({bool waiting = true}) async {
    if (!supported) return;
    await _invoke('updateHostForeground', {'waiting': waiting});
  }

  static Future<void> stopHostForeground() async {
    if (!supported) return;
    await _invoke('stopHostForeground');
  }

  /// Normalized (0..1) tap, or absolute px when [absolute] is true.
  static Future<Map<String, Object?>> injectTap({
    required double x,
    required double y,
    bool absolute = false,
  }) =>
      _invokeMap('injectTap', {'x': x, 'y': y, 'absolute': absolute});

  static Future<Map<String, Object?>> injectSwipe({
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    int durationMs = 300,
    bool absolute = false,
  }) =>
      _invokeMap('injectSwipe', {
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
        'durationMs': durationMs,
        'absolute': absolute,
      });

  static Future<Map<String, Object?>> injectKey(String key) =>
      _invokeMap('injectKey', {'key': key});

  static Future<Map<String, Object?>> injectText(String text) =>
      _invokeMap('injectText', {'text': text});
}
