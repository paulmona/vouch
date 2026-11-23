import 'package:http/http.dart' as http;
import 'package:vouch_api/api.dart';

import 'cloudflare_access.dart';
import 'device_signer.dart';
import 'signing_client.dart';

export 'package:vouch_api/api.dart';

/// The generated client wired to a signing transport, with the Cloudflare
/// Access service token added when one is set.
///
/// `serverUrl` is the base URL from the pairing QR code, e.g.
/// `https://vouch.example.com`. All spec paths start with `/v1/...`.
class VouchApi {
  VouchApi({
    required Uri serverUrl,
    required DeviceSigner signer,
    String? deviceId,
    http.Client? inner,
    CloudflareAccessStore? accessStore,
  }) : _client = ApiClient(basePath: _basePath(serverUrl)) {
    _client.client = SigningClient(
      signer: signer,
      inner: CloudflareAccessClient(
        inner: inner ?? http.Client(),
        server: serverUrl,
        store: accessStore,
      ),
      deviceId: deviceId,
    );
  }

  final ApiClient _client;

  late final DevicesApi devices = DevicesApi(_client);
  late final RequestsApi requests = RequestsApi(_client);
  late final AlertsApi alerts = AlertsApi(_client);
  late final ServerApi server = ServerApi(_client);
  late final SmsApi sms = SmsApi(_client);

  void close() => _client.client.close();

  /// No trailing slash: the generated client concatenates `basePath + path`.
  static String _basePath(Uri serverUrl) {
    final s = serverUrl.toString();
    return s.endsWith('/') ? s.substring(0, s.length - 1) : s;
  }
}
