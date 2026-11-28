import '../models/receipt_file_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../auth/data/auth_repository.dart';
import '../data/receipt_repository.dart';
import '../models/category.dart';
import '../models/receipt.dart';
import 'receipt_file_preview.dart';
import '../../getting_started/data/native_onboarding_repository.dart';
import '../../getting_started/data/onboarding_analytics.dart';
import '../../getting_started/presentation/onboarding_widgets.dart';

class ReceiptDetailScreen extends ConsumerStatefulWidget {
  const ReceiptDetailScreen({
    super.key,
    required this.receiptId,
    this.guided = false,
    this.onboardingReplay = false,
  });

  final String receiptId;
  final bool guided;
  final bool onboardingReplay;

  @override
  ConsumerState<ReceiptDetailScreen> createState() =>
      _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends ConsumerState<ReceiptDetailScreen> {
  final _merchantController = TextEditingController();
  final _amountController = TextEditingController();
  final _dateController = TextEditingController();
  final _notesController = TextEditingController();

  String _categoryId = 'other';
  ReceiptCategory? _savedCategory;
  List<ExpenseCategory> get _categoryOptions => categoryOptionsIncluding(
    _savedCategory?.id,
    savedName: _savedCategory?.name,
  );
  bool _loaded = false;
  bool _saving = false;
  bool _deleting = false;
  String? _error;
  String? _success;
  bool _viewRecorded = false;
  final _detailsKey = GlobalKey();

  @override
  void dispose() {
    _merchantController.dispose();
    _amountController.dispose();
    _dateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _loadForm(Receipt receipt) {
    if (_loaded || receipt.isProcessing) return;
    _merchantController.text =
        receipt.merchant?.canonicalName ??
        receipt.extraction?.supplierName?.value?.toString() ??
        '';
    _amountController.text =
        receipt.effectiveTotalAmount?.toString() ??
        receipt.extraction?.totalAmount?.value?.toString() ??
        '';
    _dateController.text =
        receipt.date ?? receipt.extraction?.date?.value?.toString() ?? '';
    _notesController.text = receipt.notes ?? '';
    _savedCategory = receipt.category;
    _categoryId = receipt.category?.id ?? 'other';
    _loaded = true;
  }

  Future<void> _save(Receipt receipt) async {
    if (_saving || _deleting || receipt.isProcessing) return;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    final parsedAmount = double.tryParse(_amountController.text.trim());
    final date = _dateController.text.trim();
    final parsedDate = DateTime.tryParse(date);
    if (parsedAmount == null ||
        !parsedAmount.isFinite ||
        _merchantController.text.trim().isEmpty ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsedDate == null ||
        parsedDate.toIso8601String().substring(0, 10) != date) {
      setState(
        () => _error =
            'Please enter a merchant, a valid amount, and a date in YYYY-MM-DD format.',
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_error!)));
      final detailsContext = _detailsKey.currentContext;
      if (detailsContext != null) {
        Scrollable.ensureVisible(
          detailsContext,
          duration: const Duration(milliseconds: 250),
        );
      }
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });

    try {
      final amount = double.tryParse(_amountController.text.trim());
      final category = _categoryOptions.singleWhere(
        (option) => option.id == _categoryId,
      );

      final updates = <String, dynamic>{
        'merchant': {
          'canonicalName': _merchantController.text.trim(),
          'rawName':
              receipt.merchant?.rawName ?? _merchantController.text.trim(),
          'matchConfidence': 1.0,
          'matchedBy': 'manual',
        },
        'notes': _notesController.text.trim(),
        'status': ReceiptStatuses.finalStatus,
        'category': {
          'id': category.id,
          'name': category.name,
          'confidence': 1.0,
          'assignedBy': 'user',
        },
      };

      if (amount != null) {
        updates['totalAmount'] = amount;
      }

      if (_dateController.text.trim().isNotEmpty) {
        updates['date'] = _dateController.text.trim();
      }

      await ref
          .read(receiptRepositoryProvider)
          .updateReceipt(uid, receipt.id, updates);
      if (!mounted) return;
      setState(() => _success = 'Receipt updated successfully.');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete(Receipt receipt) async {
    if (_deleting || _saving) return;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    setState(() => _deleting = true);

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: isDark ? const Color(0xFF1A1A28) : Colors.white,
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: cs.error,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Delete receipt'),
            ],
          ),
          content: const Text('Are you sure? This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: cs.error),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      if (mounted) setState(() => _deleting = false);
      return;
    }

