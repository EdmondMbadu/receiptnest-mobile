import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/utils/formatters.dart';
import '../../auth/data/auth_repository.dart';
import '../data/receipt_repository.dart';
import '../models/category.dart';
import '../models/receipt.dart';

const _previewImageExtensions = <String>{
  'jpg',
  'jpeg',
  'png',
  'webp',
  'heic',
  'heif',
};

const _previewDocExtensions = <String>{'pdf', 'doc', 'docx'};

class ReceiptDetailScreen extends ConsumerStatefulWidget {
  const ReceiptDetailScreen({super.key, required this.receiptId});

  final String receiptId;

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
        receipt.merchant?.canonicalName ??
        receipt.extraction?.supplierName?.value?.toString() ??
        '';
    _amountController.text =
        receipt.totalAmount?.toString() ??
        receipt.extraction?.totalAmount?.value?.toString() ??
        '';
    _dateController.text =
        receipt.date ?? receipt.extraction?.date?.value?.toString() ?? '';
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Receipt updated.')));
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
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
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

  Future<void> _openUrlExternally(String url) async {
    await launchUrlString(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _openFile(Receipt receipt) async {
    try {
      final url = await ref
          .read(receiptRepositoryProvider)
          .getReceiptFileUrl(receipt.file.storagePath);
      await _openUrlExternally(url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open file: $e')));
    }
  }

  String _fileExtension(Receipt receipt) {
    final parts = receipt.file.originalName.toLowerCase().split('.');
    if (parts.length < 2) return '';
    return parts.last;
  }

  bool _isImagePreviewable(Receipt receipt) {
    final mime = receipt.file.mimeType.toLowerCase();
    if (mime.startsWith('image/')) return true;
    return _previewImageExtensions.contains(_fileExtension(receipt));
  }

  bool _isDocumentPreviewable(Receipt receipt) {
    final extension = _fileExtension(receipt);
    final mime = receipt.file.mimeType.toLowerCase();
    if (_previewDocExtensions.contains(extension)) return true;
    if (mime == 'application/pdf') return true;
    if (mime.contains('msword')) return true;
    if (mime.contains('officedocument.wordprocessingml.document')) return true;
    return false;
  }

  Widget _buildPreviewCard(Receipt receipt) {
    final extension = _fileExtension(receipt);
    final useGoogleViewer = extension == 'doc' || extension == 'docx';

    return FutureBuilder<String>(
      future: ref
          .read(receiptRepositoryProvider)
          .getReceiptFileUrl(receipt.file.storagePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: SizedBox(
              height: 260,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError ||
            snapshot.data == null ||
            snapshot.data!.isEmpty) {
          return Card(
            child: _InlinePreviewError(
              message: 'Could not load in-app preview.',
              onOpenExternally: null,
            ),
          );
        }

        final fileUrl = snapshot.data!;
        if (_isImagePreviewable(receipt)) {
          return Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Text(
                    'Preview',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 300,
                  child: Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 5,
                      child: Center(
                        child: CachedNetworkImage(
                          imageUrl: fileUrl,
                          fit: BoxFit.contain,
                          progressIndicatorBuilder: (context, url, progress) {
                            return Center(
                              child: CircularProgressIndicator(
                                value: progress.progress,
                              ),
                            );
                          },
                          errorWidget: (context, url, error) {
                            return _InlinePreviewError(
                              message: 'Image preview is unavailable in-app.',
                              onOpenExternally: () =>
                                  _openUrlExternally(fileUrl),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        if (_isDocumentPreviewable(receipt)) {
          return Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Text(
                    'Preview',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 380,
                  child: _InAppDocumentPreview(
                    fileUrl: fileUrl,
                    startWithGoogleViewer: useGoogleViewer,
                    onOpenExternally: () => _openUrlExternally(fileUrl),
                  ),
                ),
              ],
            ),
          );
        }

        return Card(
          child: _InlinePreviewError(
            message: 'This file type does not support in-app preview yet.',
            onOpenExternally: () => _openUrlExternally(fileUrl),
          ),
        );
      },
    );
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
                                '${formatCurrency(receipt.totalAmount)} • ${formatDate(receipt.effectiveDate)}',
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
              _buildPreviewCard(receipt),
              const SizedBox(height: 8),

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
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          prefixIcon: Icon(
                            Icons.attach_money_rounded,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _dateController,
                        decoration: const InputDecoration(
                          labelText: 'Date (YYYY-MM-DD)',
                          prefixIcon: Icon(
                            Icons.calendar_today_outlined,
                            size: 20,
                          ),
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
                            .map(
                              (category) => DropdownMenuItem<String>(
                                value: category.id,
                                child: Text(
                                  '${category.icon} ${category.name}',
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
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
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

class _InAppDocumentPreview extends StatefulWidget {
  const _InAppDocumentPreview({
    required this.fileUrl,
    required this.startWithGoogleViewer,
    required this.onOpenExternally,
  });

  final String fileUrl;
  final bool startWithGoogleViewer;
  final VoidCallback onOpenExternally;

  @override
  State<_InAppDocumentPreview> createState() => _InAppDocumentPreviewState();
}

class _InAppDocumentPreviewState extends State<_InAppDocumentPreview> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _usingGoogleViewer = false;
  String? _error;

  Uri _googleViewerUri(String url) {
    return Uri.parse(
      'https://docs.google.com/gview?embedded=1&url=${Uri.encodeComponent(url)}',
    );
  }

  Future<void> _loadUrl({required bool useGoogleViewer}) async {
    _usingGoogleViewer = useGoogleViewer;
    _error = null;
    setState(() => _loading = true);

    final uri = useGoogleViewer
        ? _googleViewerUri(widget.fileUrl)
        : Uri.parse(widget.fileUrl);
    await _controller.loadRequest(uri);
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _error = null;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true) return;
            if (!_usingGoogleViewer) {
              _loadUrl(useGoogleViewer: true);
              return;
            }
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = 'Could not render this file in-app.';
            });
          },
        ),
      );

    _loadUrl(useGoogleViewer: widget.startWithGoogleViewer);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _InlinePreviewError(
        message: _error!,
        onOpenExternally: widget.onOpenExternally,
      );
    }

    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}

class _InlinePreviewError extends StatelessWidget {
  const _InlinePreviewError({
    required this.message,
    required this.onOpenExternally,
  });

  final String message;
  final VoidCallback? onOpenExternally;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.visibility_off_outlined,
              color: cs.onSurface.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65)),
            ),
            if (onOpenExternally != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onOpenExternally,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Open in browser'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
