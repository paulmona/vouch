/// The Firebase data message the server sends (`PushData` in the contract):
/// `v: "1"`, `kind`, and one ID (none for `sms_updated`), all strings. Never an agent, site or login.
sealed class PushEvent {
  const PushEvent();

  /// Parses a data payload. Returns null for anything that is not a valid
  /// v1 push, so a stray or malformed message is ignored, never crashes.
  static PushEvent? parse(Map<Object?, Object?> data) {
    if (data['v'] != '1') return null;
    final kind = data['kind'];
    String? id(String key) {
      final v = data[key];
      return v is String && _idPattern.hasMatch(v) ? v : null;
    }

    return switch (kind) {
      'request' => switch (id('request_id')) {
        final r? => RequestPush(r),
        _ => null,
      },
      'clear' => switch (id('request_id')) {
        final r? => ClearPush(r),
        _ => null,
      },
      'heartbeat' => switch (id('heartbeat_id')) {
        final h? => HeartbeatPush(h),
        _ => null,
      },
      'alert' => switch (id('alert_id')) {
        final a? => AlertPush(a),
        _ => null,
      },
      'sms_updated' => const SmsUpdatedPush(),
      _ => null,
    };
  }

  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
}

/// A new request: notify, and open it on a tap.
class RequestPush extends PushEvent {
  const RequestPush(this.requestId);
  final String requestId;
}

/// Dismiss that request: another device answered, or it ended.
class ClearPush extends PushEvent {
  const ClearPush(this.requestId);
  final String requestId;
}

/// No visible notification; call checkIn.
class HeartbeatPush extends PushEvent {
  const HeartbeatPush(this.heartbeatId);
  final String heartbeatId;
}

/// Visible notification; details fetched with getAlert.
class AlertPush extends PushEvent {
  const AlertPush(this.alertId);
  final String alertId;
}

/// Texts changed on the server: refetch the SMS screens. Nothing is
/// shown, and no number travels through Firebase, so there is no ID.
class SmsUpdatedPush extends PushEvent {
  const SmsUpdatedPush();
}
