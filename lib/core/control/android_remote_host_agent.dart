import '../platform/android_bridge.dart';
import 'control_protocol.dart';
import 'remote_commands.dart';

/// Executes remote-host commands on the Android phone being controlled.
///
/// Honest limits (no root / no Device Admin wipe):
/// * Keep-awake = FLAG_KEEP_SCREEN_ON + foreground service + wake lock.
/// * Unlock = best-effort: turn screen on + dismiss keyguard only when the
///   device has no secure lock (PIN/pattern/password/biometrics).
/// * Launch = http(s) URLs or an explicit installed package launch intent.
/// * Tap / swipe / Back-Home-Recents = AccessibilityService (user must enable).
/// * Screen share = scaffolded; full mirroring needs MediaProjection + encoder.
class AndroidRemoteHostAgent implements RemoteCommandHandler {
  AndroidRemoteHostAgent({required this.deviceName});

  String deviceName;
  bool keepAwake = false;
  String screenShareState = 'scaffolded'; // unavailable | scaffolded | active
  String? lastMessage;
  bool accessibility = false;

  Future<void> refreshPermissions() async {
    try {
      final p = await AndroidBridge.permissionStatus();
      accessibility = p['accessibility'] == true || p['accessibilityRunning'] == true;
    } catch (_) {
      accessibility = false;
    }
  }

  @override
  Future<Map<String, Object?>> handle(String type, Map<String, Object?> msg) async {
    switch (type) {
      case ControlProtocol.hostPing:
      case ControlProtocol.hostStatus:
        await refreshPermissions();
        return _status().toJson();
      case ControlProtocol.hostPermissions:
        final p = await AndroidBridge.permissionStatus();
        accessibility = p['accessibility'] == true || p['accessibilityRunning'] == true;
        return {..._status().toJson(), 'permissions': p};
      case ControlProtocol.hostKeepAwake:
        final on = msg['enabled'] == true;
        await AndroidBridge.setKeepScreenOn(on);
        keepAwake = on;
        lastMessage = on ? 'Ekran açık tutuluyor' : 'Ekran kilidi serbest';
        return _status().toJson();
      case ControlProtocol.hostUnlock:
        final r = await AndroidBridge.requestUnlock();
        lastMessage = r['message'] as String? ?? (r['ok'] == true ? 'Uyandırıldı' : 'Kilit açılamadı');
        return {..._status().toJson(), ...r};
      case ControlProtocol.hostLaunch:
        final pkg = msg['package'] as String?;
        final url = msg['url'] as String?;
        if ((pkg == null || pkg.isEmpty) && (url == null || url.isEmpty)) {
          throw StateError('package veya url gerekli');
        }
        if (url != null && url.isNotEmpty) {
          final u = Uri.tryParse(url);
          if (u == null || (u.scheme != 'http' && u.scheme != 'https')) {
            throw StateError('Sadece http/https URL açılabilir');
          }
        }
        if (pkg != null && pkg.isNotEmpty && !RegExp(r'^[a-zA-Z][\w.]*$').hasMatch(pkg)) {
          throw StateError('Geçersiz paket adı');
        }
        final ok = await AndroidBridge.launchApp(packageName: pkg, url: url);
        lastMessage = ok ? 'Uygulama/URL açıldı' : 'Açılamadı (yüklü değil veya engellendi)';
        return {..._status().toJson(), 'launched': ok};
      case ControlProtocol.hostTap:
        final x = (msg['x'] as num?)?.toDouble();
        final y = (msg['y'] as num?)?.toDouble();
        if (x == null || y == null) throw StateError('x/y gerekli');
        final abs = msg['absolute'] == true;
        final r = await AndroidBridge.injectTap(x: x, y: y, absolute: abs);
        lastMessage = r['message'] as String?;
        return {..._status().toJson(), ...r};
      case ControlProtocol.hostSwipe:
        final x1 = (msg['x1'] as num?)?.toDouble();
        final y1 = (msg['y1'] as num?)?.toDouble();
        final x2 = (msg['x2'] as num?)?.toDouble();
        final y2 = (msg['y2'] as num?)?.toDouble();
        if (x1 == null || y1 == null || x2 == null || y2 == null) {
          throw StateError('x1/y1/x2/y2 gerekli');
        }
        final dur = (msg['durationMs'] as num?)?.toInt() ?? 300;
        final abs = msg['absolute'] == true;
        final r = await AndroidBridge.injectSwipe(
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          durationMs: dur,
          absolute: abs,
        );
        lastMessage = r['message'] as String?;
        return {..._status().toJson(), ...r};
      case ControlProtocol.hostKey:
        final key = '${msg['key'] ?? ''}'.trim();
        if (key.isEmpty) throw StateError('key gerekli');
        final r = await AndroidBridge.injectKey(key);
        lastMessage = r['message'] as String?;
        return {..._status().toJson(), ...r};
      case ControlProtocol.hostText:
        final text = '${msg['text'] ?? ''}';
        if (text.isEmpty) throw StateError('text gerekli');
        // Cap length to avoid abuse / huge payloads.
        final clipped = text.length > 500 ? text.substring(0, 500) : text;
        final r = await AndroidBridge.injectText(clipped);
        lastMessage = r['message'] as String?;
        return {..._status().toJson(), ...r};
      case ControlProtocol.hostScreenShare:
        try {
          final r = await AndroidBridge.requestScreenCapture();
          screenShareState = 'scaffolded';
          lastMessage = r['message'] as String? ??
              'Ekran paylaşımı henüz yok — MediaProjection + WebRTC medya arka ucu sonraki sürümde';
          return {
            ..._status().toJson(),
            'ok': false,
            'reason': r['reason'] ?? 'screen_share_not_implemented',
            ...r,
          };
        } catch (e) {
          screenShareState = 'scaffolded';
          lastMessage = 'Ekran paylaşımı hatası izole edildi: $e';
          return {
            ..._status().toJson(),
            'ok': false,
            'reason': 'screen_share_error',
            'message': lastMessage,
          };
        }
      default:
        throw StateError('Bilinmeyen komut: $type');
    }
  }