    try {
      if (!mounted || ref.read(currentUserIdProvider) != uid) return;
      await ref.read(receiptRepositoryProvider).deleteReceipt(uid, receipt);
      if (!mounted || ref.read(currentUserIdProvider) != uid) return;
      await ref
          .read(nativeOnboardingProvider(uid).notifier)
          .forgetDeletedReceipt(receipt.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'We couldn’t delete this receipt. Please check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _openFile(Receipt receipt) async {
    if (ref.read(currentUserIdProvider) != receipt.userId) return;
    await openReceiptOriginal(context, receipt);
  }

  Widget _buildPreviewCard(Receipt receipt) => ReceiptFilePreview(
    key: ValueKey(
      '${receipt.userId}:${receipt.id}:${receipt.file.storagePath}',
    ),
    receipt: receipt,
  );

  Widget _statusBanner(String message, {bool isError = true}) {
    final cs = Theme.of(context).colorScheme;
    final color = isError ? cs.error : const Color(0xFF00C805);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final receiptAsync = ref.watch(receiptWatchProvider(widget.receiptId));
    final currentReceipt = receiptAsync.valueOrNull;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0D0D14)
          : const Color(0xFFF6F7F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Receipt'),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
      ),
      bottomNavigationBar:
          widget.guided &&
              currentReceipt != null &&
              !currentReceipt.isProcessing
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: FilledButton.icon(
                  onPressed: _saving
                      ? null
                      : () {
                          if (currentReceipt.status ==
                              ReceiptStatuses.finalStatus) {
                            Navigator.of(context).pop(true);
                          } else {
                            _save(currentReceipt);
                          }
                        },
                  icon: Icon(
                    currentReceipt.status == ReceiptStatuses.finalStatus
                        ? Icons.arrow_forward_rounded
                        : Icons.check_rounded,
                    size: 20,
                  ),
                  label: Text(
                    _saving
                        ? 'Saving…'
                        : currentReceipt.status == ReceiptStatuses.finalStatus
                        ? 'Continue'
                        : 'Confirm & save',
                  ),
                ),
              ),
            )
          : null,
      body: receiptAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.primary),
        ),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: cs.error.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                'Failed to load receipt',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        data: (receipt) {
          if (receipt == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 48,
                    color: cs.onSurface.withValues(alpha: 0.15),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Receipt not found',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            );
          }

          _loadForm(receipt);

          final isProcessing = receipt.isProcessing;
          if (isProcessing) {
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _ProcessingBanner(),
                const SizedBox(height: 20),
                _buildPreviewCard(receipt),
                const SizedBox(height: 20),
                const OnboardingMessage(
                  message:
                      'Your receipt is saved. Its details will appear here when processing finishes. You can leave and come back anytime.',
                ),
              ],
            );
          }
          if (!isProcessing && !_viewRecorded && isUsableReceipt(receipt)) {
            _viewRecorded = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ref.read(onboardingAnalyticsProvider).event(
                'native_receipt_view',
                {
                  'usable': 1,
                  'guided': widget.guided ? 1 : 0,
                  'receipt_id': receipt.id,
                },
              );
              final uid = ref.read(currentUserIdProvider);
              if (uid != null) {
                ref
                    .read(nativeOnboardingProvider(uid).notifier)
                    .act(
                      widget.guided && !widget.onboardingReplay
                          ? 'view'
                          : 'observe',
                      receiptId: receipt.id,
                    );
              }
            });
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              if (widget.guided && !isProcessing) ...[
                OnboardingMessage(
                  message: receipt.status == ReceiptStatuses.finalStatus
                      ? 'Your receipt is saved. The details below were filled automatically. Editing and notes are optional.'
                      : 'Check the details against your original receipt. Add anything missing, then choose Confirm & save.',
                ),
                const SizedBox(height: 16),
              ],
              // ── Processing banner ──
              if (isProcessing) ...[
                _ProcessingBanner(),
                const SizedBox(height: 14),
              ],

              // ── File card ──
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF151520) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.grey.shade200,
                  ),
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _openFile(receipt),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  cs.primary.withValues(alpha: 0.15),
                                  cs.primary.withValues(alpha: 0.05),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              receipt.isPdf
                                  ? Icons.picture_as_pdf_outlined
                                  : Icons.insert_drive_file_outlined,
                              color: cs.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  receiptFileLabel(receipt.file.originalName),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${formatCurrency(receipt.effectiveTotalAmount)} \u2022 ${formatDate(receipt.effectiveDate)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: cs.onSurface.withValues(alpha: 0.45),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.open_in_full_rounded,
                              size: 18,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),
              _buildPreviewCard(receipt),
              const SizedBox(height: 14),

              // ── Details card ──
              Container(
                key: _detailsKey,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF151520) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.grey.shade200,
                  ),
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.edit_note_rounded,
                            size: 18,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _merchantController,
                      decoration: InputDecoration(
                        labelText: 'Merchant',
                        prefixIcon: Icon(
                          Icons.store_outlined,
                          size: 20,
                          color: cs.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        prefixIcon: Icon(
                          Icons.attach_money_rounded,
                          size: 20,
                          color: cs.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _dateController,
                      decoration: InputDecoration(
                        labelText: 'Date (YYYY-MM-DD)',
                        prefixIcon: Icon(
                          Icons.calendar_today_outlined,
                          size: 20,
                          color: cs.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _categoryId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(
                          Icons.category_outlined,
                          size: 20,
                          color: cs.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                      items: _categoryOptions
                          .map(
                            (category) => DropdownMenuItem<String>(
                              value: category.id,
                              child: Text(
                                '${category.icon} ${category.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _categoryId = value);
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Notes',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(bottom: 40),
                          child: Icon(
                            Icons.notes_outlined,
                            size: 20,
                            color: cs.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                _statusBanner(_error!, isError: true),
              ],
              if (_success != null) ...[
                const SizedBox(height: 14),
                _statusBanner(_success!, isError: false),
              ],

              const SizedBox(height: 20),

              // ── Save button ──
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: _saving || isProcessing
                      ? null
                      : () => _save(receipt),
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 20),
                  label: Text(
                    _saving
                        ? 'Saving...'
                        : receipt.status == ReceiptStatuses.finalStatus
                        ? 'Save changes'
                        : 'Confirm & save',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // ── Delete button ──
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _saving || _deleting
                      ? null
                      : () => _delete(receipt),
                  icon: Icon(Icons.delete_outline, size: 20, color: cs.error),
                  label: Text(
                    'Delete receipt',
                    style: TextStyle(
                      color: cs.error,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: BorderSide(color: cs.error.withValues(alpha: 0.3)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProcessingBanner extends StatefulWidget {
  @override
  State<_ProcessingBanner> createState() => _ProcessingBannerState();
}

class _ProcessingBannerState extends State<_ProcessingBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151520) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final opacity = 0.5 + (_pulse.value * 0.5);
              return Opacity(opacity: opacity, child: child);
            },
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.primary.withValues(alpha: 0.15),
                    cs.primary.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.document_scanner_outlined,
                size: 28,
                color: cs.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Processing your receipt',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'We\'re extracting the merchant, amount, date, and category. This usually takes a few seconds.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
              color: cs.onSurface.withValues(alpha: 0.5),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 5,
              child: LinearProgressIndicator(
                value: null,
                backgroundColor: cs.primary.withValues(
                  alpha: isDark ? 0.1 : 0.08,
                ),
                color: cs.primary.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
