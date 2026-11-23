import 'dart:async';

import 'package:vouch/api/cloudflare_access.dart';

import 'helpers/memory_secrets.dart';

/// No Keychain under `flutter test`: every test gets an empty in-memory
/// token store.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  CloudflareAccessStore.instance = CloudflareAccessStore(
    backend: MemorySecrets(),
  );
  await testMain();
}
