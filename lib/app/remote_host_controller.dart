import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/control/android_remote_host_agent.dart';
import '../core/control/control_protocol.dart';
import '../core/control/phone_control_server.dart';
import '../core/control/remote_commands.dart';
import '../core/platform/android_bridge.dart';
import 'secret_store.dart';

enum RemoteHostStage { code, connected }

/// Phone acting as a remote host: shows a pairing code, accepts a controller
/// (another phone or PC), and executes `host.*` commands.
class RemoteHostController extends ChangeNotifier {
  RemoteHostController({this.startServer = true, RemoteCommandHandler? handler})
      : _injectedHandler = handler;

  final bool startServer;
  final RemoteCommandHandler? _injectedHandler;

  final _secrets = PlatformSecretStore();
  late final SharedPreferences _prefs;

  String deviceId = '';
  String deviceName = 'AktifDesk Telefon';
  RemoteHostStage stage = RemoteHostStage.code;
  String? message;
  late PhoneControlServer control;
  late RemoteCommandHandler agent;
  StreamSubscription<void>? _sub;
  StreamSubscription<PairingEvent>? _pairSub;
  PairedPc? lastController;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    deviceId = _prefs.getString('device.id') ?? '';
    if (deviceId.isEmpty) {
      deviceId = randomToken(12);
      await _prefs.setString('device.id', deviceId);
    }
    deviceName = _prefs.getString('device.name') ?? deviceName;
    final pcs = <PairedPc>[];
    try {
      final raw = await _secrets.read('remote.controllers');
      if (raw != null) {
        for (final j in jsonDecode(raw) as List) {
          pcs.add(PairedPc.fromJson((j as Map).cast<String, Object?>()));
        }
      }
    } catch (_) {}

    agent = _injectedHandler ?? AndroidRemoteHostAgent(deviceName: deviceName);
    if (agent is AndroidRemoteHostAgent) {
      (agent as AndroidRemoteHostAgent).deviceName = deviceName;
    }

    control = PhoneControlServer(
      deviceId: deviceId,
      deviceName: deviceName,
      pairedPcs: pcs,
      mode: ControlProtocol.modeRemoteHost,
      remoteHandler: agent,
    );
    _sub = control.changes.listen((_) {
      if (control.connection == ControlConnection.connected) {
        stage = RemoteHostStage.connected;
      } else if (stage == RemoteHostStage.connected) {
        stage = RemoteHostStage.code;
      }
      if (control.lastError != null) message = control.lastError;
      notifyListeners();
    });
    _pairSub = control.pairings.listen((e) async {
      lastController = e.pc;
      stage = RemoteHostStage.connected;
      await _save();
      message = 'Bağlandı: ${e.pc.name}';
      notifyListeners();
    });

    if (startServer) {
      await AndroidBridge.acquireMulticastLock().catchError((_) => false);
      try {
        await control.start();
      } catch (e) {
        message = 'Bağlantı servisi başlatılamadı: $e';
      }
    }
    notifyListeners();
  }

  Future<void> _save() => _secrets.write(
        'remote.controllers',
        jsonEncode([for (final p in control.pairedPcs) p.toJson()]),
      );

  String get pairingCode => control.code;
  ControlConnection get connection => control.connection;
  List<PairedPc> get controllers => control.pairedPcs;

  void newCode() {
    control.regenerateCode();
    notifyListeners();
  }

  Future<void> setDeviceName(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    deviceName = n;
    control.rename(n);
    if (agent is AndroidRemoteHostAgent) {
      (agent as AndroidRemoteHostAgent).deviceName = n;
    }
    await _prefs.setString('device.name', n);
    notifyListeners();
  }

  Future<void> forgetController(String id) async {
    control.forgetPc(id);
    await _save();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pairSub?.cancel();
    control.close();
    super.dispose();
  }
}
