import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../core/utils/formatters.dart';
import '../../auth/data/auth_repository.dart';
import '../data/receipt_repository.dart';
import '../models/category.dart';
import '../models/receipt.dart';

class ReceiptDetailScreen extends ConsumerStatefulWidget {
  const ReceiptDetailScreen({
    super.key,
    required this.receiptId,
  });

  final String receiptId;

  @override
  ConsumerState<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends ConsumerState<ReceiptDetailScreen> {
  final _merchantController = TextEditingController();
  final _amountController = TextEditingController();
  final _dateController = TextEditingController();
  final _notesController = TextEditingController();

  String _categoryId = 'other';
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _merchantController.dispose();
    _amountController.dispose();
    _dateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _loadForm(Receipt receipt) {
    if (_loaded) return;
    _merchantController.text =
        receipt.merchant?.canonicalName ?? receipt.extraction?.supplierName?.value?.toString() ?? '';
    _amountController.text = receipt.totalAmount?.toString() ?? receipt.extraction?.totalAmount?.value?.toString() ?? '';
    _dateController.text = receipt.date ?? receipt.extraction?.date?.value?.toString() ?? '';
    _notesController.text = receipt.notes ?? '';
    _categoryId = receipt.category?.id ?? 'other';
    _loaded = true;
  }

  Future<void> _save(Receipt receipt) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final amount = double.tryParse(_amountController.text.trim());
      final category = categoryById(_categoryId);

      final updates = <String, dynamic>{
        'merchant': {
          'canonicalName': _merchantController.text.trim(),
          'rawName': receipt.merchant?.rawName ?? _merchantController.text.trim(),
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

      await ref.read(receiptRepositoryProvider).updateReceipt(uid, receipt.id, updates);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt updated.')),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete(Receipt receipt) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete receipt'),
          content: const Text('Are you sure? This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await ref.read(receiptRepositoryProvider).deleteReceipt(uid, receipt);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _openFile(Receipt receipt) async {
    try {
      final url = await ref.read(receiptRepositoryProvider).getReceiptFileUrl(receipt.file.storagePath);
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open file: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final receiptAsync = ref.watch(receiptFutureProvider(widget.receiptId));

    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: receiptAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load receipt: $err')),
        data: (receipt) {
          if (receipt == null) {
            return const Center(child: Text('Receipt not found.'));
          }

          _loadForm(receipt);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // File info card
              Card(
                child: InkWell(
                  onTap: () => _openFile(receipt),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            receipt.isPdf
                                ? Icons.picture_as_pdf_outlined
                                : Icons.image_outlined,
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
                                receipt.file.originalName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${formatCurrency(receipt.totalAmount)} \u2022 ${formatDate(receipt.effectiveDate)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 20,
                          color: cs.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Form card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Details',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _merchantController,
                        decoration: const InputDecoration(
                          labelText: 'Merchant',
                          prefixIcon: Icon(Icons.store_outlined, size: 20),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          prefixIcon: Icon(Icons.attach_money_rounded, size: 20),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _dateController,
                        decoration: const InputDecoration(
                          labelText: 'Date (YYYY-MM-DD)',
                          prefixIcon: Icon(Icons.calendar_today_outlined, size: 20),
                        ),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: _categoryId,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          prefixIcon: Icon(Icons.category_outlined, size: 20),
                        ),
                        items: defaultCategories
                            .map((category) => DropdownMenuItem<String>(
                                  value: category.id,
                                  child: Text('${category.icon} ${category.name}'),
                                ))
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
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          prefixIcon: Padding(
                            padding: EdgeInsets.only(bottom: 40),
                            child: Icon(Icons.notes_outlined, size: 20),
                          ),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: cs.error, fontSize: 13),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : () => _save(receipt),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded, size: 20),
                label: Text(_saving ? 'Saving...' : 'Save changes'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _delete(receipt),
                icon: Icon(Icons.delete_outline, size: 20, color: cs.error),
                label: Text(
                  'Delete receipt',
                  style: TextStyle(color: cs.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: cs.error.withValues(alpha: 0.3)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
