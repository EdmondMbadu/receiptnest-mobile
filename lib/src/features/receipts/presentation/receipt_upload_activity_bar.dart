import '../models/receipt_file_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';

import '../data/receipt_repository.dart';
import '../data/receipt_upload_activity.dart';
import '../models/receipt.dart';
import 'receipt_upload_outcome.dart';
import 'receipt_upload_result.dart';
import 'receipt_upload_sheet_route.dart';

class ReceiptUploadActivityBar extends ConsumerWidget {
  const ReceiptUploadActivityBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(receiptUploadActivityProvider);
    if (tasks.isEmpty || MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }
    final items = <(ReceiptUploadActivity, Receipt?, bool)>[];
    for (final task in tasks.reversed) {
      final value = ref.watch(receiptWatchProvider(task.id));
      if (value is AsyncData<Receipt?> && value.value == null) {
        final controller = ref.read(receiptUploadActivityProvider.notifier);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => controller.acknowledge(task.id),
        );
        continue;
      }
      items.add((task, value.valueOrNull ?? task.seed, value.hasError));
    }
    if (items.isEmpty) return const SizedBox.shrink();
    final selected = items.first;
    final receipt = selected.$2;
    final ready = receipt != null && !receipt.isProcessing;
    final needsReview = ready && receiptUploadNeedsReview(receipt);
    final cs = Theme.of(context).colorScheme;
    final label = items.length > 1
        ? '${items.length} recent uploads'
        : selected.$3
        ? 'Your upload is saved'
        : ready
        ? needsReview
              ? 'Your receipt needs a quick check'
              : 'Your receipt is ready'
        : 'Your receipt is being organized';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Material(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF17231F)
                : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            child: InkWell(
              key: const ValueKey('receipt-upload-activity'),
              borderRadius: BorderRadius.circular(18),
              onTap: () async {
                final uid = ref.read(currentUserIdProvider);
                if (uid == null) return;
                var task = selected.$1;
                if (items.length > 1) {
                  final chosen =
                      await showModalBottomSheet<ReceiptUploadActivity>(
                        useRootNavigator: true,
                        context: context,
                        isScrollControlled: true,
                        constraints: BoxConstraints(
                          maxWidth: 540,
                          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
                        ),
                        builder: (context) => SafeArea(
                          child: ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'Your recent uploads',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              for (final item in items)
                                _RecentUploadTile(task: item.$1),
                            ],
                          ),
                        ),
                      );
                  if (chosen == null || !context.mounted) return;
                  task = chosen;
                }
                if (!context.mounted ||
                    ref.read(currentUserIdProvider) != uid) {
                  return;
                }
                // Activity always follows this receipt's identity. A guided
                // checkpoint can outlive the guide, so it must not reopen the
                // onboarding source chooser when someone wants their receipt.
                await showModalBottomSheet<void>(
                  useRootNavigator: true,
                  context: context,
                  isScrollControlled: true,
                  constraints: BoxConstraints(
                    maxWidth: 540,
                    maxHeight: MediaQuery.sizeOf(context).height * 0.92,
                  ),
                  builder: (sheetContext) => ReceiptUploadOutcome(
                    userId: uid,
                    first: task.first,
                    receiptId: task.id,
                    seed: task.seed,
                    onAnother: () {
                      Navigator.of(sheetContext).pop();
                      showReceiptUploadSheet(
                        context: context,
                        userId: uid,
                        repository: ref.read(receiptRepositoryProvider),
                        onUploaded: (_) {},
                      );
                    },
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      ready
                          ? needsReview
                                ? Icons.fact_check_outlined
                                : Icons.task_alt_rounded
                          : Icons.receipt_long_outlined,
                      size: 23,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            ready && items.length == 1
                                ? '${receiptDisplayMerchant(receipt)} · Tap to view'
                                : selected.$3
                                ? 'Tap to check your connection and progress'
                                : 'Upload saved · Tap to view progress',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.keyboard_arrow_up_rounded,
                      size: 21,
                      color: cs.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentUploadTile extends ConsumerWidget {
  const _RecentUploadTile({required this.task});
  final ReceiptUploadActivity task;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(receiptWatchProvider(task.id));
    if (value is AsyncData<Receipt?> && value.value == null) {
      return const SizedBox.shrink();
    }
    final receipt = value.valueOrNull ?? task.seed;
    final reading = receipt == null || receipt.isProcessing;
    return ListTile(
      leading: Icon(
        reading ? Icons.receipt_long_outlined : Icons.task_alt_rounded,
      ),
      title: Text(
        reading
            ? receiptFileLabel(receipt?.file.originalName)
            : receiptDisplayMerchant(receipt),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        value.hasError
            ? 'Upload saved · Tap to check progress'
            : reading
            ? 'Upload saved · Reading details'
            : receiptUploadNeedsReview(receipt)
            ? 'Ready to review'
            : 'Receipt organized',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).pop(task),
    );
  }
}
