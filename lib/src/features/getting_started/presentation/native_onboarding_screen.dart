import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../auth/data/auth_repository.dart';
import '../../receipts/data/receipt_repository.dart';
import '../../receipts/models/receipt.dart';
import '../../receipts/presentation/upload_receipt_sheet.dart';
import '../data/native_onboarding_repository.dart';
import '../data/onboarding_analytics.dart';
import 'onboarding_widgets.dart';

/// This gate runs after every authenticated cold start, not when changing tabs.
class NativeOnboardingEntryScreen extends ConsumerWidget {
  const NativeOnboardingEntryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const Scaffold(body: SizedBox.shrink());
    final state = ref.watch(nativeOnboardingProvider(uid));
    ref.listen(nativeOnboardingProvider(uid), (previous, next) {
      final value = next.valueOrNull;
      if (value != null && ref.read(currentUserIdProvider) == uid) {
        _navigate(context, value);
      }
    });
    final value = state.valueOrNull;
    if (value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && ref.read(currentUserIdProvider) == uid) {
          _navigate(context, value);
        }
      });
    }
    return Scaffold(
      body: OnboardingCanvas(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const OnboardingBrand(),
                    const SizedBox(height: 36),
                    if (state.hasError) ...[
                      const Text(
                        'Let’s get you started.',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'We couldn’t check your receipts. Try again, or continue to Home.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => ref
                            .read(nativeOnboardingProvider(uid).notifier)
                            .load(),
                        child: const Text('Try again'),
                      ),
                      TextButton(
                        onPressed: () => context.go('/app/home'),
                        child: const Text('Continue to Home'),
                      ),
                    ] else ...[
                      const CircularProgressIndicator(strokeWidth: 2),
                      const SizedBox(height: 18),
                      const Text(
                        'Getting your receipts ready…',
                        semanticsLabel: 'Getting your receipts ready',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _navigate(BuildContext context, NativeOnboardingState state) {
    if (context.mounted) {
      context.go(state.enterGuide ? '/app/onboarding' : '/app/home');
    }
  }
}

class NativeOnboardingScreen extends ConsumerStatefulWidget {
  const NativeOnboardingScreen({
    super.key,
    this.replay = false,
    this.startFresh = false,
  });
  final bool replay;
  final bool startFresh;
  @override
  ConsumerState<NativeOnboardingScreen> createState() =>
      _NativeOnboardingScreenState();
}

class _NativeOnboardingScreenState
    extends ConsumerState<NativeOnboardingScreen> {
  bool _started = false;
  bool _uploadOpen = false;
  bool _choosingAgain = false;
  String? _sessionReceiptId;
  String? _measuredStatus;
  bool _viewed = false;
  Timer? _slowTimer;
  bool _slow = false;
  String? _recoveringReceiptId;

  @override
  void initState() {
    super.initState();
    _choosingAgain = widget.startFresh;
    _slowTimer = Timer(const Duration(seconds: 45), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  NativeOnboardingController _controller(String uid) =>
      ref.read(nativeOnboardingProvider(uid).notifier);

  bool _replaying(String uid) =>
      widget.replay ||
      ref.read(nativeOnboardingProvider(uid)).valueOrNull?.progress.completed ==
          true;

  void _recoverDeletedReceipt(String uid, String receiptId) {
    if (_recoveringReceiptId == receiptId) return;
    _recoveringReceiptId = receiptId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ref.read(currentUserIdProvider) != uid) return;
      setState(() {
        _choosingAgain = true;
        _sessionReceiptId = null;
        _viewed = false;
        _measuredStatus = null;
      });
      unawaited(_controller(uid).forgetDeletedReceipt(receiptId));
    });
  }

  Future<void> _pause() async {
    if (_uploadOpen) return;
    final uid = ref.read(currentUserIdProvider);
    if (uid != null && !_replaying(uid)) await _controller(uid).act('pause');
    if (mounted) context.go('/app/home');
  }

  Future<void> _upload(ReceiptSource source) async {
    if (_uploadOpen) return;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    setState(() => _uploadOpen = true);
    ref.read(onboardingAnalyticsProvider).event('native_source_selected', {
      'source': source.name,
    });
    Receipt? uploaded;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        maxWidth: 520,
      ),
      builder: (_) => UploadReceiptSheet(
        userId: uid,
        repository: ref.read(receiptRepositoryProvider),
        initialSource: source,
        guided: true,
        onUploaded: (receipt) => uploaded = receipt,
      ),
    );
    if (!mounted || ref.read(currentUserIdProvider) != uid) return;
    setState(() => _uploadOpen = false);
    if (uploaded != null) {
      setState(() {
        _sessionReceiptId = uploaded!.id;
        _choosingAgain = false;
        _viewed = false;
        _slow = false;
      });
      _slowTimer?.cancel();
      _slowTimer = Timer(const Duration(seconds: 45), () {
        if (mounted) setState(() => _slow = true);
      });
      if (!_replaying(uid)) {
        await _controller(uid).act('upload', receiptId: uploaded!.id);
      }
    }
  }

  Future<void> _openReceipt(String uid, Receipt receipt) async {
    final reviewed = await context.push<bool>(
      '/app/receipt/${receipt.id}?guide=1${_replaying(uid) ? '&replay=1' : ''}',
    );
    if (!mounted || ref.read(currentUserIdProvider) != uid) return;
    if (reviewed == true) setState(() => _viewed = true);
  }

  Future<void> _finish(
    String uid,
    String? receiptId, {
    bool another = false,
  }) async {
    if (ref.read(currentUserIdProvider) != uid) return;
    if (!_replaying(uid)) {
      await _controller(uid).act('complete', receiptId: receiptId);
    }
    if (!mounted) return;
    final query = <String, String>{if (another) 'addReceipt': '1'};
    context.go(
      Uri(
        path: '/app/home',
        queryParameters: query.isEmpty ? null : query,
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const SizedBox.shrink();
    final asyncState = ref.watch(nativeOnboardingProvider(uid));
    final state = asyncState.valueOrNull;
    if (!_started && state != null) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.replay && !state.progress.completed) {
          _controller(uid).act(widget.startFresh ? 'restart' : 'introduce');
        }
      });
    }
    final replaying = widget.replay || state?.progress.completed == true;
    final savedReceiptId = _choosingAgain
        ? null
        : _sessionReceiptId ?? (replaying ? null : state?.progress.receiptId);
    final receiptAsync = savedReceiptId == null
        ? null
        : ref.watch(receiptWatchProvider(savedReceiptId));
    final deleted =
        receiptAsync is AsyncData<Receipt?> && receiptAsync.value == null;
    if (deleted && savedReceiptId != null) {
      _recoverDeletedReceipt(uid, savedReceiptId);
    }
    final receiptId = deleted ? null : savedReceiptId;
    final receipt = receiptAsync?.valueOrNull;
    final ready = receipt != null && !receipt.isProcessing;
    final usable = receipt != null && isUsableReceipt(receipt);
    final viewed =
        _viewed ||
        (!replaying &&
            state?.progress.viewedAt != null &&
            receiptId == state?.progress.receiptId);
    final stage = receiptId == null
        ? 0
        : ready
        ? 2
        : 1;
    final cs = Theme.of(context).colorScheme;
    if (receipt != null && receipt.status != _measuredStatus) {
      _measuredStatus = receipt.status;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(onboardingAnalyticsProvider).event('native_receipt_result', {
            'status': receipt.status,
            'usable': usable ? 1 : 0,
          });
        }
      });
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _pause();
      },
      child: Scaffold(
        body: OnboardingCanvas(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 12, 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: OnboardingBrand(),
                        ),
                      ),
                      IconButton(
                        onPressed: _uploadOpen ? null : _pause,
                        tooltip: 'Continue later',
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OnboardingProgress(stage: stage),
                            const SizedBox(height: 32),
                            AnimatedSwitcher(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 300),
                              child: KeyedSubtree(
                                key: ValueKey(
                                  '$stage:$viewed:${receipt?.status}',
                                ),
                                child: state == null
                                    ? _loading(asyncState.hasError, uid)
                                    : receiptId == null
                                    ? _choose(state)
                                    : viewed &&
                                          receipt?.status ==
                                              ReceiptStatuses.finalStatus
                                    ? _success(uid, receipt!)
                                    : receiptAsync?.hasError == true
                                    ? _receiptLoadError(receiptId)
                                    : !ready
                                    ? _processing()
                                    : _result(uid, receipt, usable),
                              ),
                            ),
                            const SizedBox(height: 22),
                            if (!viewed)
                              TextButton(
                                onPressed: _uploadOpen ? null : _pause,
                                child: Text(
                                  receiptId == null
                                      ? 'I’ll do this later'
                                      : 'Continue later',
                                ),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              'A little guidance. A lot less paper.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _loading(bool error, String uid) => Column(
    children: [
      if (error) ...[
        const OnboardingMessage(
          message:
              'We couldn’t load your guide. Please check your connection and try again.',
          error: true,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => _controller(uid).load(),
          child: const Text('Try again'),
        ),
      ] else
        const Center(child: CircularProgressIndicator()),
    ],
  );

  Widget _choose(NativeOnboardingState state) {
    final liveCount = ref.watch(receiptsStreamProvider).asData?.value.length;
    final first = (liveCount ?? state.receiptCount) == 0;
    final receipts = ref.watch(sortedReceiptsProvider);
    final existing = receipts.where((r) => !r.isProcessing).firstOrNull;
    return OnboardingReveal(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            first
                ? 'Start with\none receipt.'
                : 'Make your next\nreceipt effortless.',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              fontSize: 36,
              height: 1.12,
              letterSpacing: -1.3,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'A paper receipt, a photo, or a PDF. Choose what you have and we’ll take care of the details.',
            style: TextStyle(
              fontSize: 16,
              height: 1.55,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          OnboardingPaper(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                _SourceTile(
                  icon: Icons.camera_alt_outlined,
                  title: 'Take a photo',
                  subtitle: 'For a paper receipt',
                  onTap: () => _upload(ReceiptSource.camera),
                  primary: true,
                ),
                const SizedBox(height: 6),
                _SourceTile(
                  icon: Icons.photo_library_outlined,
                  title: 'Choose a photo',
                  subtitle: 'An image already on your phone',
                  onTap: () => _upload(ReceiptSource.gallery),
                ),
                const SizedBox(height: 6),
                _SourceTile(
                  icon: Icons.description_outlined,
                  title: 'Choose a file',
                  subtitle: 'A PDF or saved receipt',
                  onTap: () => _upload(ReceiptSource.file),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const OnboardingMessage(
            message:
                'We’ll read the merchant, date, amount, and category. You can check or edit them anytime.',
          ),
          if (!first && existing != null) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _sessionReceiptId = existing.id;
                  _choosingAgain = false;
                });
                final uid = ref.read(currentUserIdProvider);
                if (uid != null && !_replaying(uid)) {
                  _controller(uid).act('upload', receiptId: existing.id);
                }
              },
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Show me with an existing receipt'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _processing() => OnboardingReveal(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ReceiptIllustration(),
        const SizedBox(height: 24),
        Text(
          'The details,\ncoming together.',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            fontSize: 34,
            height: 1.12,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Your upload is saved. We’re reading the merchant, date, amount, and category.',
          style: TextStyle(
            fontSize: 16,
            height: 1.55,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
        const LinearProgressIndicator(
          minHeight: 4,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        const SizedBox(height: 20),
        OnboardingMessage(
          message: _slow
              ? 'This is taking a little longer. Your receipt is safe here. You can continue and check back later.'
              : 'You can leave this screen. Your receipt will be here when you return.',
        ),
      ],
    ),
  );

  Widget _receiptLoadError(String id) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const OnboardingMessage(
        message:
            'We couldn’t load your receipt. Check your connection and try again. Your guide is saved.',
        error: true,
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () => ref.invalidate(receiptWatchProvider(id)),
        child: const Text('Try again'),
      ),
      TextButton(
        onPressed: _restart,
        child: const Text('Choose another receipt'),
      ),
    ],
  );

  void _restart() {
    final uid = ref.read(currentUserIdProvider);
    if (uid != null && !_replaying(uid)) _controller(uid).act('restart');
    setState(() {
      _choosingAgain = true;
      _viewed = false;
      _sessionReceiptId = null;
    });
  }

  Widget _result(String uid, Receipt receipt, bool usable) {
    final needsReview = receipt.status != ReceiptStatuses.finalStatus;
    return OnboardingReveal(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            usable ? Icons.task_alt_rounded : Icons.fact_check_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            needsReview
                ? 'A quick check\nand you’re done.'
                : 'Your receipt,\nbeautifully organized.',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              fontSize: 34,
              height: 1.12,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            needsReview
                ? 'Some details need your attention. Open the receipt, check it against the original, then confirm and save.'
                : 'The details are filled in and the original is safely stored. Let’s take a look.',
            style: TextStyle(
              fontSize: 16,
              height: 1.55,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          OnboardingPaper(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'YOUR RECEIPT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  receipt.merchant?.canonicalName ??
                      receipt.merchant?.rawName ??
                      receipt.file.originalName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  receipt.effectiveTotalAmount == null
                      ? 'Amount needs review'
                      : formatCurrency(receipt.effectiveTotalAmount),
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(formatDate(receipt.effectiveDate)),
                    if (receipt.category != null) Text(receipt.category!.name),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _openReceipt(uid, receipt),
            icon: Icon(
              needsReview
                  ? Icons.fact_check_outlined
                  : Icons.arrow_forward_rounded,
              size: 19,
            ),
            label: Text(
              needsReview ? 'Check receipt details' : 'View my receipt',
            ),
          ),
          if (!usable)
            TextButton(
              onPressed: _restart,
              child: const Text('Try a clearer receipt instead'),
            ),
        ],
      ),
    );
  }

  Widget _success(String uid, Receipt receipt) => OnboardingReveal(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.08),
          ),
          child: Icon(
            Icons.check_rounded,
            size: 62,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'One less receipt\nto worry about.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            fontSize: 34,
            height: 1.12,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Your receipt is saved. Find it anytime in Home, with its details and original file together.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            height: 1.55,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => _finish(uid, receipt.id),
          child: const Text('View my receipts'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _finish(uid, receipt.id, another: true),
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Add another receipt'),
        ),
      ],
    ),
  );
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: primary ? cs.primary.withValues(alpha: 0.07) : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: cs.primary, size: 25),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: cs.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
