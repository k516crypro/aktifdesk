import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/control/android_remote_host_agent.dart';
import '../core/control/control_protocol.dart';
import '../core/control/phone_control_server.dart';
import '../core/control/remote_commands.dart';
import '../core/platform/android_bridge.dart';
import '../core/relay/relay_client.dart';
import '../core/relay/relay_config.dart';
import '../core/relay/relay_host_session.dart';
import 'app_settings.dart';
import 'secret_store.dart';

enum RemoteHostStage { code, connected }

/// Phone acting as a remote host: LAN server + optional Railway relay.
class RemoteHostController extends ChangeNotifier {
  RemoteHostController({
    this.startServer = true,
    RemoteCommandHandler? handler,
    this._settings,
  })  : _injectedHandler = handler;

  final bool startServer;
  final RemoteCommandHandler? _injectedHandler;
  AppSettings? _settings;

  final _secrets = PlatformSecretStore();
  late final SharedPreferences _prefs;
  final _relay = RelayClient();

  String deviceId = '';
  String deviceName = 'AktifDesk Telefon';
  RemoteHostStage stage = RemoteHostStage.code;
  String? message;
  late PhoneControlServer control;
  late RemoteCommandHandler agent;
  StreamSubscription<void>? _sub;
  StreamSubscription<PairingEvent>? _pairSub;
  PairedPc? lastController;
  Map<String, Object?> permissions = {};
  Timer? _permRefresh;
  Timer? _keepAlive;

  RelayHostSession? _relaySession;
  StreamSubscription<void>? _relaySub;
  Future<void>? _relayLoop;
  bool _closing = false;
  bool relayWaiting = false;
  String? relayPeerName;

  AppSettings? get settings => _settings;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _settings ??= await AppSettings.load();
    deviceId = _prefs.getString('device.id') ?? '';
    if (deviceId.isEmpty) {
      deviceId = randomToken(12);
      await _prefs.setString('device.id', deviceId);
    }
    deviceName = _settings!.deviceName;
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
        unawaited(AndroidBridge.updateHostForeground(waiting: false));
      } else if (stage == RemoteHostStage.connected && !(_relaySession?.connected ?? false)) {
        stage = RemoteHostStage.code;
        unawaited(AndroidBridge.updateHostForeground(waiting: true));
      }
      if (control.lastError != null) message = control.lastError;
      notifyListeners();
    });
    _pairSub = control.pairings.listen((e) async {
      lastController = e.pc;
      stage = RemoteHostStage.connected;
      await _save();
      message = 'LAN bağlandı: ${e.pc.name}';
      unawaited(AndroidBridge.updateHostForeground(waiting: false));
      notifyListeners();
    });

    if (startServer) {
      await AndroidBridge.acquireMulticastLock().catchError((_) => false);
      try {
        await AndroidBridge.requestRuntimePermissions();
      } catch (_) {}
      try {
        await AndroidBridge.startHostForeground(waiting: true);
        await AndroidBridge.setKeepScreenOn(true);
        if (agent is AndroidRemoteHostAgent) {
          (agent as AndroidRemoteHostAgent).keepAwake = true;
        }
      } catch (_) {}
      try {
        await control.start();
      } catch (e) {
        message = 'LAN servisi başlatılamadı: $e';
      }
      await refreshPermissions();
      _permRefresh = Timer.periodic(const Duration(seconds: 4), (_) {
        unawaited(refreshPermissions());
      });
      _keepAlive = Timer.periodic(const Duration(minutes: 2), (_) {
        unawaited(AndroidBridge.setKeepScreenOn(true));
        unawaited(AndroidBridge.updateHostForeground(
          waiting: stage != RemoteHostStage.connected,
        ));
      });
      _startRelayLoop();
    }
    notifyListeners();
  }

  void _startRelayLoop() {
    if (_relayLoop != null) return;
    _relayLoop = _runRelayLoop();
  }

  Future<void> _runRelayLoop() async {
    while (!_closing) {
      final s = _settings;
      if (s == null || !s.relayEnabled || !RelayConfig.isIntegrityOk) {
        relayWaiting = false;
        await Future<void>.delayed(const Duration(seconds: 2));
        continue;
      }
      final url = RelayConfig.url;
      relayWaiting = true;
      notifyListeners();
      try {
        final pipe = await _relay.connectHost(
          relayUrl: url,
          code: control.code,
          deviceId: deviceId,
          name: deviceName,
          waitForPeer: true,
        );
        relayWaiting = false;
        relayPeerName = pipe.peer.name;
        message = 'Uzak bağlantı: ${pipe.peer.name}';
        stage = RemoteHostStage.connected;
        unawaited(AndroidBridge.updateHostForeground(waiting: false));
        notifyListeners();

        final session = RelayHostSession(handler: agent, deviceName: deviceName);
        _relaySession = session;
        await _relaySub?.cancel();
        _relaySub = session.changes.listen((_) => notifyListeners());
        await session.attach(pipe);
        // Disconnected — loop will re-register with current code.
        message = 'Uzak bağlantı koptu — yeniden bekleniyor';
        if (control.connection != ControlConnection.connected) {
          stage = RemoteHostStage.code;
          unawaited(AndroidBridge.updateHostForeground(waiting: true));
        }
        relayPeerName = null;
        notifyListeners();
      } catch (e) {
        relayWaiting = false;
        if (!_closing && (_settings?.relayEnabled ?? false)) {
          message = 'Relay: $e';
          notifyListeners();
          await Future<void>.delayed(const Duration(seconds: 4));
        }
      }
    }
  }

  /// Call after settings change so relay loop picks up new URL / toggle.
  void onSettingsChanged() {
    notifyListeners();
    // Loop polls relayEnabled; if turned on while idle it will connect.
  }

  Future<void> refreshPermissions() async {
    try {
      permissions = await AndroidBridge.permissionStatus();
      if (agent is AndroidRemoteHostAgent) {
        await (agent as AndroidRemoteHostAgent).refreshPermissions();
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> openPermission(String which) async {
    final ok = await AndroidBridge.openPermissionSettings(which);
    Future<void>.delayed(const Duration(seconds: 1), refreshPermissions);
    return ok;
  }

  Future<void> _save() => _secrets.write(
        'remote.controllers',
        jsonEncode([for (final p in control.pairedPcs) p.toJson()]),
      );

  String get pairingCode => control.code;
  ControlConnection get connection => control.connection;
  List<PairedPc> get controllers => control.pairedPcs;
  bool get connected =>
      control.connection == ControlConnection.connected || (_relaySession?.connected ?? false);

  bool get accessibilityReady =>
      permissions['accessibility'] == true || permissions['accessibilityRunning'] == true;

  void newCode() {
    control.regenerateCode();
    // Force relay re-register with new code by closing active relay session.
    unawaited(_relaySession?.close());
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
    await _settings?.setDeviceName(n);
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
    _closing = true;
    _permRefresh?.cancel();
    _keepAlive?.cancel();
    _sub?.cancel();
    _pairSub?.cancel();
    _relaySub?.cancel();
    unawaited(_relaySession?.dispose() ?? Future.value());
    unawaited(AndroidBridge.setKeepScreenOn(false));
    unawaited(AndroidBridge.stopHostForeground());
    control.close();
    super.dispose();
  }
}
