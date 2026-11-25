import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';

import '../../auth/data/auth_repository.dart';
import '../models/receipt.dart';
import 'receipt_repository.dart';

enum ReceiptPreviewKind { image, pdf, unsupported }

ReceiptPreviewKind receiptPreviewKind(Receipt receipt) {
  final mime = receipt.file.mimeType.toLowerCase().split(';').first.trim();
  final extension = receipt.file.originalName.toLowerCase().split('.').last;
  if (mime == 'application/pdf' || extension == 'pdf') {
    return ReceiptPreviewKind.pdf;
  }
  if (mime.startsWith('image/') ||
      const {
        'jpg',
        'jpeg',
        'png',
        'webp',
        'heic',
        'heif',
        'gif',
      }.contains(extension)) {
    return ReceiptPreviewKind.image;
  }
  return ReceiptPreviewKind.unsupported;
}

const receiptPreviewMaxBytes = 50 * 1024 * 1024;

// Fetch the original directly from Firebase Storage using the current session.
// Share one in-memory download between the inline and full-screen views; release
// it after the last viewer closes. Never pass private document URLs to a viewer
// hosted by another service.
final receiptPreviewBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, path) async {
      final uid = ref.watch(currentUserIdProvider);
      if (uid == null || !path.startsWith('users/$uid/')) {
        throw StateError('Receipt is unavailable');
      }
      final bytes = await ref
          .watch(receiptRepositoryProvider)
          .getReceiptFileBytes(path, maxSizeBytes: receiptPreviewMaxBytes)
          .timeout(const Duration(seconds: 30));
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Receipt file is empty');
      }
      return bytes;
    });

// A seam for testing renderer failures and closing a viewer during native work.
final receiptPdfOpenerProvider =
    Provider<Future<PdfDocument> Function(Uint8List)>(
      (ref) =>
          (bytes) => PdfDocument.openData(bytes),
    );
