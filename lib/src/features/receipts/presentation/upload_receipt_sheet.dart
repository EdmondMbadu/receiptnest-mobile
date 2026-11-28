import '../models/receipt_file_label.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/public_app_config.dart';
import '../data/receipt_repository.dart';
import '../data/receipt_upload_activity.dart';
import '../../auth/data/auth_repository.dart';
import 'receipt_upload_outcome.dart';
import 'receipt_upload_result.dart';
import 'receipt_upload_batch.dart';
import '../models/receipt.dart';
import '../../getting_started/data/onboarding_analytics.dart';
import '../../getting_started/presentation/onboarding_widgets.dart';

enum ReceiptSource { camera, gallery, file }

final receiptImagePickerProvider = Provider<ImagePicker>(
  (ref) => ImagePicker(),
);

class UploadReceiptSheet extends ConsumerStatefulWidget {
  const UploadReceiptSheet({
    super.key,
    required this.userId,
    required this.repository,
    required this.onUploaded,
    this.initialSource,
    this.guided = false,
    this.onFileSelected,
  });

  final String userId;
  final ReceiptRepository repository;
  final ValueChanged<Receipt> onUploaded;
  final ReceiptSource? initialSource;
  final bool guided;
  final ValueChanged<UploadFileData>? onFileSelected;

  @override
  ConsumerState<UploadReceiptSheet> createState() => _UploadReceiptSheetState();
}

