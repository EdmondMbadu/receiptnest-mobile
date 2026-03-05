import 'dart:async';

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
  String? _success;

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
        receipt.effectiveTotalAmount?.toString() ??
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
      _success = null;
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
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

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
                child: Icon(Icons.warning_amber_rounded,
                    size: 20, color: cs.error),
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
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final extension = _fileExtension(receipt);
    final isPdf =
        extension == 'pdf' ||
        receipt.file.mimeType.toLowerCase() == 'application/pdf';
    final useGoogleViewer = isPdf || extension == 'doc' || extension == 'docx';

    return FutureBuilder<String>(
      future: ref
          .read(receiptRepositoryProvider)
          .getReceiptFileUrl(receipt.file.storagePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF151520) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.grey.shade200,
              ),
            ),
            height: 260,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: cs.primary,
              ),
            ),
          );
        }

        if (snapshot.hasError ||
            snapshot.data == null ||
            snapshot.data!.isEmpty) {
          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF151520) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.grey.shade200,
              ),
            ),
            child: _InlinePreviewError(
              message: 'Could not load in-app preview.',
              onOpenExternally: null,
            ),
          );
        }

        final fileUrl = snapshot.data!;

        Widget previewContent;
        if (_isImagePreviewable(receipt)) {
          previewContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.image_outlined,
                          size: 16, color: cs.primary),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Preview',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 300,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
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
                              strokeWidth: 2.5,
                              color: cs.primary,
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
              const SizedBox(height: 16),
            ],
          );
        } else if (_isDocumentPreviewable(receipt)) {
          previewContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.description_outlined,
                          size: 16, color: cs.primary),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Preview',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 380,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _InAppDocumentPreview(
                      fileUrl: fileUrl,
                      startWithGoogleViewer: useGoogleViewer,
                      onOpenExternally: () => _openUrlExternally(fileUrl),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
        } else {
          previewContent = _InlinePreviewError(
            message: 'This file type does not support in-app preview yet.',
            onOpenExternally: () => _openUrlExternally(fileUrl),
          );
        }

        return Container(
          clipBehavior: Clip.antiAlias,
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
          child: previewContent,
        );
      },
    );
  }

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
    final receiptAsync = ref.watch(receiptFutureProvider(widget.receiptId));

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D0D14) : const Color(0xFFF6F7F9),
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
      body: receiptAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: cs.primary,
          ),
        ),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: cs.error.withValues(alpha: 0.5)),
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
                  Icon(Icons.receipt_long_outlined,
                      size: 48,
                      color: cs.onSurface.withValues(alpha: 0.15)),
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

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
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
                                  receipt.file.originalName,
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
                                    color:
                                        cs.onSurface.withValues(alpha: 0.45),
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
                              Icons.open_in_new_rounded,
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
                          child: Icon(Icons.edit_note_rounded,
                              size: 18, color: cs.primary),
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
                        prefixIcon: Icon(Icons.store_outlined,
                            size: 20,
                            color: cs.onSurface.withValues(alpha: 0.4)),
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
                      decoration: InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category_outlined,
                            size: 20,
                            color: cs.onSurface.withValues(alpha: 0.4)),
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
                      decoration: InputDecoration(
                        labelText: 'Notes',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(bottom: 40),
                          child: Icon(Icons.notes_outlined,
                              size: 20,
                              color: cs.onSurface.withValues(alpha: 0.4)),
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
                  onPressed: _saving ? null : () => _save(receipt),
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
                    _saving ? 'Saving...' : 'Save changes',
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
                  onPressed: _saving ? null : () => _delete(receipt),
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
  Timer? _loadingTimeout;

  Uri _googleViewerUri(String url) {
    return Uri.parse(
      'https://docs.google.com/gview?embedded=1&url=${Uri.encodeComponent(url)}',
    );
  }

  Future<void> _loadUrl({required bool useGoogleViewer}) async {
    _loadingTimeout?.cancel();
    _usingGoogleViewer = useGoogleViewer;
    _error = null;
    setState(() => _loading = true);

    final uri = useGoogleViewer
        ? _googleViewerUri(widget.fileUrl)
        : Uri.parse(widget.fileUrl);
    await _controller.loadRequest(uri);

    _loadingTimeout = Timer(const Duration(seconds: 10), () {
      if (!mounted || !_loading) return;

      if (!_usingGoogleViewer) {
        _loadUrl(useGoogleViewer: true);
        return;
      }

      setState(() {
        _loading = false;
        _error = 'In-app preview timed out.';
      });
    });
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
            _loadingTimeout?.cancel();
            if (!mounted) return;
            setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            _loadingTimeout?.cancel();
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
  void dispose() {
    _loadingTimeout?.cancel();
    super.dispose();
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
        if (_loading)
          Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
      ],
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
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.2),
        ),
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
                backgroundColor:
                    cs.primary.withValues(alpha: isDark ? 0.1 : 0.08),
                color: cs.primary.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.visibility_off_outlined,
                color: cs.onSurface.withValues(alpha: 0.35),
                size: 24,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (onOpenExternally != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onOpenExternally,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Open in browser'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.grey.shade300,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
