import 'package:vouch/api/cloudflare_access.dart';

/// Stands in for the Keychain in tests.
class MemorySecrets implements SecretBackend {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
