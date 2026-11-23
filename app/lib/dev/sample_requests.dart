import 'package:vouch_api/api.dart';

import '../model/decision.dart';

/// Fake requests and a fake decider, for the debug preview and tests. Nothing
/// here talks to a server.
abstract final class SampleRequests {
  static ApprovalRequest signIn({
    DateTime? now,
    Duration remaining = const Duration(minutes: 4, seconds: 32),
    String? loginTitle = 'Example',
    ApprovalRequestStateEnum state = ApprovalRequestStateEnum.pending,
    ApprovalRequestDecidedByEnum? decidedBy,
  }) {
    final t = now ?? DateTime.now();
    final expiresAt = t.add(remaining);
    return ApprovalRequest(
      requestId: '3f9c2a7b1d4e8f60',
      kind: ApprovalRequestKindEnum.signIn,
      agent: 'Scout',
      site: 'shop.example.com',
      loginTitle: loginTitle,
      createdAt: expiresAt.subtract(const Duration(minutes: 5)),
      expiresAt: expiresAt,
      state: state,
      decidedAt: state == ApprovalRequestStateEnum.pending ? null : t,
      decidedBy: decidedBy,
    );
  }

  /// An agent asking to text someone new.
  static ApprovalRequest smsContact({DateTime? now}) {
    final t = now ?? DateTime.now();
    final expiresAt = t.add(const Duration(minutes: 4, seconds: 40));
    return ApprovalRequest(
      requestId: 'b7c8d9e0f1a2b3c4',
      kind: ApprovalRequestKindEnum.smsContact,
      agent: 'Ava',
      site: '+12045550150',
      loginTitle: null,
      smsContact: ApprovalRequestSmsContact(
        phone: '+12045550150',
        name: 'Sam',
        reason: "The owner asked me to confirm Tuesday's dinner with Sam.",
      ),
      createdAt: expiresAt.subtract(const Duration(minutes: 5)),
      expiresAt: expiresAt,
      state: ApprovalRequestStateEnum.pending,
    );
  }
}

/// A decider that waits a moment and returns a fixed outcome, or the natural
/// outcome for the decision when [fixed] is null.
class FakeDecider {
  FakeDecider({this.fixed, this.delay = const Duration(milliseconds: 700)});

  final DecisionOutcome? fixed;
  final Duration delay;
  final decisions = <Decision>[];

  Future<DecisionOutcome> call(Decision decision) async {
    decisions.add(decision);
    await Future<void>.delayed(delay);
    return fixed ??
        switch (decision) {
          Decision.deny => const Denied(),
          _ => Approved(decision),
        };
  }
}
