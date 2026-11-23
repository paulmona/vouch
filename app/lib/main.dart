import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'legal/licences.dart';
import 'platform/app_settings.dart';
import 'platform/biometry.dart';
import 'push/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge on Android; the theme keeps the system bars transparent.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

  registerLicences();

  // "fingerprint" / "Face ID" / "Touch ID" for every screen's wording.
  await Biometry.init(AppSettings().biometryName);

  // Notifications and Firebase Messaging; the app runs without Firebase.
  await PushService.instance.init();

  runApp(const ProviderScope(child: VouchApp()));
}
