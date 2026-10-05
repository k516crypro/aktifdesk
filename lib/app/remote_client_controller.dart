import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/control/control_protocol.dart';
import '../core/control/discovery.dart';
import '../core/control/pc_link.dart' as link;
import '../core/control/remote_client_session.dart';
import '../core/control/remote_commands.dart';
import '../core/platform/android_bridge.dart';
import '../core/relay/relay_client.dart';
import '../core/relay/relay_config.dart';
import 'app_settings.dart';
import 'secret_store.dart';

/// Controller phone: LAN discovery or optional Railway relay ("Uzak bağlantı").
class RemoteClientController extends ChangeNotifier {
  RemoteClientController({PcDiscovery? discovery, this._settings})
      : discovery = discovery ?? PcDiscovery();

  final PcDiscovery discovery;
  AppSettings? _settings;
  final _secrets = PlatformSecretStore();
  final _relay = RelayClient();
  late final SharedPreferences _prefs;

  late link.PcIdentity identity;
  List<link.PairedPhone> pairedHosts = [];
  link.PairStage pairStage = link.PairStage.idle;
  String? pairMessage;
  String? message;
  bool busy = false;
  Timer? _reconnectTimer;
  bool preferRelay = false;

  RemoteClientSession? session;
  StreamSubscription<void>? _sessionSub;
  link.PairedPhone? activeHost;
  String? activeAddress;
  bool viaRelay = false;

  AppSettings? get settings => _settings;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _settings ??= await AppSettings.load();
    preferRelay = _settings!.relayEnabled;
    var id = _prefs.getString('remote.client.id');
    if (id == null) {
      id = randomToken(16);
      await _prefs.setString('remote.client.id', id);
    }
    final name = _settings!.deviceName;
    identity = link.PcIdentity(id: id, name: name.isEmpty ? 'AktifDesk İstemci' : name);

