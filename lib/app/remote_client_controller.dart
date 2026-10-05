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
import 'secret_store.dart';

/// Phone (or any non-Windows client) that enters a pairing code to remote-
/// control another phone in remote-host mode.
class RemoteClientController extends ChangeNotifier {
  RemoteClientController({PcDiscovery? discovery}) : discovery = discovery ?? PcDiscovery();

  final PcDiscovery discovery;
  final _secrets = PlatformSecretStore();
  late final SharedPreferences _prefs;

  late link.PcIdentity identity;
  List<link.PairedPhone> pairedHosts = [];
  link.PairStage pairStage = link.PairStage.idle;
  String? pairMessage;
  String? message;
  bool busy = false;

  RemoteClientSession? session;
  StreamSubscription<void>? _sessionSub;
  link.PairedPhone? activeHost;
  String? activeAddress;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    var id = _prefs.getString('remote.client.id');
    if (id == null) {
      id = randomToken(16);
      await _prefs.setString('remote.client.id', id);
    }
    final name = _prefs.getString('device.name') ?? Platform.localHostname;
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
    if (pairedHosts.isNotEmpty) {
      unawaited(reconnect(pairedHosts.last));
    }
    notifyListeners();
  }

  Future<void> _save() =>
      _secrets.write('remote.hosts', jsonEncode([for (final p in pairedHosts) p.toJson()]));

  RemoteHostStatus? get hostStatus => session?.lastStatus;
  bool get connected => session?.connected ?? false;

  Future<bool> pairWithCode(String code) async {
    if (pairStage == link.PairStage.searching || pairStage == link.PairStage.connecting) return false;
    pairMessage = null;
    try {
      final r = await link.pairWithCode(
        code: code,
        pc: identity,
        discovery: discovery,
        onStage: (s, d) {
          pairStage = s;
          pairMessage = switch (s) {
            link.PairStage.searching => 'Telefon aranıyor…',
            link.PairStage.connecting => 'Bulundu: $d — bağlanılıyor…',
            _ => null,
          };
          notifyListeners();
        },
      );
      // Prefer remote-host phones; still accept if mode missing (older builds).
      await _adopt(r);
      pairStage = link.PairStage.success;
      pairMessage = 'Eşleşti: ${r.phone.name}';
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
      await _attachSession(ws, phone, found.address.address);
      message = 'Bağlandı: ${phone.name}';
    } catch (e) {
      message = '$e';
    }
    notifyListeners();
  }

  Future<void> _adopt(link.PairResult r) async {
    pairedHosts = [...pairedHosts.where((p) => p.id != r.phone.id), r.phone];
    await _save();
    await _attachSession(r.socket, r.phone, r.address);
  }

  Future<void> _attachSession(WebSocket ws, link.PairedPhone phone, String address) async {
    await session?.close();
    await _sessionSub?.cancel();
    final s = RemoteClientSession();
    session = s;
    activeHost = phone;
    activeAddress = address;
    _sessionSub = s.changes.listen((_) => notifyListeners());
    // Drive until closed in background.
    unawaited(s.attach(ws, peer: address).then((_) {
      if (identical(session, s)) {
        session = null;
        notifyListeners();
      }
    }));
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
    _sessionSub?.cancel();
    session?.close();
    super.dispose();
  }
}
