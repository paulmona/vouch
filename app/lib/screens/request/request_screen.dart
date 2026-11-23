import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vouch_api/api.dart';

import '../../model/decision.dart';
import '../../requests/request_kind.dart';
import '../../sms/phone_format.dart';
import '../../text/shown_text.dart';
import '../../widgets/vouch_mark.dart';
import 'countdown.dart';

/// Called when the person taps a button. Runs the fingerprint prompt, signs
/// and posts the decision, and reports what happened. A [Cancelled]
/// outcome means nothing was sent and the buttons come back.
typedef DecideCallback = Future<DecisionOutcome> Function(Decision decision);

/// The product: a request screen that says exactly what is being asked.
///
/// Layout is built for one-handed use on a large phone: the words at the top,
/// the three buttons in the thumb zone at the bottom, and the middle scrolls
/// so 200% text never pushes a button off screen.
class RequestScreen extends StatefulWidget {
  const RequestScreen({
    super.key,
    required this.request,
    required this.onDecide,
    this.onFinished,
    this.now,
  });

  final ApprovalRequest request;
  final DecideCallback onDecide;

  /// Called once the person's own decision has gone through (Approved or
  /// Denied). The caller then leaves this screen: nobody needs a page
  /// saying what they just pressed and gave a fingerprint for.
  /// Failed, Cancelled and the server's own outcomes still show here.
  final void Function(DecisionOutcome outcome)? onFinished;

  /// Clock for the countdown; tests inject one.
  final DateTime Function()? now;

  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

sealed class _Phase {
  const _Phase();
}

class _Deciding extends _Phase {
  const _Deciding();
}

class _Submitting extends _Phase {
  const _Submitting(this.decision);
  final Decision decision;
}

class _Finished extends _Phase {
  const _Finished(this.outcome);
  final DecisionOutcome outcome;
}

class _RequestScreenState extends State<RequestScreen> {
  late _Phase _phase;
  Timer? _ticker;

