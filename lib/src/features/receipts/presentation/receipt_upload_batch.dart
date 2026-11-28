import '../models/receipt_file_label.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/formatters.dart';
import '../data/receipt_upload_activity.dart';

import '../data/receipt_repository.dart';
import '../models/receipt.dart';
import 'receipt_upload_outcome.dart';
import 'receipt_upload_result.dart';

/// A file keeps its identity throughout selection, transfer, and retries.
/// Local file contents are never persisted in upload activity checkpoints.
class ReceiptUploadItem {
  ReceiptUploadItem({required this.file, required this.id});
  final UploadFileData file;
  final String id;
  Receipt? receipt;
  String? error;
  bool uploading = false;
  bool first = false;
  double progress = 0;
}

class ReceiptSelectionTile extends StatelessWidget {
  const ReceiptSelectionTile({
    super.key,
    required this.file,
    this.subtitle,
    this.title,
    this.receiptNumber,
    this.actionLabel,
    this.onRemove,
    this.onTap,
    this.trailing,
    this.error = false,
  });
  final UploadFileData file;
  final String? subtitle;
  final String? title;
  final int? receiptNumber;
  final String? actionLabel;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = receiptFileLabel(file.name, receiptNumber: receiptNumber);
    final ext = file.name.split('.').last.toLowerCase();
    final image = const {
      'jpg',
      'jpeg',
      'png',
      'webp',
      'heic',
      'heif',
    }.contains(ext);
    final fallback = Icon(
      ext == 'pdf' ? Icons.picture_as_pdf_outlined : Icons.description_outlined,
      color: cs.primary,
      size: 25,
    );
    final metadata =
        '${image ? 'Photo' : ext.toUpperCase()} · '
        '${file.sizeBytes >= 1024 * 1024 ? '${(file.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '${(file.sizeBytes / 1024).toStringAsFixed(1)} KB'}';
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 5),
          minLeadingWidth: 48,
          leading: Container(
            width: 48,
            height: 54,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(9),
            ),
            child: image && file.path != null
                ? Image.file(
                    File(file.path!),
                    fit: BoxFit.cover,
                    cacheWidth: 160,
                    errorBuilder: (_, _, _) => fallback,
                  )
                : image && file.bytes != null
                ? Image.memory(
                    file.bytes!,
                    fit: BoxFit.cover,
                    cacheWidth: 160,
                    errorBuilder: (_, _, _) => fallback,
                  )
                : fallback,
          ),
          title: Text(
            title ?? label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subtitle ?? metadata,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: error ? cs.error : cs.onSurfaceVariant,
                  ),
                ),
                if (actionLabel != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    actionLabel!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          trailing: onRemove != null
              ? IconButton(
                  tooltip: 'Remove $label',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, size: 19),
                )
              : trailing,
          onTap: onTap,
        ),
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: .45)),
      ],
    );
  }
}

