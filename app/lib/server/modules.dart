import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/vouch_api_client.dart';
import '../pairing/device_session.dart';

/// What the app shows when it has never heard from the server: the one
/// module every server had before the switches existed.
final defaultModules = Modules(credentials: true, sms: false);

/// Which optional modules the paired server runs. Fetched on pairing,
/// app open and resume. A server older than the switches answers 404,
/// meaning credentials only; any other failure keeps the last answer so a
/// flaky network never hides a tab that is on.
final modulesProvider = FutureProvider<Modules>((ref) async {
  final api = ref.watch(transportApiProvider);
  if (api == null) return defaultModules;
  final cache = ModulesCache();
  try {
    final m = await api.server.getModules() ?? defaultModules;
    await cache.save(m);
    return m;
  } on ApiException catch (e) {
    if (e.code == 404) {
      await cache.save(defaultModules);
      return defaultModules;
    }
    debugPrint('Vouch: modules check failed (${e.code})');
  } catch (e) {
    debugPrint('Vouch: modules check failed (${e.runtimeType})');
  }
  return await cache.load() ?? defaultModules;
});

/// The last module answer, so a cold start offline shows the right tabs.
class ModulesCache {
  static const _credentials = 'modules.credentials';
  static const _sms = 'modules.sms';

  Future<void> save(Modules m) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_credentials, m.credentials);
    await prefs.setBool(_sms, m.sms);
  }

  Future<Modules?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final c = prefs.getBool(_credentials);
    final s = prefs.getBool(_sms);
    if (c == null || s == null) return null;
    return Modules(credentials: c, sms: s);
  }
}