  /// Set after the server refused a decision because the request changed
  /// since it was shown; the caller then hands in the new version.
  bool _changed = false;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _phase = _initialPhase();
    if (_phase is _Deciding) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      _tick();
    }
  }

  /// The request ended elsewhere while it was on screen: show how, unless
  /// a decision from this phone is already on its way.
  @override
  void didUpdateWidget(RequestScreen old) {
    super.didUpdateWidget(old);
    if (_phase is _Deciding &&
        widget.request.state != ApprovalRequestStateEnum.pending) {
      _ticker?.cancel();
      _phase = _initialPhase();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// A request fetched after it ended opens straight on its final state.
  _Phase _initialPhase() {
    final r = widget.request;
    return switch (r.state) {
      ApprovalRequestStateEnum.pending => const _Deciding(),
      ApprovalRequestStateEnum.once || ApprovalRequestStateEnum.always =>
        r.decidedBy == ApprovalRequestDecidedByEnum.thisDevice
            ? _Finished(
                Approved(
                  r.state == ApprovalRequestStateEnum.always
                      ? Decision.always
                      : Decision.once,
                ),
              )
            : const _Finished(AnsweredElsewhere()),
      ApprovalRequestStateEnum.deny =>
        r.decidedBy == ApprovalRequestDecidedByEnum.thisDevice
            ? const _Finished(Denied())
            : const _Finished(AnsweredElsewhere()),
      ApprovalRequestStateEnum.timeout => const _Finished(Expired()),
      ApprovalRequestStateEnum.cancelled => const _Finished(Withdrawn()),
    };
  }

  void _tick() {
    if (!mounted) return;
    if (_phase is _Deciding && !_now.isBefore(widget.request.expiresAt)) {
      _ticker?.cancel();
      setState(() => _phase = const _Finished(Expired()));
    } else {
      setState(() {});
    }
  }

  Future<void> _decide(Decision decision) async {
    setState(() => _phase = _Submitting(decision));
    DecisionOutcome outcome;
    try {
      outcome = await widget.onDecide(decision);
    } on Object catch (e) {
      // Whatever went wrong, the spinner must not stay on for good
      //. The retry screen lets the person try again; a request
      // the server already settled then comes back as answered.
      debugPrint('Vouch: decide threw (${e.runtimeType})');
      outcome = const Failed(
        'Something went wrong while sending the decision. Try again.',
      );
    }
    if (!mounted) return;
    final again = outcome is Cancelled || outcome is ShownChanged;
    setState(() {
      _phase = again ? const _Deciding() : _Finished(outcome);
      if (outcome is ShownChanged) _changed = true;
    });
    if (!again) _ticker?.cancel();
    if (outcome is Approved || outcome is Denied) {
      widget.onFinished?.call(outcome);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = _phase;
    return Scaffold(
      body: SafeArea(
        child: switch (phase) {
          _Deciding() => _RequestBody(
            request: widget.request,
            now: _now,
            submitting: null,
            onDecide: _decide,
            notice: _changed ? 'This request changed. Review it again.' : null,
          ),
          _Submitting(:final decision) => _RequestBody(
            request: widget.request,
            now: _now,
            submitting: decision,
            onDecide: null,
          ),
          _Finished(:final outcome) => _OutcomeBody(
            request: widget.request,
            outcome: outcome,
            onRetry: outcome is Failed
                ? () => setState(() => _phase = const _Deciding())
                : null,
          ),
        },
      ),
    );
  }
}

/// The pending request: words, countdown, buttons.
class _RequestBody extends StatelessWidget {
  const _RequestBody({
    required this.request,
    required this.now,
    required this.submitting,
    required this.onDecide,
    this.notice,
  });

  final ApprovalRequest request;
  final DateTime now;

  /// Shown above the request when it changed under the person.
  final String? notice;

  /// Which button is in flight, if any. Disables all three.
  final Decision? submitting;
  final ValueChanged<Decision>? onDecide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) =>
          _column(context, theme, scheme, constraints.maxHeight),
    );
  }

  Widget _column(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    double height,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _Scrolled(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const VouchMark(size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Approval request',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                if (notice case final n?) ...[
                  const SizedBox(height: 16),
                  Text(
                    n,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                Semantics(header: true, child: _Headline(request: request)),
                if (request.shownLoginTitle case final title?) ...[
                  const SizedBox(height: 20),
                  _Detail(label: 'Login', value: title),
                ],
                if (request.smsContact case final c?
                    when request.isSmsContact) ...[
                  const SizedBox(height: 20),
                  // The agent's own words, shown as written (contract) but
                  // styled as a quote, so they never read as Vouch's.
                  _Quote(
                    label: 'Reason given by ${request.shownAgent}',
                    text: ShownText.oneLine(c.reason),
                  ),
                ],
                const SizedBox(height: 32),
                Countdown(
                  createdAt: request.createdAt,
                  expiresAt: request.expiresAt,
                  now: now,
                ),
              ],
            ),
          ),
        ),
        // Outside the scroll area, so no agent name or text size can push
        // where the request applies out of view while the buttons are live.
        // Capped at three quarters of the height. Deny is pinned at the
        // bottom and never scrolls; the site and the approve buttons above
        // it scroll when they do not fit, with a visible scrollbar.
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: _Scrolled(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Target(request: request, height: height),
                      _ButtonBar(
                        showAlways: request.canAlways,
                        approveLabel: request.isSmsContact
                            ? 'Approve'
                            : 'Approve once',
                        submitting: submitting,
                        onDecide: onDecide,
                      ),
                    ],
                  ),
                ),
              ),
              _DenyButton(submitting: submitting, onDecide: onDecide),
            ],
          ),
        ),
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.request});

  final ApprovalRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = theme.textTheme.headlineMedium!.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
    final strong = base.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w700,
    );
    final site = base.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w700,
    );

    // The agent picks its own name: two lines at most, so it cannot fill
    // the screen.
    final agent = Text(
      request.shownAgent,
      style: strong,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    final rest = request.isSmsContact
        ? Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'would like approval to text ', style: base),
                TextSpan(text: request.shownNumber, style: site),
              ],
            ),
            style: base,
          )
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'would like approval to sign in to ',
                  style: base,
                ),
                TextSpan(text: request.shownSite, style: site),
              ],
            ),
            style: base,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [agent, rest],
    );
  }
}

/// Where approving applies (the site, or who gets texted), labelled, in the
/// fixed part of the screen right above the buttons.
class _Target extends StatelessWidget {
  const _Target({required this.request, required this.height});

  final ApprovalRequest request;