class ReceiptUploadBatch extends ConsumerWidget {
  const ReceiptUploadBatch({
    super.key,
    required this.userId,
    required this.items,
    required this.uploading,
    required this.onRetry,
    required this.onAnother,
    required this.onRemove,
  });
  final String userId;
  final List<ReceiptUploadItem> items;
  final bool uploading;
  final VoidCallback onRetry;
  final VoidCallback onAnother;
  final ValueChanged<ReceiptUploadItem> onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final saved = items.where((item) => item.receipt != null).length;
    final failed = items.where((item) => item.error != null).length;
    final current = items.indexWhere((item) => item.uploading);
    final live = <String, AsyncValue<Receipt?>>{
      for (final item in items)
        if (item.receipt != null)
          item.id: ref.watch(receiptWatchProvider(item.receipt!.id)),
    };
    var reading = 0;
    var ready = 0;
    var review = 0;
    var checking = 0;
    for (final item in items.where((item) => item.receipt != null)) {
      final value = live[item.id]!;
      if (value is AsyncData<Receipt?> && value.value == null) continue;
      final receipt = value.valueOrNull ?? item.receipt!;
      if (value.hasError) {
        checking++;
      } else if (receipt.isProcessing) {
        reading++;
      } else if (receiptUploadNeedsReview(receipt)) {
        review++;
      } else {
        ready++;
      }
    }
    final status = [
      if (ready > 0) '$ready of $saved ready',
      if (review > 0) '$review to review',
      if (reading > 0)
        ready + review == 0
            ? 'Reading $reading ${reading == 1 ? 'receipt' : 'receipts'}…'
            : '$reading still processing',
      if (checking > 0)
        '$checking ${checking == 1 ? 'needs' : 'need'} a connection check',
    ].join(' · ');
    return PopScope(
      canPop: !uploading,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: CustomScrollView(
                  shrinkWrap: true,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  uploading
                                      ? 'Adding your receipts'
                                      : saved == 0
                                      ? 'Your files are still here'
                                      : 'Your receipts',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (!uploading)
                                IconButton(
                                  tooltip: 'Close uploads',
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            uploading
                                ? 'Saving ${current < 0 ? saved + 1 : current + 1} of ${items.length} files. Keep this screen open.'
                                : '$saved of ${items.length} files saved${failed == 0 ? '.' : '. $failed ${failed == 1 ? 'file needs' : 'files need'} another try.'}',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                          if (status.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              status,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          if (uploading) ...[
                            LinearProgressIndicator(
                              value:
                                  (items.fold<double>(
                                            0,
                                            (sum, item) =>
                                                sum +
                                                (item.receipt != null
                                                    ? 1
                                                    : item.progress),
                                          ) /
                                          items.length)
                                      .clamp(0, 1),
                              minHeight: 4,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            const SizedBox(height: 12),
                          ] else if (reading > 0) ...[
                            const _ReceiptProcessingBar(
                              key: ValueKey('batch-processing'),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    ),
                    SliverList.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) => _BatchItem(
                        userId: userId,
                        item: items[index],
                        number: index + 1,
                        value: live[items[index].id],
                        onRemove: uploading
                            ? null
                            : () => onRemove(items[index]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (!uploading) ...[
                if (failed > 0)
                  FilledButton(
                    onPressed: onRetry,
                    child: Text(
                      'Retry $failed ${failed == 1 ? 'file' : 'files'}',
                    ),
                  )
                else
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Continue browsing'),
                  ),
                if (reading > 0 && failed == 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Your receipts are saved. We’ll keep reading the details.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                TextButton(
                  onPressed: failed > 0
                      ? () => Navigator.of(context).pop()
                      : onAnother,
                  child: Text(
                    failed > 0 ? 'Continue browsing' : 'Add more receipts',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BatchItem extends ConsumerWidget {
  const _BatchItem({
    required this.userId,
    required this.item,
    required this.number,
    this.value,
    this.onRemove,
  });
  final String userId;
  final ReceiptUploadItem item;
  final int number;
  final AsyncValue<Receipt?>? value;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = item.receipt;
    final deleted = value is AsyncData<Receipt?> && value!.value == null;
    final receipt = deleted ? null : value?.valueOrNull ?? seed;
    final ready =
        receipt != null && !receipt.isProcessing && value?.hasError != true;
    final needsReview = ready && receiptUploadNeedsReview(receipt);
    final cs = Theme.of(context).colorScheme;
    final merchant = ready ? receiptDisplayMerchant(receipt) : null;
    final amount = receipt?.effectiveTotalAmount;
    final date = receipt == null ? null : receiptTransactionDate(receipt);
    final currency =
        receipt?.currency ??
        receipt?.extraction?.currency?.value?.toString() ??
        'USD';
    final summary = ready
        ? [
            amount == null || !amount.isFinite
                ? 'Amount needs review'
                : NumberFormat.simpleCurrency(name: currency).format(amount),
            date == null ? 'Date needs review' : formatDate(date),
            if (needsReview) 'Details need review',
          ].join(' · ')
        : null;
    final subtitle =
        item.error ??
        (deleted
            ? 'This receipt was deleted.'
            : seed != null
            ? value?.hasError == true
                  ? 'Saved · Check progress'
                  : ready
                  ? summary!
                  : 'Saved · Reading details'
            : item.uploading
            ? item.progress >= 1
                  ? 'Finishing the save…'
                  : 'Uploading · ${(item.progress * 100).round()}%'
            : 'Waiting to upload');
    return ReceiptSelectionTile(
      key: ValueKey('batch-upload-${item.id}'),
      file: item.file,
      receiptNumber: number,
      title: merchant == 'Merchant needs review' ? null : merchant,
      subtitle: subtitle,
      actionLabel: seed == null || deleted
          ? null
          : ready
          ? needsReview
                ? 'Review receipt'
                : 'View receipt'
          : 'View progress',
      error: item.error != null,
      onRemove: item.error != null ? onRemove : null,
      trailing: seed != null && !deleted
          ? Icon(Icons.chevron_right_rounded, color: cs.primary, size: 22)
          : null,
      onTap: seed == null || deleted
          ? null
          : () {
              if (ready) {
                ref
                    .read(receiptUploadActivityProvider.notifier)
                    .acknowledge(seed.id);
                context.push('/app/receipt/${seed.id}');
                return;
              }
              showModalBottomSheet<void>(
                useRootNavigator: true,
                context: context,
                isScrollControlled: true,
                constraints: BoxConstraints(
                  maxWidth: 540,
                  maxHeight: MediaQuery.sizeOf(context).height * .92,
                ),
                builder: (_) => ReceiptUploadOutcome(
                  userId: userId,
                  receiptId: seed.id,
                  seed: seed,
                  first: item.first,
                  file: item.file,
                ),
              );
            },
    );
  }
}

/// A single indeterminate bar shows activity without inventing a completion
/// percentage. Reduced motion retains a quiet static line and status label.
class _ReceiptProcessingBar extends StatelessWidget {
  const _ReceiptProcessingBar({super.key});
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    if (MediaQuery.disableAnimationsOf(context)) {
      return Semantics(
        label: 'Reading receipt details',
        child: Container(
          height: 3,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .25),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      );
    }
    return LinearProgressIndicator(
      value: null,
      minHeight: 3,
      borderRadius: BorderRadius.circular(3),
      color: color,
      backgroundColor: color.withValues(alpha: .12),
      semanticsLabel: 'Reading receipt details',
    );
  }
}