class _UploadReceiptSheetState extends ConsumerState<UploadReceiptSheet> {
  final List<ReceiptUploadItem> _items = [];
  UploadFileData? get _selectedFile => _items.firstOrNull?.file;
  bool _batch = false;
  bool _batchFinished = false;
  bool get _sameAccount =>
      mounted && ref.read(currentUserIdProvider) == widget.userId;
  Receipt? _uploaded;
  bool _uploading = false;
  bool _isFirstUpload = false;
  bool _picking = false;
  bool _closingForAccountChange = false;
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (widget.initialSource) {
        case ReceiptSource.camera:
          _pickFromCamera();
        case ReceiptSource.gallery:
          _pickFromGallery();
        case ReceiptSource.file:
          _pickDocument();
        case null:
          break;
      }
    });
  }

  void _selected(List<UploadFileData> files, String source) {
    if (!_sameAccount || files.isEmpty) return;
    setState(() {
      if (widget.guided) _items.clear();
      for (final file in widget.guided ? files.take(1) : files) {
        // Only deduplicate an identical local selection. Different files with
        // the same name/size must remain independently uploadable.
        if (_items.any(
          (item) => file.path != null
              ? item.file.path == file.path
              : item.file.name == file.name &&
                    item.file.sizeBytes == file.sizeBytes &&
                    listEquals(item.file.bytes, file.bytes),
        )) {
          continue;
        }
        _items.add(ReceiptUploadItem(file: file, id: const Uuid().v4()));
      }
      _error = null;
    });
    if (widget.guided) widget.onFileSelected?.call(_items.single.file);
    ref.read(onboardingAnalyticsProvider).event('native_receipt_selected', {
      'source': source,
      'guided': widget.guided ? 1 : 0,
      'file_count': files.length,
    });
  }

  void _reset() => setState(() {
    _items.clear();
    _uploaded = null;
    _batch = false;
    _batchFinished = false;
    _error = null;
    _progress = 0;
  });

  String _fileExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  String _mimeTypeFromFileName(String fileName, {required String fallback}) {
    switch (_fileExtension(fileName)) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      default:
        return fallback;
    }
  }

  String _friendlyPickerError(Object error, {required bool isCamera}) {
    if (error is PlatformException) {
      switch (error.code) {
        case 'camera_access_denied':
        case 'camera_access_denied_without_prompt':
          return 'Camera access is denied. Enable it in Settings, or choose a photo or file instead.';
        case 'photo_access_denied':
        case 'photo_access_denied_without_prompt':
          return 'Photo access is denied. Enable it in Settings, or choose a file instead.';
        case 'invalid_image':
          return 'The selected image could not be read. Please try another file.';
        case 'camera_unavailable':
          return 'This device has no camera available. Choose a photo or file instead.';
        default:
          break;
      }
    }

    return isCamera
        ? 'Could not open camera. Please check camera permissions and try again.'
        : 'Could not open photo library. Please check permissions and try again.';
  }

  Future<void> _pickFromCamera() async {
    if (_picking || _uploading) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picker = ref.read(receiptImagePickerProvider);
      final image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (image == null) return;

      final sizeBytes = await image.length();
      if (!mounted) return;

      _selected([
        UploadFileData(
          name: image.name,
          path: image.path,
          sizeBytes: sizeBytes,
          mimeType: _mimeTypeFromFileName(image.name, fallback: 'image/jpeg'),
        ),
      ], 'camera');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyPickerError(error, isCamera: true);
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_picking || _uploading) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picker = ref.read(receiptImagePickerProvider);
      final images = widget.guided
          ? [
              await picker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 92,
              ),
            ].nonNulls.toList()
          : await picker.pickMultiImage(imageQuality: 92);
      final files = <UploadFileData>[];
      for (final image in images) {
        if (!_sameAccount) return;
        files.add(
          UploadFileData(
            name: image.name,
            path: image.path,
            sizeBytes: await image.length(),
            mimeType: _mimeTypeFromFileName(image.name, fallback: 'image/jpeg'),
          ),
        );
      }
      _selected(files, 'gallery');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyPickerError(error, isCamera: false);
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickDocument() async {
    if (_picking || _uploading) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final appConfig =
          ref.read(publicAppConfigProvider).valueOrNull ??
          const PublicAppConfig();
      final result = await FilePicker.platform.pickFiles(
        withData: kIsWeb,
        allowMultiple: !widget.guided,
        type: FileType.custom,
        allowedExtensions: appConfig.uploadAllowedExtensions,
      );

      if (result == null || result.files.isEmpty) return;

      if (!_sameAccount) return;
      _selected([
        for (final file in result.files)
          UploadFileData(
            name: file.name,
            path: file.path,
            bytes: file.path == null ? file.bytes : null,
            sizeBytes: file.size,
            mimeType: null,
          ),
      ], 'file');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not open file picker. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _upload() async {
    if (_uploading || _picking || !_sameAccount || _items.isEmpty) return;
    final pending = _items.where((item) => item.receipt == null).toList();
    if (pending.isEmpty) return;
    if (!_batchFinished) {
      _isFirstUpload =
          ref.read(receiptsStreamProvider).asData?.value.isEmpty == true;
    }
    final appConfig =
        ref.read(publicAppConfigProvider).valueOrNull ??
        const PublicAppConfig();
    final batch = _batch || _items.length > 1;
    // Validate every file, preserving invalid files alongside successful ones.
    for (final item in pending) {
      final validation = widget.repository.validateFile(
        item.file,
        appConfig: appConfig,
      );
      item.error = validation.valid ? null : validation.error;
      item.progress = 0;
    }
    if (!batch && pending.single.error != null) {
      setState(() => _error = pending.single.error);
      return;
    }
    setState(() {
      _batch = batch;
      _batchFinished = false;
      _uploading = true;
      _error = null;
      _progress = 0;
    });
    // Serialize transfers so the existing free-plan count check observes each
    // accepted receipt. Extraction starts independently as soon as each saves.
    for (final item in pending) {
      if (!_sameAccount) break;
      if (item.error != null) continue;
      final elapsed = Stopwatch()..start();
      int? firstProgressMs;
      int? fileTransferredMs;
      setState(() => item.uploading = true);
      ref.read(onboardingAnalyticsProvider).event('native_upload_start', {
        'guided': widget.guided ? 1 : 0,
        'batch_size': _items.length,
      });
      try {
        final uploaded = await widget.repository.uploadReceipt(
          userId: widget.userId,
          file: item.file,
          uploadId: item.id,
          appConfig: appConfig,
          onProgress: (value) {
            if (!_sameAccount) return;
            if (value > 0) firstProgressMs ??= elapsed.elapsedMilliseconds;
            if (value >= 1) fileTransferredMs ??= elapsed.elapsedMilliseconds;
            setState(() {
              item.progress = value.clamp(0, 1).toDouble();
              _progress = item.progress;
            });
          },
        );
        if (!_sameAccount) break;
        final first =
            _isFirstUpload && !_items.any((entry) => entry.receipt != null);
        setState(() {
          item.receipt = uploaded;
          item.first = first;
          item.uploading = false;
        });
        ref
            .read(receiptUploadActivityProvider.notifier)
            .track(uploaded, guided: widget.guided, first: first);
        ref.read(onboardingAnalyticsProvider).event('native_upload_accepted', {
          'guided': widget.guided ? 1 : 0,
          'elapsed_ms': elapsed.elapsedMilliseconds,
          if (firstProgressMs != null) 'first_progress_ms': firstProgressMs!,
          if (fileTransferredMs != null)
            'file_transferred_ms': fileTransferredMs!,
          'file_kind': uploaded.isPdf ? 'pdf' : 'image',
        });
        widget.onUploaded(uploaded);
      } catch (error) {
        if (!_sameAccount) break;
        ref.read(onboardingAnalyticsProvider).event('native_upload_error', {
          'guided': widget.guided ? 1 : 0,
        });
        final message = error.toString().replaceFirst('Exception: ', '');
        setState(() {
          item.uploading = false;
          item.error = message.startsWith('Free plan')
              ? message
              : 'Couldn’t save this file. Check your connection and try again.';
          if (!batch) {
            _error = error is FirebaseException
                ? 'We couldn’t save your receipt. Check your connection and try again. Your selected file is still here.'
                : item.error;
          }
        });
        if (message.startsWith('Free plan')) {
          // Remaining files cannot pass the same limit. Keep them selected and
          // avoid an unnecessary server round trip for each one.
          for (final remaining
              in pending.skipWhile((entry) => entry != item).skip(1)) {
            remaining.error ??= message;
          }
          break;
        }
      }
    }
    if (!_sameAccount) return;
    setState(() {
      _uploading = false;
      _batchFinished = batch;
      if (!batch) _uploaded = _items.single.receipt;
    });
    if (mounted && widget.guided && _uploaded != null) {
      Navigator.of(context).pop();
    }
  }

  Widget _uploadProgress() {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 19,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _progress >= 1
                          ? 'Saving your receipt'
                          : 'Uploading your receipt',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ReceiptUploadPreview(file: _selectedFile, height: 140),
              const SizedBox(height: 22),
              Text(
                'On its way.',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Keep this screen open while we save your file.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _progress >= 1 ? 'Finishing the save…' : 'Uploading',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_progress > 0 && _progress < 1)
                    Text(
                      '${(100 * _progress).round()}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: _progress <= 0 || _progress >= 1 ? null : _progress,
                minHeight: 5,
                borderRadius: BorderRadius.circular(8),
              ),
            ],
          ),
        ),
      ),
    );
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
      return const PopScope(canPop: true, child: SizedBox.shrink());
    }
    if (_uploaded != null) {
      return ReceiptUploadOutcome(
        key: ValueKey(_uploaded!.id),
        userId: widget.userId,
        first: _isFirstUpload,
        receiptId: _uploaded!.id,
        seed: _uploaded,
        file: _selectedFile,
        onAnother: _reset,
      );
    }
    if (_batch && (_uploading || _batchFinished)) {
      return ReceiptUploadBatch(
        userId: widget.userId,
        items: _items,
        uploading: _uploading,
        onRetry: _upload,
        onAnother: _reset,
        onRemove: (item) => setState(() {
          _items.remove(item);
          if (_items.isEmpty) {
            _batch = false;
            _batchFinished = false;
          }
        }),
      );
    }
    if (_uploading) return _uploadProgress();
    final cs = Theme.of(context).colorScheme;
    final selected = _selectedFile;
    final single = _items.length == 1;
    return SafeArea(
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
                                widget.guided
                                    ? selected == null
                                          ? 'Add your receipt'
                                          : 'Looking good?'
                                    : 'Add receipts',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              tooltip: 'Close upload',
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.guided
                              ? selected == null
                                    ? 'Take a photo, or choose a receipt you already have.'
                                    : 'Make sure the whole receipt is visible and the text is readable.'
                              : _items.isEmpty
                              ? 'One or several. Choose what you have.'
                              : single
                              ? '1 file selected'
                              : '${_items.length} files selected',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (selected == null || !widget.guided)
                          Row(
                            children: [
                              for (final source in ReceiptSource.values) ...[
                                if (source != ReceiptSource.camera)
                                  const SizedBox(width: 10),
                                Expanded(
                                  child: _SourceButton(
                                    icon: switch (source) {
                                      ReceiptSource.camera =>
                                        Icons.camera_alt_outlined,
                                      ReceiptSource.gallery =>
                                        Icons.photo_library_outlined,
                                      ReceiptSource.file =>
                                        Icons.description_outlined,
                                    },
                                    label: switch (source) {
                                      ReceiptSource.camera => 'Camera',
                                      ReceiptSource.gallery => 'Gallery',
                                      ReceiptSource.file => 'Files',
                                    },
                                    hint: widget.guided
                                        ? null
                                        : source == ReceiptSource.camera
                                        ? 'Take a photo'
                                        : 'One or more',
                                    onTap: _picking
                                        ? null
                                        : switch (source) {
                                            ReceiptSource.camera =>
                                              _pickFromCamera,
                                            ReceiptSource.gallery =>
                                              _pickFromGallery,
                                            ReceiptSource.file => _pickDocument,
                                          },
                                    cs: cs,
                                    isDark:
                                        Theme.of(context).brightness ==
                                        Brightness.dark,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        if (_picking)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        if (selected != null) const SizedBox(height: 20),
                        if (single)
                          Stack(
                            children: [
                              ReceiptUploadPreview(file: selected, height: 150),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: IconButton(
                                  tooltip:
                                      'Remove ${receiptFileLabel(selected!.name)}',
                                  onPressed: _picking
                                      ? null
                                      : () => setState(() {
                                          _items.clear();
                                          _error = null;
                                        }),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  if (_items.length > 1)
                    SliverList.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return ReceiptSelectionTile(
                          file: item.file,
                          receiptNumber: index + 1,
                          onRemove: _picking
                              ? null
                              : () => setState(() {
                                  _items.remove(item);
                                  _error = null;
                                }),
                        );
                      },
                    ),
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        if (widget.guided && selected != null)
                          TextButton(
                            onPressed: _picking ? null : _reset,
                            child: const Text('Choose another receipt'),
                          ),
                        if (!widget.guided)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: TextButton.icon(
                              onPressed: _picking
                                  ? null
                                  : () {
                                      final router = GoRouter.of(context);
                                      Navigator.of(context).pop();
                                      router.push('/app/forward-email');
                                    },
                              icon: const Icon(
                                Icons.mail_outline_rounded,
                                size: 19,
                              ),
                              label: const Text('Forward an email'),
                            ),
                          ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 8),
                            child: OnboardingMessage(
                              message: _error!,
                              error: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _picking || selected == null ? null : _upload,
              child: Text(
                _error != null && selected != null
                    ? 'Try upload again'
                    : _items.length > 1
                    ? 'Upload ${_items.length} files'
                    : selected == null && !widget.guided
                    ? 'Upload receipts'
                    : 'Upload receipt',
              ),
            ),
            if (!widget.guided && selected != null) ...[
              const SizedBox(height: 10),
              Text(
                'We’ll organize the details.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.cs,
    required this.isDark,
    this.hint,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final VoidCallback? onTap;
  final ColorScheme cs;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.grey.shade300,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon, color: cs.primary, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 5),
                Text(
                  hint!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
