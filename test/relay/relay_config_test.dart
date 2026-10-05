import 'package:aktifdesk/core/relay/relay_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('baked relay URL integrity passes', () {
    expect(RelayConfig.isIntegrityOk, isTrue);
    expect(RelayConfig.integrityError(), isNull);
    expect(RelayConfig.url, contains('aktifdesk-relay'));
    expect(RelayConfig.url.startsWith('wss://'), isTrue);
  });

  test('tampered host fails closed', () {
    final err = RelayConfig.integrityError('wss://evil.example/aktifdesk-relay');
    expect(err, isNotNull);
  });

  test('cleartext public ws fails closed', () {
    final err = RelayConfig.integrityError(
      'ws://aktifdesk-relay-production.up.railway.app/aktifdesk-relay',
    );
    expect(err, isNotNull);
  });
}
