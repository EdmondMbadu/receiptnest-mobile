import '../models/receipt_file_label.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/formatters.dart';
import '../../getting_started/presentation/onboarding_widgets.dart';
import '../data/receipt_repository.dart';
import '../models/receipt.dart';

DateTime? receiptTransactionDate(Receipt receipt) {
  final raw = receipt.date ?? receipt.extraction?.date?.value?.toString();
  // An upload timestamp is not evidence of the receipt's transaction date.
  return raw == null || raw.trim().isEmpty ? null : receipt.effectiveDate;
}

String receiptDisplayMerchant(Receipt receipt) {
  final value =
      receipt.merchant?.canonicalName ??
      receipt.merchant?.rawName ??
      receipt.extraction?.supplierName?.value?.toString();
  return value == null || value.trim().isEmpty
      ? 'Merchant needs review'
      : value;
}

bool receiptUploadNeedsReview(Receipt receipt) =>
    receipt.status != ReceiptStatuses.finalStatus ||
    receipt.effectiveTotalAmount == null ||
    !receipt.effectiveTotalAmount!.isFinite ||
    receiptTransactionDate(receipt) == null ||
    receiptDisplayMerchant(receipt) == 'Merchant needs review';

class ReceiptUploadPreview extends StatelessWidget {
  const ReceiptUploadPreview({
    super.key,
    this.file,
    this.receipt,
    this.height = 154,
  });
  final UploadFileData? file;
  final Receipt? receipt;
  final double height;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = file?.name ?? receipt?.file.originalName ?? 'Your receipt';
    final label = receiptFileLabel(name);
    final pdf = name.toLowerCase().endsWith('.pdf') || receipt?.isPdf == true;
    final path = file?.path;
    final image = !pdf && path != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          if (image)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(path),
                height: height,
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => _document(context, pdf),
              ),
            )
          else
            _document(context, pdf),
          const SizedBox(height: 12),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _document(BuildContext context, bool pdf) => SizedBox(
    height: height.clamp(60, 100),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            pdf ? Icons.picture_as_pdf_outlined : Icons.receipt_long_outlined,
            size: 38,
            color: Theme.of(context).colorScheme.primary,
          ),
          if (pdf) ...[
            const SizedBox(height: 7),
            Text(
              'PDF document',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class ReceiptReadingResult extends StatelessWidget {
  const ReceiptReadingResult({
    super.key,
    this.file,
    this.receipt,
    this.slow = false,
    this.onContinue,
  });
  final UploadFileData? file;
  final Receipt? receipt;
  final bool slow;
  final VoidCallback? onContinue;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusLabel(icon: Icons.cloud_done_outlined, label: 'Upload saved'),
        const SizedBox(height: 18),
        ReceiptUploadPreview(file: file, receipt: receipt, height: 110),
        const SizedBox(height: 22),
        Text('The details,\ncoming together.', style: _title(context)),
        const SizedBox(height: 12),
        Text(
          'We’re reading the merchant, date, amount, and category.',
          style: _body(context),
        ),
        const SizedBox(height: 22),
        Text(
          'Reading your receipt',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          liveRegion: true,
          label: 'Reading receipt details. Upload saved.',
          child: LinearProgressIndicator(
            minHeight: 4,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, size: 17, color: cs.primary),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                slow
                    ? 'This is taking a little longer. Your original is saved. You can keep browsing and check back here.'
                    : 'Your original is safe. You can keep browsing while we finish.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        if (onContinue != null) ...[
          const SizedBox(height: 22),
          OutlinedButton(
            onPressed: onContinue,
            child: const Text('Continue browsing'),
          ),
        ],
      ],
    );
  }
}

