import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../control/control_protocol.dart';
import '../control/remote_commands.dart';
import 'relay_client.dart';

/// Host-side handler for a relay-bridged WebSocket (same `host.*` semantics as LAN).
class RelayHostSession {
  RelayHostSession({required this.handler, required this.deviceName});

  final RemoteCommandHandler handler;
  String deviceName;
  WebSocket? _ws;
  final _changes = StreamController<void>.broadcast();
  bool get connected => _ws != null;
  String? peerName;
  Stream<void> get changes => _changes.stream;

  Future<void> attach(RelayPipe pipe) async {
    await close();
    final ws = pipe.ws;
    _ws = ws;
    peerName = pipe.peer.name;
    ws.pingInterval = const Duration(seconds: 15);
    try {
      ws.add(jsonEncode({
        'type': ControlProtocol.hello,
        'version': ControlProtocol.version,
        'host': deviceName,
        'mode': ControlProtocol.modeRemoteHost,
        'via': 'relay',
      }));
    } catch (_) {}
    _notify();

    final done = Completer<void>();
    ws.listen(
      _onData,
      onDone: () {
        if (identical(_ws, ws)) {
          _ws = null;
          _notify();
        }
        if (!done.isCompleted) done.complete();
      },
      onError: (_) {
        if (identical(_ws, ws)) {
          _ws = null;
          _notify();
        }
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    return done.future;
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void _onData(Object? data) {
    Map<String, Object?> m;
    try {
      m = (jsonDecode(data as String) as Map).cast<String, Object?>();
    } catch (_) {
      return;
    }
    // Ignore leftover relay control frames.
    if (m['type'] == 'waiting' || m['type'] == 'paired' || m['type'] == 'peer_left') {
      return;
    }
    final type = m['type'];
    if (m['id'] != null && type is String && type.startsWith('host.')) {
      unawaited(_handle(m));
    }
  }

  Future<void> _handle(Map<String, Object?> m) async {
    final ws = _ws;
    final id = m['id'];
    if (ws == null) return;
    void reply(bool ok, [Object? error, Object? value]) {
      try {
        ws.add(jsonEncode({
          'type': ControlProtocol.result,
          'id': id,
          'ok': ok,
          if (error != null) 'error': '$error',
          'value': ?value,
        }));
      } catch (_) {}
    }

    try {
      final value = await handler.handle('${m['type']}', m);
      reply(true, null, value);
      _notify();
    } catch (e) {
      reply(false, e);
    }
  }

  Future<void> close() async {
    final ws = _ws;
    _ws = null;
    try {
      await ws?.close(WebSocketStatus.goingAway);
    } catch (_) {}
    _notify();
  }

  Future<void> dispose() async {
    await close();
    await _changes.close();
  }
}
