import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:vouch_api/api.dart';

/// Shown wherever a request was stopped by Cloudflare Access.
const accessBlockedMessage =
    'Cloudflare Access blocked this phone. Check the service token in '
    'Settings.';

/// A Cloudflare Access service token, pasted by the owner.
class AccessToken {
  const AccessToken({required this.clientId, required this.clientSecret});

  final String clientId;
  final String clientSecret;

  Map<String, String> toJson() => {'id': clientId, 'secret': clientSecret};

  static AccessToken? fromJson(String? s) {
    if (s == null) return null;
    try {
      final m = jsonDecode(s);
      if (m is Map && m['id'] is String && m['secret'] is String) {
        return AccessToken(
          clientId: m['id'] as String,
          clientSecret: m['secret'] as String,
        );
      }
    } on FormatException {
      // Unreadable: treat as not set.
    }
    return null;
  }
}

/// Where the secret lives: the Keychain on iOS, Keystore-backed storage on
/// Android. Replaced in tests.
abstract class SecretBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureStorageBackend implements SecretBackend {
  const SecureStorageBackend();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Service tokens by server origin. A token saved before pairing (no server
/// yet: the QR code hasn't been scanned) waits in a pending slot and is tied
/// to the server when pairing starts, since the pair call must pass Access.
class CloudflareAccessStore {
  CloudflareAccessStore({this._backend = const SecureStorageBackend()});

  /// Process-wide, so every client (background isolates included) reads the
  /// same tokens. Tests replace it.
  static CloudflareAccessStore instance = CloudflareAccessStore();

  final SecretBackend _backend;
  final _cache = <String, AccessToken?>{};

  static const _pending = 'pending';

  /// `https://host:port`, or the pending slot for null.
  static String _slot(Uri? server) => server == null
      ? _pending
      : '${server.scheme}://${server.host}:${server.port}';

  static String _key(String slot) => 'cf_access:$slot';

  Future<AccessToken?> read(Uri? server) async {
    final slot = _slot(server);
    if (_cache.containsKey(slot)) return _cache[slot];
    final t = AccessToken.fromJson(await _backend.read(_key(slot)));
    return _cache[slot] = t;
  }

  Future<void> save(Uri? server, AccessToken token) async {
    final slot = _slot(server);
    await _backend.write(_key(slot), jsonEncode(token.toJson()));
    _cache[slot] = token;
  }

  Future<void> remove(Uri? server) async {
    final slot = _slot(server);
    await _backend.delete(_key(slot));
    _cache[slot] = null;
  }

  /// Ties a token saved before pairing to [server]. A token already saved
  /// for that server stays unless one is pending.
  Future<void> bindPending(Uri server) async {
    // Never sent over plain HTTP, so it waits for an HTTPS server.
    if (server.scheme != 'https') return;
    final t = await read(null);
    if (t == null) return;
    await save(server, t);
    await remove(null);
  }
}

/// Stopped by Cloudflare Access: its login page (HTML) or a redirect to it
/// came back instead of the API's JSON.
class AccessBlockedException extends http.ClientException {
  AccessBlockedException(Uri url) : super(accessBlockedMessage, url);
}

/// True when [e], or the error the generated client wrapped, is an
/// Access block.
bool isAccessBlocked(Object? e) =>
    e is AccessBlockedException ||
    (e is ApiException && e.innerException is AccessBlockedException);

/// Adds the service-token headers to requests for [server]'s origin, and
/// only those, and turns an Access block into [AccessBlockedException].
///
/// Sits under the signing client: the signature covers method, path and
/// body, not these headers, so signing is unchanged.
class CloudflareAccessClient extends http.BaseClient {
  CloudflareAccessClient({
    required this.inner,
    required this.server,
    CloudflareAccessStore? store,
  }) : _store = store ?? CloudflareAccessStore.instance;

  final http.Client inner;
  final Uri server;
  final CloudflareAccessStore _store;

  static const headerId = 'CF-Access-Client-Id';
  static const headerSecret = 'CF-Access-Client-Secret';

  /// The secret only ever goes out over HTTPS.
  bool _sameOrigin(Uri u) =>
      u.scheme == 'https' &&
      u.scheme == server.scheme &&
      u.host == server.host &&
      u.port == server.port;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Never follow a redirect: one to another host would carry the secret
    // there, and the API itself never redirects.
    request.followRedirects = false;
    if (_sameOrigin(request.url)) {
      final t = await _store.read(server);
      if (t != null) {
        request.headers[headerId] = t.clientId;
        request.headers[headerSecret] = t.clientSecret;
      }
    }
    final r = await inner.send(request);
    if (_blocked(r)) {
      await r.stream.drain<void>();
      throw AccessBlockedException(request.url);
    }
    return r;
  }

  static bool _blocked(http.StreamedResponse r) {
    final type = r.headers['content-type'] ?? '';
    if (type.contains('text/html')) return true;
    if (r.statusCode >= 300 && r.statusCode < 400) {
      final host = Uri.tryParse(r.headers['location'] ?? '')?.host ?? '';
      return host == 'cloudflareaccess.com' ||
          host.endsWith('.cloudflareaccess.com');
    }
    return false;
  }

  @override
  void close() => inner.close();
}
