import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'canonical.dart';
import 'device_signer.dart';

/// What to add to the phone's clock to get the server's, learned from a
/// `clock_skew` reply (the server allows ±60 s). One per process: every
/// client to the paired server shares it, so a corrected offset carries over
/// to the next request instead of costing another 401.
class ServerClock {
  ServerClock();

  static final shared = ServerClock();

  Duration offset = Duration.zero;

  DateTime now(DateTime local) => local.add(offset);
}

/// An [http.Client] that signs every request per the contract and adds the
/// `X-Vouch-*` headers. Wraps whatever client the generated API uses, so the
/// generated code stays untouched.
///
/// [deviceId] is null only while pairing: the pair call is signed with the
/// key being registered and carries no `X-Vouch-Device` header.
///
/// On a `401 clock_skew` it takes `server_time` from the error, records the
/// offset in [serverClock], re-signs with a fresh nonce and the corrected
/// timestamp, and retries once. The retry's reply is returned as is.
class SigningClient extends http.BaseClient {
  SigningClient({
    required this.signer,
    required this.inner,
    this.deviceId,
    DateTime Function()? clock,
    String Function()? nonceSource,
    ServerClock? serverClock,
  }) : _clock = clock ?? DateTime.now,
       _nonce = nonceSource ?? Canonical.nonce,
       serverClock = serverClock ?? ServerClock.shared;

  final DeviceSigner signer;
  final http.Client inner;

  /// Null only while pairing.
  final String? deviceId;
  final ServerClock serverClock;
  final DateTime Function() _clock;
  final String Function() _nonce;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await _bodyBytes(request);
    final first = await _sendSigned(request, body);
    if (first.statusCode != 401) return first;

    // Read the body once: either it is a clock_skew we can fix, or it is
    // handed back unchanged to the generated client.
    final bytes = await first.stream.toBytes();
    final serverTime = _clockSkewServerTime(bytes);
    if (serverTime == null) {
      return http.StreamedResponse(
        http.ByteStream.fromBytes(bytes),
        first.statusCode,
        contentLength: bytes.length,
        request: first.request,
        headers: first.headers,
        isRedirect: first.isRedirect,
        persistentConnection: first.persistentConnection,
        reasonPhrase: first.reasonPhrase,
      );
    }
    serverClock.offset = serverTime.difference(_clock());
    return _sendSigned(request, body);
  }

  Future<http.StreamedResponse> _sendSigned(
    http.BaseRequest request,
    Uint8List body,
  ) async {
    final timestamp = Canonical.timestamp(serverClock.now(_clock()));
    final nonce = _nonce();
    final canonical = Canonical.string(
      method: request.method,
      target: Canonical.target(request.url),
      bodySha256: Canonical.bodySha256Hex(body),
      timestamp: timestamp,
      nonce: nonce,
    );
    final signature = await signer.signDer(
      Uint8List.fromList(canonical.codeUnits),
    );

    // Signing needs the final bytes, and a request can only be sent once, so
    // rebuild it as a plain Request with the same bytes plus our headers.
    final signed = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = body
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection;
    signed.headers[Canonical.headerTimestamp] = timestamp;
    signed.headers[Canonical.headerNonce] = nonce;
    signed.headers[Canonical.headerSignature] = Canonical.base64UrlNoPad(
      signature,
    );
    if (deviceId != null) {
      signed.headers[Canonical.headerDevice] = deviceId!;
    } else {
      signed.headers.remove(Canonical.headerDevice);
    }
    return inner.send(signed);
  }

  /// `server_time` from a `clock_skew` error body, else null.
  static DateTime? _clockSkewServerTime(Uint8List bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map || json['code'] != 'clock_skew') return null;
      final t = json['server_time'];
      return t is String ? DateTime.tryParse(t) : null;
    } on FormatException {
      return null;
    }
  }

  @override
  void close() => inner.close();

  static Future<Uint8List> _bodyBytes(http.BaseRequest request) async {
    if (request is http.Request) {
      return request.bodyBytes;
    }
    // Multipart or streamed: read it all so we can hash it.
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request.finalize()) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
