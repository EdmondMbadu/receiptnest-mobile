import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/receipt_repository.dart';
import '../models/receipt.dart';

class UploadReceiptSheet extends StatefulWidget {
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
  State<UploadReceiptSheet> createState() => _UploadReceiptSheetState();
}

class _UploadReceiptSheetState extends State<UploadReceiptSheet> {
  UploadFileData? _selectedFile;
  bool _uploading = false;
  double _progress = 0;
  String? _error;

  Future<void> _pickFromCamera() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 92);
    if (image == null) return;

    final bytes = await image.readAsBytes();
    if (!mounted) return;

    setState(() {
      _selectedFile = UploadFileData(
        name: image.name,
        path: image.path,
        bytes: bytes,
        sizeBytes: bytes.length,
        mimeType: 'image/jpeg',
      );
      _error = null;
    });
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (image == null) return;

    final bytes = await image.readAsBytes();
    if (!mounted) return;

    setState(() {
      _selectedFile = UploadFileData(
        name: image.name,
        path: image.path,
        bytes: bytes,
        sizeBytes: bytes.length,
        mimeType: 'image/jpeg',
      );
      _error = null;
    });
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'pdf', 'doc', 'docx'],
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (!mounted) return;

    setState(() {
      _selectedFile = UploadFileData(
        name: file.name,
        path: file.path,
        bytes: file.bytes,
        sizeBytes: file.size,
        mimeType: null,
      );
      _error = null;
    });
  }

  Future<void> _upload() async {
    final file = _selectedFile;
    if (file == null) return;

    final validation = widget.repository.validateFile(file);
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
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedFile;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Upload Receipt',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _uploading ? null : _pickFromCamera,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Camera'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _uploading ? null : _pickFromGallery,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Gallery'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _uploading ? null : _pickDocument,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Files'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (selected != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selected.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text('${(selected.sizeBytes / 1024).toStringAsFixed(1)} KB'),
                        const SizedBox(height: 8),
                        if (selected.path != null &&
                            (selected.name.toLowerCase().endsWith('.jpg') ||
                                selected.name.toLowerCase().endsWith('.jpeg') ||
                                selected.name.toLowerCase().endsWith('.png') ||
                                selected.name.toLowerCase().endsWith('.webp')))
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(selected.path!),
                              height: 180,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          )
                        else
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.insert_drive_file_outlined),
                            title: Text('Preview unavailable for this file type'),
                          ),
                      ],
                    ),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              if (_uploading) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _progress == 0 ? null : _progress),
                const SizedBox(height: 6),
                Text('Uploading ${(100 * _progress).toStringAsFixed(0)}%'),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _uploading || selected == null ? null : _upload,
                child: Text(_uploading ? 'Uploading...' : 'Upload receipt'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
