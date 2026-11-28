import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/data/auth_repository.dart';
import '../data/receipt_file_preview.dart';
import '../data/receipt_repository.dart';
import '../models/receipt.dart';
import '../models/receipt_file_label.dart';

Future<void> openReceiptOriginal(BuildContext context, Receipt receipt) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => ReceiptOriginalScreen(receipt: receipt),
      ),
    );

// Actual document names can help identify a file. Generated picker labels add
// no information above the receipt itself, so omit them from the viewer.
String? _meaningfulFileName(Receipt receipt) {
  final name = receipt.file.originalName.trim();
  return name.isNotEmpty && receiptFileLabel(name) == name ? name : null;
}

class ReceiptFilePreview extends ConsumerWidget {
  const ReceiptFilePreview({super.key, required this.receipt});
  final Receipt receipt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(currentUserIdProvider) != receipt.userId) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    final fileName = _meaningfulFileName(receipt);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 8, fileName == null ? 8 : 0),
            child: Row(
              children: [
                Icon(
                  receiptPreviewKind(receipt) == ReceiptPreviewKind.pdf
                      ? Icons.picture_as_pdf_outlined
                      : Icons.image_outlined,
                  color: cs.primary,
                  size: 21,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Original receipt',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'View full receipt',
                  onPressed: () => openReceiptOriginal(context, receipt),
                  icon: const Icon(Icons.open_in_full_rounded, size: 20),
                ),
              ],
            ),
          ),
          if (fileName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          SizedBox(
            height: (MediaQuery.sizeOf(context).height * 0.5).clamp(
              280.0,
              460.0,
            ),
            child: _ReceiptOriginalBody(receipt: receipt, fullScreen: false),
          ),
        ],
      ),
    );
  }
}

class ReceiptOriginalScreen extends ConsumerWidget {
  const ReceiptOriginalScreen({super.key, required this.receipt});
  final Receipt receipt;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(currentUserIdProvider) == receipt.userId;
    final fileName = _meaningfulFileName(receipt);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Original receipt'),
        leading: IconButton(
          tooltip: 'Close receipt',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: active
          ? SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (fileName != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Text(
                        fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  Expanded(
                    child: _ReceiptOriginalBody(
                      receipt: receipt,
                      fullScreen: true,
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _ReceiptOriginalBody extends ConsumerWidget {
  const _ReceiptOriginalBody({required this.receipt, required this.fullScreen});
  final Receipt receipt;
  final bool fullScreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(currentUserIdProvider) != receipt.userId) {
      return const SizedBox.shrink();
    }
    final kind = receiptPreviewKind(receipt);
    if (kind == ReceiptPreviewKind.unsupported) {
      return _PreviewNotice(
        message: 'This file type can’t be displayed here yet.',
        onOriginal: () => _openExternal(context, ref),
      );
    }
    final bytes = ref.watch(
      receiptPreviewBytesProvider(receipt.file.storagePath),
    );
    void retry() =>
        ref.invalidate(receiptPreviewBytesProvider(receipt.file.storagePath));
    return bytes.when(
      loading: () => const _PreviewLoading(),
      error: (_, _) => _PreviewNotice(
        message:
            'We couldn’t load your original. Check your connection and try again.',
        onRetry: retry,
        onOriginal: () => _openExternal(context, ref),
      ),
      data: (data) => kind == ReceiptPreviewKind.pdf
          ? _NativeReceiptPdf(
              key: ValueKey(data),
              bytes: data,
              fullScreen: fullScreen,
              opener: ref.watch(receiptPdfOpenerProvider),
              onOriginal: () => _openExternal(context, ref),
              onExpand: () => openReceiptOriginal(context, receipt),
            )
          : _ReceiptImage(
              key: ValueKey(data),
              bytes: data,
              fullScreen: fullScreen,
              onRetry: retry,
              onOriginal: () => _openExternal(context, ref),
              onExpand: () => openReceiptOriginal(context, receipt),
            ),
    );
  }

  Future<void> _openExternal(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid != receipt.userId) return;
    try {
      final url = await ref.read(
        receiptFileUrlProvider(receipt.file.storagePath).future,
      );
      if (!context.mounted || ref.read(currentUserIdProvider) != uid) return;
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Preserve a usable retry state rather than throwing out of the viewer.
    }
    if (!context.mounted || ref.read(currentUserIdProvider) != uid) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Couldn’t open the original file. Please try again.'),
      ),
    );
  }
}

class _NativeReceiptPdf extends StatefulWidget {
  const _NativeReceiptPdf({
    super.key,
    required this.bytes,
    required this.fullScreen,
    required this.opener,
    required this.onOriginal,
    required this.onExpand,
  });
  final Uint8List bytes;
  final bool fullScreen;
  final Future<PdfDocument> Function(Uint8List) opener;
  final VoidCallback onOriginal;
  final VoidCallback onExpand;
  @override
  State<_NativeReceiptPdf> createState() => _NativeReceiptPdfState();
}

class _NativeReceiptPdfState extends State<_NativeReceiptPdf> {
  PdfDocument? _document;
  Uint8List? _image;
  int _page = 1;
  int _requested = 1;
  bool _busy = true;
  bool _error = false;
  Future<void> _work = Future.value();

  @override
  void initState() {
    super.initState();
    _work = _open();
  }

