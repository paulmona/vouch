import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';

/// `vouch://pair?...` links handed over by Android (a tapped link, or an
/// `am start -a VIEW -d` on a dev box). The text only; parsing and the
/// decision to pair stay in Dart, and the pair screen asks first.
class PairLinkChannel {
  PairLinkChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const channelName = 'ai.viewbridge.vouch/pair_link';

  final MethodChannel _channel;
  final _links = StreamController<String>.broadcast();

  /// The link the app was started with, read once; null otherwise, and on
  /// platforms without the channel.
  Future<String?> initialLink() async {
    try {
      return await _channel.invokeMethod<String>('initialLink');
    } on MissingPluginException {
      return null;
    }
  }

  /// Links that arrive while the app is running.
  Stream<String> get links => _links.stream;

  Future<Object?> _onCall(MethodCall call) async {
    debugPrint('Vouch: pair link call ${call.method}');
    if (call.method == 'link' && call.arguments is String) {
      _links.add(call.arguments as String);
    }
    return null;
  }

  void dispose() {
    _links.close();
  }
}
