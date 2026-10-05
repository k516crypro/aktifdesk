import 'dart:io';

import 'package:aktifdesk/core/control/android_remote_host_agent.dart';
import 'package:aktifdesk/core/control/control_protocol.dart';
import 'package:aktifdesk/core/control/discovery.dart';
import 'package:aktifdesk/core/control/pc_link.dart';
import 'package:aktifdesk/core/control/phone_control_server.dart';
import 'package:aktifdesk/core/control/remote_client_session.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> until(bool Function() cond) async {
  for (var i = 0; i < 300 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(cond(), isTrue);
}

void main() {
  late PhoneControlServer host;
  late FakeRemoteHostAgent agent;
  late PcDiscovery discovery;
  final sessions = <RemoteClientSession>[];

  setUp(() async {
    agent = FakeRemoteHostAgent(deviceName: 'Host Telefon');
    host = PhoneControlServer(
      deviceId: 'host-phone',
      deviceName: 'Host Telefon',
      port: 0,
      address: InternetAddress.loopbackIPv4,
      discoveryPort: 0,
      beaconTargets: const [],
      initialCode: '654321',
      mode: ControlProtocol.modeRemoteHost,
      remoteHandler: agent,
    );
    await host.start();
    discovery = PcDiscovery(
      port: host.advertiser!.boundPort!,
      targets: [InternetAddress.loopbackIPv4],
      listenForBeacons: false,
      queryInterval: const Duration(milliseconds: 100),
    );
  });

  tearDown(() async {
    for (final s in sessions) {
      await s.close();
    }
    sessions.clear();
    await host.close();
  });

  test('phone-host advertises remote-host mode and accepts controller by code', () async {
    final r = await pairWithCode(
      code: '654321',
      pc: const PcIdentity(id: 'ctrl-1', name: 'Kumanda'),
      discovery: discovery,
      searchTimeout: const Duration(seconds: 3),
    );
    expect(r.isRemoteHost, isTrue);
    expect(r.mode, ControlProtocol.modeRemoteHost);

    final session = RemoteClientSession();
    sessions.add(session);
    // ignore: unawaited_futures
    session.attach(r.socket, peer: r.address);
    await until(() => host.connection == ControlConnection.connected);

    final st = await session.ping();
    expect(st?.deviceName, 'Host Telefon');
    expect(st?.keepAwake, isFalse);

    await session.setKeepAwake(true);
    expect(agent.keepAwake, isTrue);

    await session.requestUnlock();
    expect(agent.unlockCalls, 1);

    await session.launch(url: 'https://example.com');
    expect(agent.launches.single, 'null|https://example.com');

    final share = await session.screenShare(enable: true);
    expect(share['ok'], isFalse);
    expect(share['reason'], 'screen_share_not_implemented');

    final tap = await session.tap(x: 0.5, y: 0.5);
    expect(tap['ok'], isTrue);
    expect(agent.gestures, contains('tap:0.5,0.5'));

    await session.swipe(x1: 0.2, y1: 0.2, x2: 0.8, y2: 0.8);
    expect(agent.gestures.any((g) => g.startsWith('swipe:')), isTrue);

    await session.key('back');
    expect(agent.gestures, contains('key:back'));
  });

  test('pc-client mode still rejects host.* without handler meaning', () async {
    await host.close();
    host = PhoneControlServer(
      deviceId: 'pc-mode-phone',
      deviceName: 'PC Client Phone',
      port: 0,
      address: InternetAddress.loopbackIPv4,
      discoveryPort: 0,
      beaconTargets: const [],
      initialCode: '111222',
      mode: ControlProtocol.modePcClient,
    );
    await host.start();
    discovery = PcDiscovery(
      port: host.advertiser!.boundPort!,
      targets: [InternetAddress.loopbackIPv4],
      listenForBeacons: false,
      queryInterval: const Duration(milliseconds: 100),
    );
    final r = await pairWithCode(
      code: '111222',
      pc: const PcIdentity(id: 'ctrl-2', name: 'PC'),
      discovery: discovery,
      searchTimeout: const Duration(seconds: 3),
    );
    expect(r.isRemoteHost, isFalse);
    final session = RemoteClientSession();
    sessions.add(session);
    // ignore: unawaited_futures
    session.attach(r.socket, peer: r.address);
    await until(() => host.connection == ControlConnection.connected);
    expect(() => session.ping(), throwsA(isA<Exception>()));
  });
}
