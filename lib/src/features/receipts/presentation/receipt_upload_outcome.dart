import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';
import '../../getting_started/data/onboarding_analytics.dart';
import '../../getting_started/presentation/onboarding_widgets.dart';
import '../data/receipt_repository.dart';
import '../data/receipt_upload_activity.dart';
import '../models/receipt.dart';
import 'receipt_upload_result.dart';

class ReceiptUploadOutcome extends ConsumerStatefulWidget {
  const ReceiptUploadOutcome({
    super.key,
    required this.userId,
    required this.receiptId,
    this.seed,
    this.file,
    this.onAnother,
    this.showCloseButton = true,
    this.first = false,
  });
  final String userId;
  final String receiptId;
  final Receipt? seed;
  final UploadFileData? file;
  final VoidCallback? onAnother;
  final bool first;
  final bool showCloseButton;
  @override
  ConsumerState<ReceiptUploadOutcome> createState() =>
      _ReceiptUploadOutcomeState();
}

class _ReceiptUploadOutcomeState extends ConsumerState<ReceiptUploadOutcome> {
  Timer? _timer;
  bool _slow = false;
  bool _deletedHandled = false;
  bool _closingForAccountChange = false;
  String? _measuredStatus;
  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 45), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _acknowledge() {
    if (!mounted || ref.read(currentUserIdProvider) != widget.userId) return;
    ref
        .read(receiptUploadActivityProvider.notifier)
        .acknowledge(widget.receiptId);
  }

  void _close(Receipt? receipt) {
    if (receipt != null && !receipt.isProcessing) _acknowledge();
    Navigator.of(context).pop();
  }

  Future<void> _view() async {
    _acknowledge();
    await context.push('/app/receipt/${widget.receiptId}');
  }

  void _month(Receipt receipt) {
    final date = receiptTransactionDate(receipt);
    if (date == null) return;
    ref.read(selectedMonthProvider.notifier).state = date.month;
    ref.read(selectedYearProvider.notifier).state = date.year;
    _acknowledge();
    ref.read(onboardingAnalyticsProvider).event('native_upload_view_month');
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go('/app/home');
  }

  void _another() {
    _acknowledge();
    widget.onAnother?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(currentUserIdProvider) != widget.userId) {
      if (!_closingForAccountChange) {
        _closingForAccountChange = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ref.read(currentUserIdProvider) != widget.userId) {
            Navigator.of(context).pop();
          }
        });
      }
      return const SizedBox.shrink();
    }
    final value = ref.watch(receiptWatchProvider(widget.receiptId));
    final deleted = value is AsyncData<Receipt?> && value.value == null;
    final receipt = deleted ? null : value.valueOrNull ?? widget.seed;
    if (deleted && !_deletedHandled) {
      _deletedHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _acknowledge();
      });
    }
    final ready = receipt != null && !receipt.isProcessing;
    if (ready && _measuredStatus != receipt.status) {
      _measuredStatus = receipt.status;
      _timer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final start = receipt.file.uploadedAt ?? receipt.createdAt;
        ref
            .read(onboardingAnalyticsProvider)
            .event('native_upload_result_visible', {
              'status': receipt.status,
              'needs_review': receiptUploadNeedsReview(receipt) ? 1 : 0,
              if (start != null && !start.isAfter(DateTime.now()))
                'elapsed_ms': DateTime.now().difference(start).inMilliseconds,
            });
      });
    }
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && ready) _acknowledge();
      },
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!ready && widget.showCloseButton)
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: ready
                        ? 'Close receipt result'
                        : 'Continue browsing',
                    onPressed: () => _close(receipt),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              if (deleted) ...[
                const OnboardingMessage(
                  message:
                      'This receipt was deleted. You can add another receipt whenever you’re ready.',
                ),
                const SizedBox(height: 18),
                if (widget.onAnother != null)
                  FilledButton(
                    onPressed: _another,
                    child: const Text('Add another receipt'),
                  ),
              ] else if (value.hasError && receipt?.isProcessing != false) ...[
                const OnboardingMessage(
                  message:
                      'Your upload is saved. We couldn’t check its progress. Check your connection and try again.',
                  error: true,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(receiptWatchProvider(widget.receiptId)),
                  child: const Text('Check progress again'),
                ),
                TextButton(
                  onPressed: () => _close(receipt),
                  child: const Text('Continue browsing'),
                ),
              ] else if (ready)
                ReceiptUploadResult(
                  receipt: receipt,
                  first: widget.first,
                  onClose: widget.showCloseButton
                      ? () => _close(receipt)
                      : null,
                  onView: _view,
                  onViewMonth: () => _month(receipt),
                  onAnother: widget.onAnother == null ? null : _another,
                  onReplace: widget.onAnother == null ? null : _another,
                )
              else
                ReceiptReadingResult(
                  file: widget.file,
                  receipt: receipt,
                  slow: _slow,
                  onContinue: () => _close(receipt),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
