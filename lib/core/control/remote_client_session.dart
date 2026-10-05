import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'control_protocol.dart';
import 'phone_control_server.dart';
import 'remote_commands.dart';

/// Runs on the *controller* (another phone or the PC) after it has opened a
/// WebSocket to a phone in [ControlProtocol.modeRemoteHost]. Sends `host.*`
/// requests and waits for `result` replies.
class RemoteClientSession {
  RemoteClientSession({this.requestTimeout = const Duration(seconds: 20)});

  final Duration requestTimeout;
  WebSocket? _ws;
  int _nextId = 1;
  final _pending = <int, Completer<Map<String, Object?>>>{};
  final _changes = StreamController<void>.broadcast();

  String? peerName;
  String? peerMode;
  RemoteHostStatus? lastStatus;
  String? lastError;
  bool get connected => _ws != null;

  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Serve / drive an already-authenticated socket until it closes.
  Future<void> attach(WebSocket ws, {String? peer}) {
    final closed = Completer<void>();
    _ws = ws;
    ws.pingInterval = const Duration(seconds: 10);
    lastError = null;
    _notify();

    void done() {
      if (!identical(_ws, ws)) return;
      _ws = null;
      _failPending('Bağlantı koptu');
      _notify();
      if (!closed.isCompleted) closed.complete();
    }

    ws.listen(
      _onData,
      onDone: done,
      onError: (_) => done(),
      cancelOnError: true,
    );
    // Ask for an immediate status snapshot.
    unawaited(ping().catchError((_) => null));
    return closed.future;
  }

  void _onData(Object? data) {
    Map<String, Object?> m;
    try {
      m = (jsonDecode(data as String) as Map).cast<String, Object?>();
    } catch (_) {
      return;
    }
    switch (m['type']) {
      case ControlProtocol.hello:
        peerName = (m['host'] as String?) ?? peerName;
        peerMode = m['mode'] as String? ?? peerMode;
      case ControlProtocol.result:
        final c = _pending.remove((m['id'] as num?)?.toInt());
        if (c != null && !c.isCompleted) {
          if (m['ok'] == true) {
            final v = m['value'];
            if (v is Map) {
              lastStatus = RemoteHostStatus.fromJson(v.cast<String, Object?>());
            }
            c.complete(m);
          } else {
            c.completeError(ControlException('${m['error'] ?? 'Hata'}'));
          }
        }
    }
    _notify();
  }

  void _failPending(String why) {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(ControlException(why));
    }
    _pending.clear();
  }

  Future<Map<String, Object?>> request(String type, [Map<String, Object?> body = const {}]) {
    final ws = _ws;
    if (ws == null) return Future.error(ControlException('Bağlı değil'));
    final id = _nextId++;
    final c = Completer<Map<String, Object?>>();
    _pending[id] = c;
    ws.add(jsonEncode({'type': type, 'id': id, ...body}));
    return c.future.timeout(
      requestTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw ControlException('Yanıt zaman aşımı');
      },
    );
  }

  Future<RemoteHostStatus?> ping() async {
    final r = await request(ControlProtocol.hostPing);
    final v = r['value'];
    if (v is Map) {
      lastStatus = RemoteHostStatus.fromJson(v.cast<String, Object?>());
      return lastStatus;
    }
    return null;
  }

  Future<RemoteHostStatus?> status() async {
    final r = await request(ControlProtocol.hostStatus);
    final v = r['value'];
    if (v is Map) {
      lastStatus = RemoteHostStatus.fromJson(v.cast<String, Object?>());
      return lastStatus;
    }
    return null;
  }

  Future<void> setKeepAwake(bool on) =>
      request(ControlProtocol.hostKeepAwake, {'enabled': on});

  Future<Map<String, Object?>> requestUnlock() async {
    final r = await request(ControlProtocol.hostUnlock);
    final v = r['value'];
    return v is Map ? v.cast<String, Object?>() : r;
  }

  Future<Map<String, Object?>> launch({String? packageName, String? url}) async {
    final r = await request(ControlProtocol.hostLaunch, {
      'package': ?packageName,
      'url': ?url,
    });
    final v = r['value'];
    return v is Map ? v.cast<String, Object?>() : r;
  }

  Future<Map<String, Object?>> screenShare({required bool enable}) async {
    final r = await request(ControlProtocol.hostScreenShare, {'enable': enable});
    final v = r['value'];
    return v is Map ? v.cast<String, Object?>() : r;
  }

  Future<Map<String, Object?>> tap({
    required double x,
    required double y,
    bool absolute = false,
  }) async {
    final r = await request(ControlProtocol.hostTap, {
      'x': x,
      'y': y,
      'absolute': absolute,
    });
    final v = r['value'];
    return v is Map ? v.cast<String, Object?>() : r;
  }

  Future<Map<String, Object?>> swipe({
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    int durationMs = 300,
    bool absolute = false,
  }) async {
    final r = await request(ControlProtocol.hostSwipe, {
      'x1': x1,
      'y1': y1,
      'x2': x2,
      'y2': y2,
      'durationMs': durationMs,
      'absolute': absolute,
    });
    final v = r['value'];
    return v is Map ? v.cast<String, Object?>() : r;
  }

  Future<Map<String, Object?>> key(String key) async {
    final r = await request(ControlProtocol.hostKey, {'key': key});
    final v = r['value'];
    return v is Map ? v.cast<String, Object?>() : r;
  }

  Future<Map<String, Object?>> text(String text) async {
    final r = await request(ControlProtocol.hostText, {'text': text});
    final v = r['value'];
    return v is Map ? v.cast<String, Object?>() : r;
  }

  Future<Map<String, Object?>> permissions() async {
    final r = await request(ControlProtocol.hostPermissions);
    final v = r['value'];
    return v is Map ? v.cast<String, Object?>() : r;
  }

  Future<void> close() async {
    _failPending('Kapatıldı');
    await _ws?.close(WebSocketStatus.goingAway);
    _ws = null;
    await _changes.close();
  }
}