  RemoteHostStatus _status() => RemoteHostStatus(
        deviceName: deviceName,
        keepAwake: keepAwake,
        screenShare: screenShareState,
        message: lastMessage,
        extras: {
          'accessibility': accessibility,
          'inputReady': accessibility,
        },
      );
}

/// In-memory agent for unit tests (no Android).
class FakeRemoteHostAgent implements RemoteCommandHandler {
  FakeRemoteHostAgent({this.deviceName = 'Test Host'});
  String deviceName;
  bool keepAwake = false;
  final launches = <String>[];
  final gestures = <String>[];
  int unlockCalls = 0;
  bool accessibility = true;

  @override
  Future<Map<String, Object?>> handle(String type, Map<String, Object?> msg) async {
    switch (type) {
      case ControlProtocol.hostPing:
      case ControlProtocol.hostStatus:
        return RemoteHostStatus(
          deviceName: deviceName,
          keepAwake: keepAwake,
          screenShare: 'scaffolded',
          extras: {'accessibility': accessibility, 'inputReady': accessibility},
        ).toJson();
      case ControlProtocol.hostPermissions:
        return {
          'permissions': {
            'accessibility': accessibility,
            'accessibilityRunning': accessibility,
            'batteryOptimizationIgnored': true,
            'overlay': false,
            'notifications': true,
            'notificationListener': false,
            'foregroundService': true,
            'wakeLock': true,
            'screenCapture': false,
          },
          'accessibility': accessibility,
          'inputReady': accessibility,
        };
      case ControlProtocol.hostKeepAwake:
        keepAwake = msg['enabled'] == true;
        return RemoteHostStatus(
          deviceName: deviceName,
          keepAwake: keepAwake,
          screenShare: 'scaffolded',
        ).toJson();
      case ControlProtocol.hostUnlock:
        unlockCalls++;
        return {'ok': true, 'secure': false, 'message': 'fake unlock'};
      case ControlProtocol.hostLaunch:
        launches.add('${msg['package']}|${msg['url']}');
        return {'launched': true};
      case ControlProtocol.hostTap:
        gestures.add('tap:${msg['x']},${msg['y']}');
        return {'ok': accessibility, 'reason': accessibility ? null : 'accessibility_off'};
      case ControlProtocol.hostSwipe:
        gestures.add('swipe:${msg['x1']},${msg['y1']}->${msg['x2']},${msg['y2']}');
        return {'ok': accessibility};
      case ControlProtocol.hostKey:
        gestures.add('key:${msg['key']}');
        return {'ok': accessibility};
      case ControlProtocol.hostText:
        gestures.add('text:${msg['text']}');
        return {'ok': accessibility};
      case ControlProtocol.hostScreenShare:
        return {'ok': false, 'reason': 'screen_share_not_implemented'};
      default:
        throw StateError(type);
    }
  }
}