  /// The height the whole request screen has.
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.titleLarge?.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w700,
    );
    final lineHeight = MediaQuery.textScalerOf(
      context,
    ).scale((style?.fontSize ?? 22) * (style?.height ?? 1.3));
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              request.isSmsContact ? 'Text to' : 'Site',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            // For a text, the number: it is what approving permits. The
            // name the agent chose follows, one line at most.
            _TailText(
              request.isSmsContact ? request.shownNumber : request.shownSite,
              // A number fits in two lines at any normal size; four leaves
              // room for marked hidden characters before anything is cut.
              // Never more than about half the screen's height, so a short
              // landscape screen keeps room for the label and buttons.
              maxLines: math.min(
                request.isSmsContact ? 4 : 3,
                math.max(1, (height * 0.55) ~/ lineHeight),
              ),
              labels: !request.isSmsContact,
              style: style,
            ),
            // Labelled as the agent's, like the reason: a name such as
            // "+1 (416) 555-0199" must not read as a second number.
            if (request.isSmsContact)
              if (request.shownContactName case final name?) ...[
                const SizedBox(height: 8),
                Text(
                  'Name given by ${request.shownAgent}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

/// [text] in at most [maxLines] lines. When it does not fit, the start
/// gives way to an ellipsis and the end stays: the end of a host is its real
/// domain, and a lookalike puts a familiar name at the start. Screen readers
/// get it whole.
///
/// With [labels] (a host) the kept end always starts on a whole label, just
/// after a dot, so a cut can never turn "evilyourbank.com" into
/// "…yourbank.com". If even the last two labels do not fit, they are shown
/// whole on as many lines as they need.
class _TailText extends StatelessWidget {
  const _TailText(
    this.text, {
    required this.maxLines,
    required this.labels,
    this.style,
  });

  final String text;
  final int maxLines;
  final bool labels;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        bool fits(String s) {
          final painter = TextPainter(
            text: TextSpan(text: s, style: effective),
            textDirection: direction,
            textScaler: scaler,
            maxLines: maxLines,
          )..layout(maxWidth: constraints.maxWidth);
          final ok = !painter.didExceedMaxLines;
          painter.dispose();
          return ok;
        }

        final (shown, lines) = fits(text)
            ? (text, maxLines)
            : labels
            ? _labelTail(fits)
            : (_charTail(fits), maxLines);
        return Text(shown, maxLines: lines, style: style, semanticsLabel: text);
      },
    );
  }

  /// The longest tail that fits and starts on a label, never shorter than
  /// the last two labels.
  (String, int?) _labelTail(bool Function(String) fits) {
    final starts = [
      for (var i = 1; i < text.length; i++)
        if (text[i - 1] == '.') i,
    ];
    final lastTwo = starts.length >= 2 ? starts[starts.length - 2] : 0;
    for (final i in starts) {
      if (i > lastTwo) break;
      final tail = '\u2026${text.substring(i)}';
      if (fits(tail)) return (tail, maxLines);
    }
    return (lastTwo == 0 ? text : '\u2026${text.substring(lastTwo)}', null);
  }

  /// The longest tail that fits, cut anywhere.
  String _charTail(bool Function(String) fits) {
    final chars = text.characters;
    String tail(int n) => '\u2026${chars.skip(chars.length - n)}';
    var lo = 0;
    var hi = chars.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (fits(tail(mid))) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return tail(lo);
  }
}

/// Text someone else wrote, shown as a quote: regular weight, italic,
/// behind a rule.
class _Quote extends StatelessWidget {
  const _Quote({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: scheme.outlineVariant, width: 3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              '\u201C$text\u201D',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontStyle: FontStyle.italic,
                color: scheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleLarge),
      ],
    );
  }
}

/// Approve once (filled), Always allow (tonal), Deny (outlined, error tone).
/// All full width and at least 56dp tall, stacked for the thumb.
class _ButtonBar extends StatelessWidget {
  const _ButtonBar({
    required this.showAlways,
    this.approveLabel = 'Approve once',
    required this.submitting,
    required this.onDecide,
  });

  final bool showAlways;

  /// "Approve" for an SMS contact: approving permits them until removed,
  /// so "once" would mislead.
  final String approveLabel;
  final Decision? submitting;
  final ValueChanged<Decision>? onDecide;

  @override
  Widget build(BuildContext context) {
    final enabled = onDecide != null;

    Widget label(String text, Decision d) =>
        _busyLabel(text, busy: submitting == d);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: enabled ? () => onDecide!(Decision.once) : null,
            child: label(approveLabel, Decision.once),
          ),
          if (showAlways) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: enabled ? () => onDecide!(Decision.always) : null,
              child: label('Always allow', Decision.always),
            ),
          ],
        ],
      ),
    );
  }
}

/// Deny, pinned under the scrolling part so it is always on screen.
class _DenyButton extends StatelessWidget {
  const _DenyButton({required this.submitting, required this.onDecide});