class ReceiptUploadResult extends StatelessWidget {
  const ReceiptUploadResult({
    super.key,
    required this.receipt,
    required this.onView,
    this.onViewMonth,
    this.onAnother,
    this.first = false,
    this.guided = false,
    this.onReplace,
    this.onClose,
  });
  final Receipt receipt;
  final VoidCallback onView;
  final VoidCallback? onViewMonth;
  final VoidCallback? onAnother;
  final VoidCallback? onReplace;
  final VoidCallback? onClose;
  final bool first;
  final bool guided;
  @override
  Widget build(BuildContext context) {
    final needsReview = receiptUploadNeedsReview(receipt);
    final fromEmail = receipt.source == 'email';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatusLabel(
                icon: needsReview
                    ? Icons.fact_check_outlined
                    : Icons.task_alt_rounded,
                label: needsReview
                    ? 'A quick check needed'
                    : fromEmail
                    ? 'Receipt saved'
                    : 'Receipt organized',
              ),
            ),
            if (onClose != null)
              IconButton(
                onPressed: onClose,
                tooltip: 'Close receipt result',
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          needsReview
              ? 'A quick check\nand you’re done.'
              : fromEmail
              ? 'Your receipt is here.'
              : first
              ? 'Your first receipt,\nall together.'
              : 'Another receipt,\ntaken care of.',
          style: fromEmail
              ? _title(context).copyWith(fontWeight: FontWeight.w600)
              : _title(context),
        ),
        const SizedBox(height: 12),
        Text(
          needsReview
              ? 'Your original is saved. Check the details against it, then confirm and save.'
              : fromEmail
              ? 'Forwarded from your email. The details are ready for you to review.'
              : 'The details are filled in and the original is safely stored.',
          style: _body(context),
        ),
        const SizedBox(height: 22),
        ReceiptUploadSummary(receipt: receipt, onViewMonth: onViewMonth),
        const SizedBox(height: 22),
        if (!first && !guided && !needsReview && onAnother != null) ...[
          FilledButton.icon(
            onPressed: onAnother,
            icon: const Icon(Icons.add_rounded, size: 19),
            label: const Text('Add another receipt'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onView,
            icon: const Icon(Icons.arrow_forward_rounded, size: 19),
            label: const Text('View receipt'),
          ),
        ] else ...[
          FilledButton.icon(
            onPressed: onView,
            icon: Icon(
              needsReview
                  ? Icons.fact_check_outlined
                  : Icons.arrow_forward_rounded,
              size: 19,
            ),
            label: Text(
              needsReview
                  ? 'Check receipt details'
                  : !fromEmail && (first || guided)
                  ? 'View my receipt'
                  : 'View receipt',
            ),
          ),
          if (onAnother != null && !needsReview) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onAnother,
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('Add another receipt'),
            ),
          ],
        ],
        if (needsReview && onReplace != null)
          TextButton(
            onPressed: onReplace,
            child: const Text('Try a clearer receipt instead'),
          ),
      ],
    );
  }
}

class ReceiptUploadSummary extends StatelessWidget {
  const ReceiptUploadSummary({
    super.key,
    required this.receipt,
    this.onViewMonth,
  });
  final Receipt receipt;
  final VoidCallback? onViewMonth;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final date = receiptTransactionDate(receipt);
    final amount = receipt.effectiveTotalAmount;
    final currency =
        receipt.currency ??
        receipt.extraction?.currency?.value?.toString() ??
        'USD';
    final month = date == null ? null : DateFormat('MMMM').format(date);
    return OnboardingPaper(
      neutral: receipt.source == 'email',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'YOUR RECEIPT',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            receiptDisplayMerchant(receipt),
            style: const TextStyle(
              fontSize: 22,
              height: 1.3,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            amount == null || !amount.isFinite
                ? 'Amount needs review'
                : NumberFormat.simpleCurrency(name: currency).format(amount),
            style: TextStyle(
              fontSize: amount == null ? 22 : 40,
              height: 1.25,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.3,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                date == null ? 'Date needs review' : formatDate(date),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              if (receipt.category != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    receipt.category!.name,
                    style: TextStyle(fontSize: 11, color: cs.primary),
                  ),
                ),
            ],
          ),
          if (date != null) ...[
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final label = Row(
                  children: [
                    Icon(Icons.folder_outlined, size: 19, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Filed under',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            DateFormat('MMMM y').format(date),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final action = onViewMonth == null
                    ? null
                    : TextButton(
                        onPressed: onViewMonth,
                        child: Text('View $month'),
                      );
                if (constraints.maxWidth < 260 ||
                    MediaQuery.textScalerOf(context).scale(12) > 16) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      label,
                      if (action != null)
                        Align(alignment: Alignment.centerLeft, child: action),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: label),
                    ?action,
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    ],
  );
}

TextStyle _title(BuildContext context) =>
    Theme.of(context).textTheme.headlineLarge!.copyWith(
      fontSize: 30,
      height: 1.16,
      fontWeight: FontWeight.w800,
      letterSpacing: -1,
    );
TextStyle _body(BuildContext context) => TextStyle(
  fontSize: 14,
  height: 1.65,
  color: Theme.of(context).colorScheme.onSurfaceVariant,
);
