import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/brand.dart';
import '../widgets/vouch_mark.dart';

/// Short commit the release workflow bakes in (`--dart-define=VOUCH_COMMIT`);
/// empty in local builds.
const buildCommit = String.fromEnvironment('VOUCH_COMMIT');

final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return versionLabel(info.version, info.buildNumber, buildCommit);
});

/// "0.1.0 (100) · 3f2a9c1", or without the commit when none was baked in.
String versionLabel(String version, String buildNumber, String commit) =>
    commit.isEmpty
    ? '$version ($buildNumber)'
    : '$version ($buildNumber) · $commit';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final version = ref.watch(appVersionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          children: [
            const Center(
              child: VouchMark(size: 72, semanticLabel: 'Viewbridge logo'),
            ),
            const SizedBox(height: 16),
            Text(
              Brand.fullName,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              Brand.tagline,
              style: theme.textTheme.titleLarge?.copyWith(
                fontFamily: Brand.serifFamily,
                fontWeight: FontWeight.w400,
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.tag),
              title: const Text('Version'),
              subtitle: Text(
                version.when(
                  data: (v) => v,
                  loading: () => '…',
                  error: (_, _) => 'Unknown',
                ),
              ),
            ),
            // Required by the bundled open-source licences, but not
            // something anyone comes to About for: a quiet link, not a row.
            const SizedBox(height: 24),
            Center(
              child: TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: Brand.fullName,
                  applicationVersion: version.value,
                ),
                child: Text(
                  'Open-source licences',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