  final Decision? submitting;
  final ValueChanged<Decision>? onDecide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: OutlinedButton(
        onPressed: onDecide == null ? null : () => onDecide!(Decision.deny),
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.error,
          side: BorderSide(color: scheme.error.withValues(alpha: 0.6)),
        ),
        child: _busyLabel('Deny', busy: submitting == Decision.deny),
      ),
    );
  }
}

/// A button's text, with a spinner beside it while its decision is sent.
Widget _busyLabel(String text, {required bool busy}) => busy
    ? Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 12),
          Text(text),
        ],
      )
    : Text(text);

/// A scroll view whose scrollbar is always drawn, so it is plain that
/// there is more to see.
class _Scrolled extends StatefulWidget {
  const _Scrolled({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  State<_Scrolled> createState() => _ScrolledState();
}

class _ScrolledState extends State<_Scrolled> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _controller,
    thumbVisibility: true,
    child: SingleChildScrollView(
      controller: _controller,
      padding: widget.padding,
      child: widget.child,
    ),
  );
}

/// A final state: one icon, one title, one sentence, one button. Calm.
class _OutcomeBody extends StatelessWidget {
  const _OutcomeBody({
    required this.request,
    required this.outcome,
    required this.onRetry,
  });

  final ApprovalRequest request;
  final DecisionOutcome outcome;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final agent = request.shownAgent;
    final site = request.shownSite;
    final what = request.allows;

    final (
      IconData icon,
      Color iconBg,
      Color iconFg,
      String title,
      String body,
    ) = switch (outcome) {
      Approved(decision: Decision.always) => (
        Icons.check,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        'Always allowed',
        '$agent can $what from now on without asking. '
            'To stop this, ask the agent to revoke it.',
      ),
      Approved() when request.isSmsContact => (
        Icons.check,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        'Approved',
        '$agent can text ${request.shownNumber} now. To stop, remove them under '
            'Messages > Permitted contacts.',
      ),
      Approved() => (
        Icons.check,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        'Approved',
        '$agent can $what now.',
      ),
      Denied() => (
        Icons.block,
        scheme.surfaceContainerHighest,
        scheme.onSurface,
        'Denied',
        '$agent was not allowed to $what.',
      ),
      AnsweredElsewhere() => (
        Icons.devices,
        scheme.surfaceContainerHighest,
        scheme.onSurface,
        'Answered on another device',
        'This request was already decided on one of your other devices.',
      ),
      Expired() => (
        Icons.timer_off_outlined,
        scheme.surfaceContainerHighest,
        scheme.onSurface,
        'Request expired',
        'Nobody answered in time, so it was denied.',
      ),
      Withdrawn() => (
        Icons.undo,
        scheme.surfaceContainerHighest,
        scheme.onSurface,
        'Request withdrawn',
        '$agent no longer needs this. Nothing was allowed.',
      ),
      Failed(:final message) => (
        Icons.error_outline,
        scheme.errorContainer,
        scheme.onErrorContainer,
        "Couldn't send your decision",
        message,
      ),
      Cancelled() => (
        Icons.fingerprint,
        scheme.surfaceContainerHighest,
        scheme.onSurface,
        'Not confirmed',
        'Nothing was sent.',
      ),
      // Goes back to the request instead; listed for completeness.
      ShownChanged() => (
        Icons.refresh,
        scheme.surfaceContainerHighest,
        scheme.onSurface,
        'This request changed',
        'Nothing was approved. Review it again.',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 48),
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: iconBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 44, color: iconFg),
                ),
                const SizedBox(height: 28),
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  body,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (request.isSmsContact && outcome is! Failed) ...[
                  const SizedBox(height: 28),
                  _Detail(label: 'Number', value: formatPhone(site)),
                ] else if (outcome is! Failed) ...[
                  const SizedBox(height: 28),
                  _Detail(label: 'Site', value: site),
                  if (request.shownLoginTitle case final t?) ...[
                    const SizedBox(height: 16),
                    _Detail(label: 'Login', value: t),
                  ],
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (onRetry != null) ...[
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Close'),
                ),
              ] else
                FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Done'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Exposed for the debug preview and tests: the headline a request renders.
String requestHeadline(ApprovalRequest r) => r.isSmsContact
    ? '${r.shownAgent} would like approval to text ${r.shownNumber}'
    : '${r.shownAgent} would like approval to sign in to ${r.shownSite}';