    final stored = await _secrets.read('remote.hosts');
    if (stored != null) {
      try {
        pairedHosts = [
          for (final j in jsonDecode(stored) as List)
            link.PairedPhone.fromJson((j as Map).cast<String, Object?>())
        ];
      } catch (_) {}
    }
    await AndroidBridge.acquireMulticastLock().catchError((_) => false);
    if (pairedHosts.isNotEmpty && !preferRelay) {
      unawaited(reconnect(pairedHosts.last));
    }
    notifyListeners();
  }

  void onSettingsChanged() {
    preferRelay = _settings?.relayEnabled ?? false;
    notifyListeners();
  }

  Future<void> _save() =>
      _secrets.write('remote.hosts', jsonEncode([for (final p in pairedHosts) p.toJson()]));

  RemoteHostStatus? get hostStatus => session?.lastStatus;
  bool get connected => session?.connected ?? false;

  Future<bool> pairWithCode(String code) async {
    if (pairStage == link.PairStage.searching || pairStage == link.PairStage.connecting) {
      return false;
    }
    pairMessage = null;
    final useRelay = preferRelay || (_settings?.relayEnabled ?? false);
    if (useRelay) {
      return _pairViaRelay(code);
    }
    return _pairViaLan(code);
  }

  Future<bool> _pairViaLan(String code) async {
    try {
      final r = await link.pairWithCode(
        code: code,
        pc: identity,
        discovery: discovery,
        onStage: (s, d) {
          pairStage = s;
          pairMessage = switch (s) {
            link.PairStage.searching => 'LAN’da telefon aranıyor…',
            link.PairStage.connecting => 'Bulundu: $d — bağlanılıyor…',
            _ => null,
          };
          notifyListeners();
        },
      );
      await _adopt(r, relay: false);
      pairStage = link.PairStage.success;
      pairMessage = 'Eşleşti (LAN): ${r.phone.name}';
      notifyListeners();
      return true;
    } catch (e) {
      // If LAN fails and relay is configured, offer automatic fallback.
      if (RelayConfig.isIntegrityOk) {
        pairMessage = 'LAN bulunamadı — uzak bağlantı deneniyor…';
        notifyListeners();
        return _pairViaRelay(code);
      }
      pairStage = link.PairStage.failed;
      pairMessage = '$e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> _pairViaRelay(String code) async {
    if (!RelayConfig.isIntegrityOk) {
      pairStage = link.PairStage.failed;
      pairMessage = RelayConfig.integrityError() ?? 'Relay bütünlük hatası';
      notifyListeners();
      return false;
    }
    final url = RelayConfig.url;
    pairStage = link.PairStage.searching;
    pairMessage = 'Relay üzerinden eşleşiliyor…';
    notifyListeners();
    try {
      pairStage = link.PairStage.connecting;
      notifyListeners();
      final pipe = await _relay.connectClient(
        relayUrl: url,
        code: code,
        deviceId: identity.id,
        name: identity.name,
        pairKey: randomToken(24),
      );
      final phone = link.PairedPhone(
        id: pipe.peer.id.isEmpty ? 'relay-${PairingCode.normalize(code)}' : pipe.peer.id,
        name: pipe.peer.name.isEmpty ? 'Uzak host' : pipe.peer.name,
        key: randomToken(24),
      );
      pairedHosts = [...pairedHosts.where((p) => p.id != phone.id), phone];
      await _save();
      await _attachSession(pipe.ws, phone, 'relay', relay: true);
      pairStage = link.PairStage.success;
      pairMessage = 'Eşleşti (uzak): ${phone.name}';
      notifyListeners();
      return true;
    } catch (e) {
      pairStage = link.PairStage.failed;
      pairMessage = '$e';
      notifyListeners();
      return false;
    }
  }

  Future<void> reconnect(link.PairedPhone phone) async {
    message = 'Yeniden bağlanılıyor…';
    notifyListeners();
    if (preferRelay || (_settings?.relayEnabled ?? false)) {
      message = 'Uzak modda yeniden bağlanmak için kodu tekrar gir';
      notifyListeners();
      return;
    }
    try {
      final found = await discovery.findPaired(
        deviceId: phone.id,
        pcId: identity.id,
        key: phone.key,
        timeout: const Duration(seconds: 10),
      );
      if (found == null) {
        message = 'Telefon bulunamadı (AktifDesk uzaktan modda açık olmalı)';
        notifyListeners();
        return;
      }
      final ws = await link.connectToPhone(found.address.address, found.port, identity, token: phone.key);
      await _attachSession(ws, phone, found.address.address, relay: false);
      message = 'Bağlandı: ${phone.name}';
    } catch (e) {
      message = '$e';
    }
    notifyListeners();
  }

  Future<void> _adopt(link.PairResult r, {required bool relay}) async {
    pairedHosts = [...pairedHosts.where((p) => p.id != r.phone.id), r.phone];
    await _save();
    await _attachSession(r.socket, r.phone, r.address, relay: relay);
  }

  Future<void> _attachSession(
    WebSocket ws,
    link.PairedPhone phone,
    String address, {
    required bool relay,
  }) async {
    _reconnectTimer?.cancel();
    await session?.close();
    await _sessionSub?.cancel();
    final s = RemoteClientSession();
    session = s;
    activeHost = phone;
    activeAddress = address;
    viaRelay = relay;
    _sessionSub = s.changes.listen((_) => notifyListeners());
    unawaited(s.attach(ws, peer: address).then((_) {
      if (identical(session, s)) {
        session = null;
        notifyListeners();
        if (!relay) _scheduleReconnect(phone);
      }
    }));
  }

  void _scheduleReconnect(link.PairedPhone phone) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (session != null || activeHost?.id != phone.id) return;
      message = 'Bağlantı koptu — yeniden deneniyor…';
      notifyListeners();
      unawaited(reconnect(phone));
    });
  }

  Future<void> _run(Future<void> Function() f) async {
    busy = true;
    notifyListeners();
    try {
      await f();
    } catch (e) {
      message = '$e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> ping() => _run(() async {
        await session?.ping();
      });

  Future<void> setKeepAwake(bool on) => _run(() async {
        await session?.setKeepAwake(on);
        await session?.status();
      });

  Future<void> unlock() => _run(() async {
        final r = await session?.requestUnlock();
        message = r?['message'] as String? ?? 'Unlock gönderildi';
      });

  Future<void> launchUrl(String url) => _run(() async {
        await session?.launch(url: url);
      });

  Future<void> launchPackage(String packageName) => _run(() async {
        await session?.launch(packageName: packageName);
      });

  Future<void> requestScreenShare() => _run(() async {
        final r = await session?.screenShare(enable: true);
        message = r?['message'] as String? ??
            'Ekran paylaşımı henüz yok (MediaProjection iskeleti)';
      });

  Future<void> tap(double x, double y) => _run(() async {
        final r = await session?.tap(x: x, y: y);
        if (r != null && r['ok'] != true) {
          message = r['message'] as String? ?? 'Dokunma başarısız (Erişilebilirlik?)';
        }
      });

  void tapQuick(double x, double y) {
    final s = session;
    if (s == null || !s.connected) return;
    unawaited(s.tap(x: x, y: y).catchError((_) => <String, Object?>{}));
  }

  void swipeQuick(double x1, double y1, double x2, double y2, {int durationMs = 280}) {
    final s = session;
    if (s == null || !s.connected) return;
    unawaited(s
        .swipe(x1: x1, y1: y1, x2: x2, y2: y2, durationMs: durationMs)
        .catchError((_) => <String, Object?>{}));
  }

  Future<void> sendKey(String key) => _run(() async {
        final r = await session?.key(key);
        if (r != null && r['ok'] != true) {
          message = r['message'] as String? ?? 'Tuş başarısız';
        }
      });

  Future<void> sendText(String text) => _run(() async {
        final r = await session?.text(text);
        if (r != null && r['ok'] != true) {
          message = r['message'] as String? ?? 'Metin gönderilemedi';
        }
      });

  Future<void> forget(String id) async {
    if (activeHost?.id == id) {
      await session?.close();
      session = null;
      activeHost = null;
    }
    pairedHosts = pairedHosts.where((p) => p.id != id).toList();
    await _save();
    notifyListeners();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _sessionSub?.cancel();
    session?.close();
    super.dispose();
  }
}
