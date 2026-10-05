import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'relay_config.dart';

/// Cross-network pairing via a public/self-hosted WebSocket relay (Railway).
///
/// LAN discovery remains the default fast path. Set [relayUrl] to something like
/// `wss://your-app.up.railway.app/aktifdesk-relay` to enable "Uzak bağlantı".
class RelayClient {
  RelayClient({this.connectTimeout = const Duration(seconds: 20)});

  final Duration connectTimeout;

  /// Normalize user input into a WebSocket URL ending with `/aktifdesk-relay`.
  static String? normalizeUrl(String? raw) {
    var s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    if (s.startsWith('https://')) s = 'wss://${s.substring(8)}';
    if (s.startsWith('http://')) s = 'ws://${s.substring(7)}';
    if (!s.startsWith('ws://') && !s.startsWith('wss://')) {
      s = 'wss://$s';
    }
    // Strip trailing slash before appending path if needed.
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    if (!s.contains('/aktifdesk-relay')) {
      s = '$s/aktifdesk-relay';
    }
    return s;
  }

  /// Connect as host, wait until a client pairs (or [waitForPeer] is false → after registered).
  Future<RelayPipe> connectHost({
    required String relayUrl,
    required String code,
    required String deviceId,
    required String name,
    bool waitForPeer = true,
  }) =>
      _connect(
        relayUrl: relayUrl,
        role: 'host',
        code: code,
        deviceId: deviceId,
        name: name,
        waitForPeer: waitForPeer,
      );

  /// Connect as client and wait until the host is paired.
  Future<RelayPipe> connectClient({
    required String relayUrl,
    required String code,
    required String deviceId,
    required String name,
    String? pairKey,
  }) =>
      _connect(
        relayUrl: relayUrl,
        role: 'client',
        code: code,
        deviceId: deviceId,
        name: name,
        pairKey: pairKey,
        waitForPeer: true,
      );

  Future<RelayPipe> _connect({
    required String relayUrl,
    required String role,
    required String code,
    required String deviceId,
    required String name,
    String? pairKey,
    required bool waitForPeer,
  }) async {
    // Prefer baked RelayConfig; ignore tampered / empty caller overrides.
    final url = RelayConfig.url;
    final err = RelayConfig.integrityError(url);
    if (err != null) {
      throw StateError(err);
    }
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'ws' && uri.scheme != 'wss')) {
      throw StateError('Geçersiz relay URL');
    }

    final ws = await WebSocket.connect(url).timeout(connectTimeout);
    ws.pingInterval = const Duration(seconds: 20);

    final paired = Completer<RelayPeer>();
    final pending = <String>[];
    StreamSubscription? sub;

    void fail(Object e) {
      if (!paired.isCompleted) paired.completeError(e);
    }

    sub = ws.listen(
      (data) {
        if (paired.isCompleted) {
          // After handshake, pipe owns the socket — shouldn't get here.
          return;
        }
        Map<String, Object?> m;
        try {
          m = (jsonDecode(data as String) as Map).cast<String, Object?>();
        } catch (_) {
          return;
        }
        switch (m['type']) {
          case 'waiting':
            if (!waitForPeer && !paired.isCompleted) {
              paired.complete(const RelayPeer(id: '', name: '', role: ''));
            }
          case 'paired':
            final peer = (m['peer'] as Map?)?.cast<String, Object?>() ?? {};
            if (!paired.isCompleted) {
              paired.complete(RelayPeer(
                id: '${peer['id'] ?? ''}',
                name: '${peer['name'] ?? ''}',
                role: '${peer['role'] ?? ''}',
              ));
            }
          case 'error':
            fail(StateError('${m['error'] ?? 'relay_error'}'));
          case 'peer_left':
            fail(StateError('Karşı taraf ayrıldı'));
        }
      },
      onError: fail,
      onDone: () => fail(StateError('Relay bağlantısı kapandı')),
      cancelOnError: true,
    );

    ws.add(jsonEncode({
      'v': 1,
      'type': 'hello',
      'role': role,
      'code': code.replaceAll(RegExp(r'[^0-9]'), ''),
      'deviceId': deviceId,
      'name': name,
      if (pairKey != null && pairKey.isNotEmpty) 'pairKey': pairKey,
    }));

    try {
      final peer = await paired.future.timeout(
        waitForPeer ? const Duration(minutes: 10) : connectTimeout,
        onTimeout: () => throw StateError(
          waitForPeer ? 'Relay: karşı taraf beklenirken zaman aşımı' : 'Relay zaman aşımı',
        ),
      );
      await sub.cancel();
      // Any frames that arrived between cancel and return are dropped; control
      // protocol starts fresh with hello from host.
      return RelayPipe(ws: ws, peer: peer, buffered: pending);
    } catch (e) {
      await sub.cancel();
      try {
        await ws.close();
      } catch (_) {}
      rethrow;
    }
  }
}

class RelayPeer {
  const RelayPeer({required this.id, required this.name, required this.role});
  final String id;
  final String name;
  final String role;
}

/// Bridged WebSocket after relay handshake. Opaque forward; use as control pipe.
class RelayPipe {
  RelayPipe({required this.ws, required this.peer, this.buffered = const []});
  final WebSocket ws;
  final RelayPeer peer;
  final List<String> buffered;

  Future<void> close() async {
    try {
      await ws.close(WebSocketStatus.goingAway);
    } catch (_) {}
  }
}