  Future<void> _open() async {
    try {
      final document = await widget.opener(widget.bytes);
      if (!mounted) {
        await document.close();
        return;
      }
      _document = document;
      if (document.pagesCount < 1) throw StateError('Empty PDF');
      await _render(_requested);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _render(int number) async {
    PdfPage? page;
    try {
      page = await _document!.getPage(number);
      if (!mounted) return;
      if (!page.width.isFinite ||
          !page.height.isFinite ||
          page.width <= 0 ||
          page.height <= 0) {
        throw StateError('Invalid page dimensions');
      }
      // Bound decoding to one page and at most eight megapixels. Very long
      // receipts preserve their aspect ratio instead of allocating huge images.
      final scale = math.min(
        (widget.fullScreen ? 2048 : 1200) / page.width,
        4096 / page.height,
      );
      final image = await page.render(
        width: math.max(1, page.width * scale),
        height: math.max(1, page.height * scale),
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      if (image == null || image.bytes.isEmpty) throw StateError('Empty page');
      if (mounted) {
        setState(() {
          _image = image.bytes;
          _page = number;
          _error = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      try {
        await page?.close();
      } catch (_) {
        /* Native cleanup must not crash a closing screen. */
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(int number) {
    if (_busy) return;
    _requested = number;
    setState(() {
      _busy = true;
      _error = false;
    });
    _work = _document == null ? _open() : _render(number);
  }

  @override
  void dispose() {
    // Android permits only one open page per document. Wait for rendering and
    // its page cleanup to finish before releasing the native document.
    unawaited(
      _work.then((_) async {
        try {
          await _document?.close();
        } catch (_) {
          /* Already released. */
        }
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _document?.pagesCount ?? 0;
    return Column(
      children: [
        Expanded(
          child: _error
              ? _PreviewNotice(
                  message:
                      'We couldn’t display this PDF. Try again or open the original file.',
                  onRetry: () => _show(_requested),
                  onOriginal: widget.onOriginal,
                )
              : _image == null
              ? const _PreviewLoading()
              : Stack(
                  children: [
                    Positioned.fill(
                      child: _ReceiptImage(
                        key: ValueKey(_image),
                        bytes: _image!,
                        fullScreen: widget.fullScreen,
                        onRetry: () => _show(_page),
                        onOriginal: widget.onOriginal,
                        onExpand: widget.onExpand,
                      ),
                    ),
                    if (_busy)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Color(0x80FFFFFF),
                          child: _PreviewLoading(),
                        ),
                      ),
                  ],
                ),
        ),
        if (count > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: _busy || _page <= 1 ? null : () => _show(_page - 1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Flexible(
                child: Text(
                  'Page $_page of $count',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed: _busy || _page >= count
                    ? null
                    : () => _show(_page + 1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
      ],
    );
  }
}

class _ReceiptImage extends StatefulWidget {
  const _ReceiptImage({
    super.key,
    required this.bytes,
    required this.fullScreen,
    required this.onRetry,
    required this.onOriginal,
    required this.onExpand,
  });
  final Uint8List bytes;
  final bool fullScreen;
  final VoidCallback onRetry;
  final VoidCallback onOriginal;
  final VoidCallback onExpand;
  @override
  State<_ReceiptImage> createState() => _ReceiptImageState();
}

class _ReceiptImageState extends State<_ReceiptImage> {
  final _transform = TransformationController();
  late final ImageProvider _image;
  Offset _tap = Offset.zero;
  @override
  void initState() {
    super.initState();
    _image = ResizeImage(
      MemoryImage(widget.bytes),
      width: widget.fullScreen ? 2048 : 1200,
      height: 4096,
      policy: ResizeImagePolicy.fit,
    );
  }

  @override
  void dispose() {
    _transform.dispose();
    unawaited(_image.evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = Image(
      image: _image,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Original receipt',
      frameBuilder: (context, child, frame, synchronous) =>
          frame != null || synchronous
          ? child
          : const Center(
              child: Text(
                'Opening your receipt…',
                style: TextStyle(fontSize: 13),
              ),
            ),
      errorBuilder: (_, _, _) => _PreviewNotice(
        message: 'We couldn’t display this image.',
        onRetry: widget.onRetry,
        onOriginal: widget.onOriginal,
      ),
    );
    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF202026)
                : const Color(0xFFF0F1F3),
            child: widget.fullScreen
                ? GestureDetector(
                    onDoubleTapDown: (details) => _tap = details.localPosition,
                    onDoubleTap: () => _transform.value =
                        _transform.value.getMaxScaleOnAxis() > 1.1
                        ? Matrix4.identity()
                        : (Matrix4.diagonal3Values(2.5, 2.5, 1)
                            ..setTranslationRaw(
                              -_tap.dx * 1.5,
                              -_tap.dy * 1.5,
                              0,
                            )),
                    child: InteractiveViewer(
                      transformationController: _transform,
                      minScale: 1,
                      maxScale: 6,
                      child: SizedBox.expand(child: image),
                    ),
                  )
                : Semantics(
                    button: true,
                    label: 'Enlarge receipt',
                    child: InkWell(
                      onTap: widget.onExpand,
                      child: SizedBox.expand(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: image,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        if (widget.fullScreen)
          Row(
            children: [
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Pinch or double-tap to zoom',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              IconButton(
                tooltip: 'Fit receipt',
                onPressed: () => _transform.value = Matrix4.identity(),
                icon: const Icon(Icons.fit_screen_rounded, size: 21),
              ),
              const SizedBox(width: 8),
            ],
          ),
      ],
    );
  }
}

class _PreviewLoading extends StatelessWidget {
  const _PreviewLoading();
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(height: 12),
        Text('Opening your receipt…', style: TextStyle(fontSize: 13)),
      ],
    ),
  );
}

class _PreviewNotice extends StatelessWidget {
  const _PreviewNotice({
    required this.message,
    this.onRetry,
    required this.onOriginal,
  });
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback onOriginal;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.receipt_long_outlined, size: 28),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('Try again'),
            ),
          ],
          TextButton(
            onPressed: onOriginal,
            child: const Text('Open original file'),
          ),
        ],
      ),
    ),
  );
}
