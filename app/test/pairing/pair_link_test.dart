import 'package:flutter_test/flutter_test.dart';
import 'package:vouch/pairing/pair_link.dart';

void main() {
  const token = 'TEST-SETUP-TOKEN-0000000000000000000000000';

  test('parses the contract link', () {
    final l = PairLink.parse(
      'vouch://pair?v=1&server=https%3A%2F%2Fvouch.example.com&token=$token',
    );
    expect(l, isNotNull);
    expect(l!.server.toString(), 'https://vouch.example.com');
    expect(l.token, token);
  });

  test('accepts http for dev servers and strips a trailing slash', () {
    final l = PairLink.parse(
      'vouch://pair?v=1&server=http%3A%2F%2F10.0.2.2%3A8770%2F&token=$token',
    );
    expect(l!.server.toString(), 'http://10.0.2.2:8770');
  });

  group('plain HTTP', () {
    String linkTo(String server) =>
        'vouch://pair?v=1&server=${Uri.encodeComponent(server)}&token=$token';

    test('accepted for this phone and the local network', () {
      for (final server in [
        'http://192.168.1.20:8771',
        'http://10.0.2.2:8770',
        'http://172.16.0.5',
        'http://169.254.10.1',
        'http://vouch.local:8771',
        'http://127.0.0.1:8770',
        'http://localhost:8770',
        'http://[::1]:8770',
        'http://[fd00::5]:8770',
      ]) {
        expect(PairLink.parse(linkTo(server)), isNotNull, reason: server);
        expect(PairLink.isPlainHttpToPublicHost(linkTo(server)), isFalse);
      }
    });

    test('refused for a public server, with a reason', () {
      for (final server in [
        'http://vouch.example.com',
        'http://203.0.113.7:8771',
        'http://172.32.0.1',
        'http://[2001:db8::1]:8771',
      ]) {
        expect(PairLink.parse(linkTo(server)), isNull, reason: server);
        expect(
          PairLink.isPlainHttpToPublicHost(linkTo(server)),
          isTrue,
          reason: server,
        );
      }
    });

    test('https is unchanged, public or not', () {
      for (final server in [
        'https://vouch.example.com',
        'https://192.168.1.20:8771',
      ]) {
        expect(PairLink.parse(linkTo(server)), isNotNull, reason: server);
        expect(PairLink.isPlainHttpToPublicHost(linkTo(server)), isFalse);
      }
    });
  });

  test('tolerates surrounding whitespace and a path on the server', () {
    final l = PairLink.parse(
      '  vouch://pair?v=1&server=https%3A%2F%2Fh.example%2Fvouch%2F&token=$token \n',
    );
    expect(l!.server.toString(), 'https://h.example/vouch');
  });

  test('rejects other versions, schemes, hosts, tokens and servers', () {
    for (final bad in [
      'vouch://pair?v=2&server=https%3A%2F%2Fh.example&token=$token',
      'https://pair?v=1&server=https%3A%2F%2Fh.example&token=$token',
      'vouch://other?v=1&server=https%3A%2F%2Fh.example&token=$token',
      'vouch://pair?v=1&server=https%3A%2F%2Fh.example',
      'vouch://pair?v=1&token=$token',
      'vouch://pair?v=1&server=https%3A%2F%2Fh.example&token=short',
      'vouch://pair?v=1&server=https%3A%2F%2Fh.example&token=has%20space%20in%20it%20here',
      'vouch://pair?v=1&server=ftp%3A%2F%2Fh.example&token=$token',
      'vouch://pair?v=1&server=https%3A%2F%2Fh.example%3Fx%3D1&token=$token',
      'not a link',
      '',
    ]) {
      expect(PairLink.parse(bad), isNull, reason: bad);
    }
  });

  test('round trips through toUri', () {
    final l = PairLink.parse(
      'vouch://pair?v=1&server=https%3A%2F%2Fvouch.example.com&token=$token',
    )!;
    expect(PairLink.parse(l.toUri().toString())!.token, token);
  });
}
