import 'package:vouch_api/api.dart';

/// What the person chose on the request screen.
enum Decision {
  once,
  always,
  deny;

  DecisionRequestDecisionEnum toApi() => switch (this) {
    Decision.once => DecisionRequestDecisionEnum.once,
    Decision.always => DecisionRequestDecisionEnum.always,
    Decision.deny => DecisionRequestDecisionEnum.deny,
  };

  /// The state a request is in once the server has recorded this decision.
  ApprovalRequestStateEnum toApiState() => switch (this) {
    Decision.once => ApprovalRequestStateEnum.once,
    Decision.always => ApprovalRequestStateEnum.always,
    Decision.deny => ApprovalRequestStateEnum.deny,
  };
}

/// What happened after a decision was attempted. The request screen renders
/// one final state per outcome; [cancelled] goes back to the buttons because
/// nothing was sent.
sealed class DecisionOutcome {
  const DecisionOutcome();
}

/// The server recorded this device's decision.
class Approved extends DecisionOutcome {
  const Approved(this.decision);

  /// [Decision.once] or [Decision.always].
  final Decision decision;
}

class Denied extends DecisionOutcome {
  const Denied();
}

/// 409 `already_decided`: another device (or an earlier tap) answered first.
class AnsweredElsewhere extends DecisionOutcome {
  const AnsweredElsewhere();
}

/// 409 `expired`, or the countdown ran out locally.
class Expired extends DecisionOutcome {
  const Expired();
}

/// The agent withdrew the request (`cancelled` state from the server).
class Withdrawn extends DecisionOutcome {
  const Withdrawn();
}

/// 409 `shown_mismatch`: the request changed after it was shown, so the
/// decision was refused and it stays pending. [request] is the server's
/// current version, to show again before anyone decides.
class ShownChanged extends DecisionOutcome {
  const ShownChanged(this.request);
  final ApprovalRequest request;
}

/// The fingerprint prompt was dismissed. Nothing was signed or sent.
class Cancelled extends DecisionOutcome {
  const Cancelled();
}

/// Could not reach the server, or it rejected the call. Retry is allowed.
class Failed extends DecisionOutcome {
  const Failed(this.message);

  /// Plain English, safe to show.
  final String message;
}
