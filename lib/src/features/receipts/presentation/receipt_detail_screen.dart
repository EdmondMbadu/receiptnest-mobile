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
          content: const Text('Are you sure you want to delete this receipt? This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
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
    final receiptAsync = ref.watch(receiptFutureProvider(widget.receiptId));

    return Scaffold(
      appBar: AppBar(title: const Text('Receipt Detail')),
      body: receiptAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load receipt: $err')),
        data: (receipt) {
          if (receipt == null) {
            return const Center(child: Text('Receipt not found.'));
          }

          _loadForm(receipt);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  title: Text(receipt.file.originalName),
                  subtitle: Text('${formatCurrency(receipt.totalAmount)} • ${formatDate(receipt.effectiveDate)}'),
                  leading: Icon(receipt.isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined),
                  trailing: IconButton(
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => _openFile(receipt),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _merchantController,
                decoration: const InputDecoration(labelText: 'Merchant'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _dateController,
                decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
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
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : () => _save(receipt),
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving...' : 'Save changes'),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _delete(receipt),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete receipt'),
              ),
            ],
          );
        },
      ),
    );
  }
}
