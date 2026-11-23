import 'package:flutter/material.dart';
import 'package:vouch_api/api.dart';

import '../model/decision.dart';
import '../screens/request/request_screen.dart';
import 'sample_requests.dart';

/// Debug builds only: opens the request screen in each of its states on fake
/// data, so the design can be checked on a device before the server exists.
class RequestPreviewScreen extends StatelessWidget {
  const RequestPreviewScreen({super.key});

  static final scenarios = <_Scenario>[
    _Scenario(
      'Pending sign-in',
      'Scout, shop.example.com, 4:32 left',
      () => SampleRequests.signIn(),
      FakeDecider(),
    ),
    _Scenario(
      'Pending, no login title',
      'login_title is null',
      () => SampleRequests.signIn(loginTitle: null),
      FakeDecider(),
    ),
    _Scenario(
      'Pending SMS contact',
      'sms_contact kind: name, number, reason; no Always allow',
      () => SampleRequests.smsContact(),
      FakeDecider(),
    ),
    _Scenario(
      'Expiring in 20 s',
      'urgent colour, then expires on its own',
      () => SampleRequests.signIn(remaining: const Duration(seconds: 20)),
      FakeDecider(),
    ),
    _Scenario('Long names', 'overflow check', () {
      final r = SampleRequests.signIn(
        loginTitle: 'Example staff portal: admin (secondary, read-only)',
      );
      return ApprovalRequest(
        requestId: r.requestId,
        kind: r.kind,
        agent: 'Scout the Second of Example Labs',
        site: 'portal.northernlights.healthcare-services.example.com',
        loginTitle: r.loginTitle,
        createdAt: r.createdAt,
        expiresAt: r.expiresAt,
        state: r.state,
      );
    }, FakeDecider()),
    _Scenario(
      'Fingerprint cancelled',
      'buttons come back, nothing sent',
      () => SampleRequests.signIn(),
      FakeDecider(fixed: const Cancelled()),
    ),
    _Scenario(
      'Answered on another device',
      '409 already_decided',
      () => SampleRequests.signIn(),
      FakeDecider(fixed: const AnsweredElsewhere()),
    ),
    _Scenario(
      'Expired on the server',
      '409 expired',
      () => SampleRequests.signIn(),
      FakeDecider(fixed: const Expired()),
    ),
    _Scenario(
      'Send fails',
      'network error, Try again',
      () => SampleRequests.signIn(),
      FakeDecider(
        fixed: const Failed(
          "Vouch couldn't reach your server. Check your connection and try again.",
        ),
      ),
    ),
    _Scenario(
      'Opened after: approved once',
      'fetched in a final state',
      () => SampleRequests.signIn(
        state: ApprovalRequestStateEnum.once,
        decidedBy: ApprovalRequestDecidedByEnum.thisDevice,
      ),
      FakeDecider(),
    ),
    _Scenario(
      'Opened after: always, other device',
      'fetched in a final state',
      () => SampleRequests.signIn(
        state: ApprovalRequestStateEnum.always,
        decidedBy: ApprovalRequestDecidedByEnum.otherDevice,
      ),
      FakeDecider(),
    ),
    _Scenario(
      'Opened after: timed out',
      'fetched in a final state',
      () => SampleRequests.signIn(state: ApprovalRequestStateEnum.timeout),
      FakeDecider(),
    ),
    _Scenario(
      'Opened after: withdrawn',
      'fetched in a final state',
      () => SampleRequests.signIn(state: ApprovalRequestStateEnum.cancelled),
      FakeDecider(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Preview request screen')),
      body: SafeArea(
        child: ListView.separated(
          itemCount: scenarios.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, i) {
            final s = scenarios[i];
            return ListTile(
              title: Text(s.title),
              subtitle: Text(s.subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // Build the fake once per tap, so a theme change or rebuild
                // does not reset its expiry (a real request's is fixed).
                final request = s.request();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RequestScreen(
                      request: request,
                      onDecide: s.decider.call,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Scenario {
  _Scenario(this.title, this.subtitle, this.request, this.decider);

  final String title;
  final String subtitle;
  final ApprovalRequest Function() request;
  final FakeDecider decider;
}
