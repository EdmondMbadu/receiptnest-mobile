import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/data/auth_repository.dart';
import '../data/native_onboarding_repository.dart';

const gettingStartedVideoUrl =
    'https://receipt-nest.com/getting-started#walkthrough';

Future<void> openGettingStartedVideo(BuildContext context) async {
  try {
    // A browser sheet supports the existing captioned video without another login.
    final opened = await launchUrl(
      Uri.parse(gettingStartedVideoUrl),
      mode: LaunchMode.inAppBrowserView,
    );
    if (opened) return;
  } catch (_) {
    // Keep the written instructions available if a browser cannot be opened.
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Could not open the video. Please try again when you are online.',
      ),
    ),
  );
}

class GettingStartedScreen extends ConsumerStatefulWidget {
  const GettingStartedScreen({super.key});

  @override
  ConsumerState<GettingStartedScreen> createState() =>
      _GettingStartedScreenState();
}

class _GettingStartedScreenState extends ConsumerState<GettingStartedScreen> {
  int? _expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final uid = ref.watch(currentUserIdProvider);
    final completed =
        uid != null &&
        (ref
                .watch(nativeOnboardingProvider(uid))
                .valueOrNull
                ?.progress
                .completed ??
            false);
    return ColoredBox(
      color: dark ? const Color(0xFF0D0D12) : Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 680;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                key: const ValueKey('help-content'),
                padding: EdgeInsets.fromLTRB(20, compact ? 16 : 24, 20, 24),
                children: [
                  Text(
                    'Help & getting started',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: compact ? 16 : 24),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 16 : 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: compact ? 36 : 42,
                              height: compact ? 36 : 42,
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.receipt_long_outlined,
                                size: 23,
                                color: colors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Start with one receipt.',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add it. We’ll organize the details.',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: uid == null
                                ? null
                                : () => context.push(
                                    completed
                                        ? '/app/onboarding?replay=1'
                                        : '/app/onboarding',
                                  ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(child: Text('Show me how')),
                                SizedBox(width: 12),
                                Icon(Icons.arrow_forward_rounded, size: 19),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Quick help',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        _HelpTopic(
                          key: const ValueKey('help-find'),
                          icon: Icons.search_rounded,
                          title: 'Find or edit a receipt',
                          answer:
                              'Search on Home. Open a receipt to review or edit its details.',
                          action: 'Open my receipts',
                          onAction: () => context.go('/app/home'),
                          expanded: _expanded == 0,
                          onToggle: () => setState(
                            () => _expanded = _expanded == 0 ? null : 0,
                          ),
                        ),
                        const _TopicDivider(),
                        _HelpTopic(
                          key: const ValueKey('help-email'),
                          icon: Icons.mail_outline_rounded,
                          title: 'Forward an email',
                          answer:
                              'Send a receipt email to your personal ReceiptNest address. It will appear with your other receipts.',
                          action: 'Get my receipt address',
                          onAction: () => context.push('/app/forward-email'),
                          expanded: _expanded == 1,
                          onToggle: () => setState(
                            () => _expanded = _expanded == 1 ? null : 1,
                          ),
                        ),
                        const _TopicDivider(),
                        _HelpTopic(
                          key: const ValueKey('help-export'),
                          icon: Icons.file_download_outlined,
                          title: 'Export receipts',
                          answer:
                              'In Collections, choose a category and period, then export a CSV or PDF.',
                          action: 'Open Collections',
                          onAction: () => context.go('/app/folders'),
                          expanded: _expanded == 2,
                          onToggle: () => setState(
                            () => _expanded = _expanded == 2 ? null : 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => openGettingStartedVideo(context),
                      icon: const Icon(
                        Icons.play_circle_outline_rounded,
                        size: 21,
                      ),
                      label: const Text('Watch the video · 85 sec'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => context.push('/support'),
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 21,
                      ),
                      label: const Text('Contact support'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopicDivider extends StatelessWidget {
  const _TopicDivider();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 16),
    child: Divider(height: 1),
  );
}

class _HelpTopic extends StatelessWidget {
  const _HelpTopic({
    super.key,
    required this.icon,
    required this.title,
    required this.answer,
    required this.action,
    required this.onAction,
    required this.expanded,
    required this.onToggle,
  });
  final IconData icon;
  final String title;
  final String answer;
  final String action;
  final VoidCallback onAction;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(
                children: [
                  Icon(icon, size: 21, color: colors.onSurface),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          curve: Curves.easeOutCubic,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        answer,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: onAction,
                          child: Text(action),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
