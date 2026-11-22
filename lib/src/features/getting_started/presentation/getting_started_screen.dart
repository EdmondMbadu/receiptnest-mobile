import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/data/auth_repository.dart';
import '../data/native_onboarding_repository.dart';
import '../../receipts/data/receipt_repository.dart';
import '../../receipts/presentation/upload_receipt_sheet.dart';

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

class GettingStartedScreen extends ConsumerWidget {
  const GettingStartedScreen({super.key});

  Future<void> _addReceipt(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    var uploaded = false;
    await showModalBottomSheet<void>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      constraints: BoxConstraints(
        maxWidth: 540,
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      builder: (_) => UploadReceiptSheet(
        userId: uid,
        repository: ref.read(receiptRepositoryProvider),
        onUploaded: (_) => uploaded = true,
      ),
    );
    if (!uploaded || !context.mounted) return;
    if (GoRouterState.of(context).uri.path == '/app/help') {
      context.go('/app/home');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final uid = ref.watch(currentUserIdProvider);
    final completed = uid == null
        ? false
        : ref
                  .watch(nativeOnboardingProvider(uid))
                  .valueOrNull
                  ?.progress
                  .completed ??
              false;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Help & getting started',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Text(
          'Snap. Organize.\nDownload.',
          style: Theme.of(
            context,
          ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        const Text(
          'Start with one receipt. ReceiptNest takes care of the details in most cases.',
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => _addReceipt(context, ref),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add a receipt'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => context.push(
            completed ? '/app/onboarding?replay=1' : '/app/onboarding',
          ),
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Replay the guided receipt walkthrough'),
        ),
        const SizedBox(height: 24),
        Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => openGettingStartedVideo(context),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.play_circle_fill_rounded,
                    size: 52,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Watch the 85-second walkthrough',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'See the core workflow on the web. Captions included. The mobile steps are below.',
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const _Step(
          number: '1',
          title: 'Add your receipt',
          description:
              'On Home, tap +. Choose Camera to take a photo, Gallery for an existing image, or Files for a document. Check the preview, then tap Upload receipt.',
        ),
        const _Step(
          number: '2',
          title: 'Let ReceiptNest organize it',
          description:
              'ReceiptNest reads the merchant, amount and date, assigns a category, and saves your receipt automatically. For most receipts, that is all you need to do. Open a receipt to check or edit its details when needed.',
        ),
        const _Step(
          number: '3',
          title: 'Find and export',
          description:
              'Search on Home, then tap a receipt to see its details and original file. For exports, open Collections, choose a category and period, then tap Export for CSV or PDF and save or share the file.',
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.go('/app/home'),
          icon: const Icon(Icons.home_outlined),
          label: const Text('Open my receipts'),
        ),
        TextButton(
          onPressed: () => context.push('/support'),
          child: const Text('Contact support'),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.description,
  });
  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(radius: 16, child: Text(number)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(description, style: const TextStyle(height: 1.5)),
            ],
          ),
        ),
      ],
    ),
  );
}
