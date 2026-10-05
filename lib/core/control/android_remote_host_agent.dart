import '../platform/android_bridge.dart';
import 'control_protocol.dart';
import 'remote_commands.dart';

/// Executes remote-host commands on the Android phone being controlled.
///
/// Honest limits (no root):
/// * Keep-awake = FLAG_KEEP_SCREEN_ON / partial wake lock while AktifDesk is
///   in the foreground.
/// * Unlock = best-effort: turn screen on + dismiss keyguard only when the
///   device has no secure lock (PIN/pattern/password/biometrics). Secure
///   locks cannot be bypassed without Device Owner / Accessibility abuse.
/// * Launch = http(s) URLs or an explicit installed package launch intent.
/// * Screen share = scaffolded; full mirroring needs MediaProjection + an
///   encoder (WebRTC stub exists but media backend is not bundled).
class AndroidRemoteHostAgent implements RemoteCommandHandler {
  AndroidRemoteHostAgent({required this.deviceName});

  String deviceName;
  bool keepAwake = false;
  String screenShareState = 'scaffolded'; // unavailable | scaffolded | active
  String? lastMessage;

  @override
  Future<Map<String, Object?>> handle(String type, Map<String, Object?> msg) async {
    switch (type) {
      case ControlProtocol.hostPing:
      case ControlProtocol.hostStatus:
        return _status().toJson();
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
        // Safety: only http(s) URLs; packages must look like reverse-DNS ids.
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
      case ControlProtocol.hostScreenShare:
        // MediaProjection + encoder not bundled in v1.2.0 MVP.
        screenShareState = 'scaffolded';
        lastMessage =
            'Ekran paylaşımı henüz yok — MediaProjection + WebRTC medya arka ucu sonraki sürümde';
        return {
          ..._status().toJson(),
          'ok': false,
          'reason': 'screen_share_not_implemented',
        };
      default:
        throw StateError('Bilinmeyen komut: $type');
    }
  }

  RemoteHostStatus _status() => RemoteHostStatus(
        deviceName: deviceName,
        keepAwake: keepAwake,
        screenShare: screenShareState,
        message: lastMessage,
      );
}

/// In-memory agent for unit tests (no Android).
class FakeRemoteHostAgent implements RemoteCommandHandler {
  FakeRemoteHostAgent({this.deviceName = 'Test Host'});
  String deviceName;
  bool keepAwake = false;
  final launches = <String>[];
  int unlockCalls = 0;

  @override
  Future<Map<String, Object?>> handle(String type, Map<String, Object?> msg) async {
    switch (type) {
      case ControlProtocol.hostPing:
      case ControlProtocol.hostStatus:
        return RemoteHostStatus(
          deviceName: deviceName,
          keepAwake: keepAwake,
          screenShare: 'scaffolded',
        ).toJson();
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
      case ControlProtocol.hostScreenShare:
        return {'ok': false, 'reason': 'screen_share_not_implemented'};
      default:
        throw StateError(type);
    }
  }
}
