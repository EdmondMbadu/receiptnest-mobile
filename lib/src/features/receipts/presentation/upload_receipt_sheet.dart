import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/public_app_config.dart';
import '../data/receipt_repository.dart';
import '../models/receipt.dart';

class UploadReceiptSheet extends ConsumerStatefulWidget {
  const UploadReceiptSheet({
    super.key,
    required this.userId,
    required this.repository,
    required this.onUploaded,
  });

  final String userId;
  final ReceiptRepository repository;
  final ValueChanged<Receipt> onUploaded;

  @override
  ConsumerState<UploadReceiptSheet> createState() => _UploadReceiptSheetState();
}

class _UploadReceiptSheetState extends ConsumerState<UploadReceiptSheet> {
  static const Set<String> _previewableImageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  UploadFileData? _selectedFile;
  bool _uploading = false;
  double _progress = 0;
  String? _error;

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
          return 'Camera access is denied. Enable it in Settings to scan receipts.';
        case 'photo_access_denied':
        case 'photo_access_denied_without_prompt':
          return 'Photo access is denied. Enable it in Settings to choose images.';
        case 'invalid_image':
          return 'The selected image could not be read. Please try another file.';
        default:
          break;
      }
    }

    return isCamera
        ? 'Could not open camera. Please check camera permissions and try again.'
        : 'Could not open photo library. Please check permissions and try again.';
  }

  Future<void> _pickFromCamera() async {
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

      setState(() {
        _selectedFile = UploadFileData(
          name: image.name,
          path: image.path,
          sizeBytes: sizeBytes,
          mimeType: _mimeTypeFromFileName(image.name, fallback: 'image/jpeg'),
        );
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyPickerError(error, isCamera: true);
      });
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );
      if (image == null) return;

      final sizeBytes = await File(image.path).length();
      if (!mounted) return;

      setState(() {
        _selectedFile = UploadFileData(
          name: image.name,
          path: image.path,
          sizeBytes: sizeBytes,
          mimeType: _mimeTypeFromFileName(image.name, fallback: 'image/jpeg'),
        );
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyPickerError(error, isCamera: false);
      });
    }
  }

  Future<void> _pickDocument() async {
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

      setState(() {
        _selectedFile = UploadFileData(
          name: file.name,
          path: file.path,
          bytes: file.path == null ? file.bytes : null,
          sizeBytes: file.size,
          mimeType: null,
        );
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not open file picker. Please try again.';
      });
    }
  }

  Future<void> _upload() async {
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

    try {
      final uploaded = await widget.repository.uploadReceipt(
        userId: widget.userId,
        file: file,
        appConfig: appConfig,
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _progress = value);
        },
      );

      if (!mounted) return;
      widget.onUploaded(uploaded);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = _selectedFile;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Upload Receipt',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _SourceButton(
                      icon: Icons.camera_alt_outlined,
                      label: 'Camera',
                      onTap: _uploading ? null : _pickFromCamera,
                      cs: cs,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SourceButton(
                      icon: Icons.photo_library_outlined,
                      label: 'Gallery',
                      onTap: _uploading ? null : _pickFromGallery,
                      cs: cs,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SourceButton(
                      icon: Icons.description_outlined,
                      label: 'Files',
                      onTap: _uploading ? null : _pickDocument,
                      cs: cs,
                      isDark: isDark,
                    ),
                  ),
                ],
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
                            fit: BoxFit.cover,
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
                  'Uploading ${(100 * _progress).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _uploading || selected == null ? null : _upload,
                child: _uploading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Upload receipt'),
              ),
            ],
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
