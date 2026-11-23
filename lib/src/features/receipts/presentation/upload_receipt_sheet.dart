import 'dart:io';

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
import '../models/receipt.dart';
import '../../getting_started/data/onboarding_analytics.dart';
import '../../getting_started/presentation/onboarding_widgets.dart';

enum ReceiptSource { camera, gallery, file }

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
  static const Set<String> _previewableImageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
  };

  UploadFileData? _selectedFile;
  Receipt? _uploaded;
  bool _uploading = false;
  bool _isFirstUpload = false;
  bool _picking = false;
  bool _closingForAccountChange = false;
  double _progress = 0;
  String? _error;
  String _uploadId = const Uuid().v4();

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

  void _selected(UploadFileData file, String source) {
    setState(() {
      _selectedFile = file;
      _uploadId = const Uuid().v4();
      _error = null;
    });
    widget.onFileSelected?.call(file);
    ref.read(onboardingAnalyticsProvider).event('native_receipt_selected', {
      'source': source,
      'guided': widget.guided ? 1 : 0,
    });
  }

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

  bool _isPreviewableImage(UploadFileData file) {
    return file.path != null &&
        _previewableImageExtensions.contains(_fileExtension(file.name));
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
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (image == null) return;

      final sizeBytes = await File(image.path).length();
      if (!mounted) return;

      _selected(
        UploadFileData(
          name: image.name,
          path: image.path,
          sizeBytes: sizeBytes,
          mimeType: _mimeTypeFromFileName(image.name, fallback: 'image/jpeg'),
        ),
        'camera',
      );
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
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );
      if (image == null) return;

      final sizeBytes = await File(image.path).length();
      if (!mounted) return;

      _selected(
        UploadFileData(
          name: image.name,
          path: image.path,
          sizeBytes: sizeBytes,
          mimeType: _mimeTypeFromFileName(image.name, fallback: 'image/jpeg'),
        ),
        'gallery',
      );
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
        type: FileType.custom,
        allowedExtensions: appConfig.uploadAllowedExtensions,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (!mounted) return;

      _selected(
        UploadFileData(
          name: file.name,
          path: file.path,
          bytes: file.path == null ? file.bytes : null,
          sizeBytes: file.size,
          mimeType: null,
        ),
        'file',
      );
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
    if (_uploading ||
        _picking ||
        ref.read(currentUserIdProvider) != widget.userId) {
      return;
    }
    _isFirstUpload =
        ref.read(receiptsStreamProvider).asData?.value.isEmpty == true;
    final elapsed = Stopwatch()..start();
    int? firstProgressMs;
    int? fileTransferredMs;
    final file = _selectedFile;
    if (file == null) return;
    final appConfig =
        ref.read(publicAppConfigProvider).valueOrNull ??
        const PublicAppConfig();

    final validation = widget.repository.validateFile(
      file,
      appConfig: appConfig,
    );
    if (!validation.valid) {
      setState(() => _error = validation.error);
      return;
    }

    setState(() {
      _uploading = true;
      _error = null;
      _progress = 0;
    });
    ref.read(onboardingAnalyticsProvider).event('native_upload_start', {
      'guided': widget.guided ? 1 : 0,
    });

    try {
      final uploaded = await widget.repository.uploadReceipt(
        userId: widget.userId,
        file: file,
        uploadId: _uploadId,
        appConfig: appConfig,
        onProgress: (value) {
          if (!mounted) return;
          if (value > 0) firstProgressMs ??= elapsed.elapsedMilliseconds;
          if (value >= 1) fileTransferredMs ??= elapsed.elapsedMilliseconds;
          setState(() => _progress = value.clamp(0, 1).toDouble());
        },
      );

      if (!mounted) return;
      if (ref.read(currentUserIdProvider) != widget.userId) return;
      ref
          .read(receiptUploadActivityProvider.notifier)
          .track(uploaded, guided: widget.guided, first: _isFirstUpload);
      ref.read(onboardingAnalyticsProvider).event('native_upload_accepted', {
        'guided': widget.guided ? 1 : 0,
        'elapsed_ms': elapsed.elapsedMilliseconds,
        if (firstProgressMs != null) 'first_progress_ms': firstProgressMs!,
        if (fileTransferredMs != null)
          'file_transferred_ms': fileTransferredMs!,
        'file_kind': uploaded.isPdf ? 'pdf' : 'image',
      });
      widget.onUploaded(uploaded);
      if (!mounted) return;
      if (widget.guided) {
        Navigator.of(context).pop();
      } else {
        setState(() => _uploaded = uploaded);
      }
    } catch (e) {
      if (!mounted || ref.read(currentUserIdProvider) != widget.userId) return;
      ref.read(onboardingAnalyticsProvider).event('native_upload_error', {
        'guided': widget.guided ? 1 : 0,
      });
      if (!mounted) return;
      setState(() {
        final message = e.toString().replaceFirst('Exception: ', '');
        _error = e is FirebaseException
            ? 'We couldn’t save your receipt. Check your connection and try again. Your selected file is still here.'
            : message.startsWith('Free plan')
            ? message
            : 'We couldn’t upload this receipt. Please try again or choose another file.';
      });
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
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
        onAnother: () => setState(() {
          _uploaded = null;
          _selectedFile = null;
          _error = null;
          _progress = 0;
          _uploadId = const Uuid().v4();
        }),
      );
    }
    if (_uploading) return _uploadProgress();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = _selectedFile;

    return PopScope(
      canPop: !_uploading,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        selected == null ? 'Add your receipt' : 'Looking good?',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      onPressed: _uploading
                          ? null
                          : () => Navigator.of(context).pop(),
                      tooltip: 'Close upload',
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  selected == null
                      ? 'Take a photo, or choose a receipt you already have.'
                      : 'Make sure the whole receipt is visible and the text is readable.',
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
                ),
                const SizedBox(height: 16),
                if (selected == null || !widget.guided)
                  Row(
                    children: [
                      Expanded(
                        child: _SourceButton(
                          icon: Icons.camera_alt_outlined,
                          label: 'Camera',
                          onTap: _uploading || _picking
                              ? null
                              : _pickFromCamera,
                          cs: cs,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SourceButton(
                          icon: Icons.photo_library_outlined,
                          label: 'Gallery',
                          onTap: _uploading || _picking
                              ? null
                              : _pickFromGallery,
                          cs: cs,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SourceButton(
                          icon: Icons.description_outlined,
                          label: 'Files',
                          onTap: _uploading || _picking ? null : _pickDocument,
                          cs: cs,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                if (selected == null && !widget.guided)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton.icon(
                      onPressed: _uploading || _picking
                          ? null
                          : () {
                              final router = GoRouter.of(context);
                              Navigator.of(context).pop();
                              router.push('/app/forward-email');
                            },
                      icon: const Icon(Icons.mail_outline_rounded, size: 19),
                      label: const Text('Forward an email'),
                    ),
                  ),
                const SizedBox(height: 16),
                if (selected != null)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isPreviewableImage(selected))
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(15),
                            ),
                            child: Image.file(
                              File(selected.path!),
                              height: 180,
                              width: double.infinity,
                              fit: BoxFit.contain,
                              errorBuilder: (_, error, stack) => const SizedBox(
                                height: 100,
                                child: Center(
                                  child: Icon(
                                    Icons.description_outlined,
                                    size: 36,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            height: 80,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.06),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(15),
                              ),
                            ),
                            child: Icon(
                              Icons.insert_drive_file_outlined,
                              size: 36,
                              color: cs.primary.withValues(alpha: 0.4),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      selected.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${(selected.sizeBytes / 1024).toStringAsFixed(1)} KB',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurface.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!_uploading)
                                IconButton(
                                  onPressed: () =>
                                      setState(() => _selectedFile = null),
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 20,
                                    color: cs.onSurface.withValues(alpha: 0.4),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  OnboardingMessage(message: _error!, error: true),
                ],
                if (_uploading) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _progress == 0 ? null : _progress,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _progress >= 1
                        ? 'Saving your receipt…'
                        : 'Uploading ${(100 * _progress).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _uploading || _picking || selected == null
                      ? null
                      : _upload,
                  child: _uploading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _error != null && selected != null
                              ? 'Try upload again'
                              : 'Upload receipt',
                        ),
                ),
                if (selected != null && !_uploading)
                  TextButton(
                    onPressed: () => setState(() {
                      _selectedFile = null;
                      _error = null;
                    }),
                    child: const Text('Choose another receipt'),
                  ),
              ],
            ),
          ),
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
  });

  final IconData icon;
  final String label;
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
            ],
          ),
        ),
      ),
    );
  }
}
