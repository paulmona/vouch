import 'dart:io';

/// The pairing link in the QR code (contract v0.2.0):
/// `vouch://pair?v=1&server=<URL-encoded base URL>&token=<setup token>`.
/// The same text can be pasted by hand.
class PairLink {
  const PairLink({required this.server, required this.token});

  /// Base URL for every API call, e.g. `https://vouch.example.com`.
  final Uri server;

  /// Single-use setup token, valid 10 minutes.
  final String token;

  static final _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{16,128}$');

  /// Returns null for anything that is not a valid v1 pairing link.
  static PairLink? parse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null) return null;
    if (uri.scheme.toLowerCase() != 'vouch' || uri.host != 'pair') return null;
    final q = uri.queryParameters;
    if (q['v'] != '1') return null;
    final token = q['token'];
    final serverText = q['server'];
    if (token == null || serverText == null) return null;
    if (!_tokenPattern.hasMatch(token)) return null;
    final server = Uri.tryParse(serverText);
    if (server == null ||
        !(server.scheme == 'https' ||
            (server.scheme == 'http' && allowsPlainHttp(server.host))) ||
        server.host.isEmpty ||
        server.hasQuery ||
        server.hasFragment) {
      return null;
    }
    return PairLink(server: _stripTrailingSlash(server), token: token);
  }

  /// True for a pairing link that is otherwise fine but points at a public
  /// server over plain HTTP, so the refusal can say to use HTTPS.
  static bool isPlainHttpToPublicHost(String text) {
    final uri = Uri.tryParse(text.trim());
    final server = Uri.tryParse(uri?.queryParameters['server'] ?? '');
    return server != null &&
        server.scheme == 'http' &&
        server.host.isNotEmpty &&
        !allowsPlainHttp(server.host);
  }

  /// Shown when [isPlainHttpToPublicHost].
  static const plainHttpRefused =
      'This link uses plain HTTP to a server outside your network. '
      'Set the server up with HTTPS and create a new link.';

  /// Plain HTTP is accepted only where nobody else is on the path: this
  /// phone or the local network. Dart's sockets ignore the platforms'
  /// cleartext rules, so this is the only check there is.
  static bool allowsPlainHttp(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost') return true;
    final ip = InternetAddress.tryParse(h);
    return (ip?.isLoopback ?? false) || isLanHost(h);
  }

  /// Private IPv4, link-local, unique-local IPv6, or a `.local` name.
  static bool isLanHost(String host) {
    final h = host.toLowerCase();
    if (h.endsWith('.local')) return true;
    final ip = InternetAddress.tryParse(h);
    if (ip == null) return false;
    final b = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4) {
      return b[0] == 10 ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168) ||
          (b[0] == 169 && b[1] == 254);
    }
    return (b[0] & 0xfe) == 0xfc || (b[0] == 0xfe && (b[1] & 0xc0) == 0x80);
  }

  static Uri _stripTrailingSlash(Uri u) {
    final p = u.path;
    if (p.isEmpty || p == '/') return u.replace(path: '');
    return p.endsWith('/') ? u.replace(path: p.substring(0, p.length - 1)) : u;
  }

  /// Round trip, for the debug preview and tests.
  Uri toUri() => Uri(
    scheme: 'vouch',
    host: 'pair',
    queryParameters: {'v': '1', 'server': server.toString(), 'token': token},
  );
}
