import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../receipts/data/receipt_repository.dart';
import '../../receipts/models/category.dart';
import '../../receipts/models/receipt.dart';
import '../models/category_period_filter.dart';

final categoryExportServiceProvider = Provider<CategoryExportService>((ref) {
  return CategoryExportService(
    receiptRepository: ref.watch(receiptRepositoryProvider),
  );
});

class CategoryExportException implements Exception {
  const CategoryExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CategoryExportService {
  CategoryExportService({required ReceiptRepository receiptRepository})
    : _receiptRepository = receiptRepository;

  final ReceiptRepository _receiptRepository;

  static final DateFormat _csvDateFormat = DateFormat('yyyy-MM-dd');

  Future<void> exportCsv({
    required ExpenseCategory category,
    required CategoryTimeRange range,
    required String? selectedPeriodKey,
    required List<Receipt> receipts,
  }) async {
    if (receipts.isEmpty) {
      throw const CategoryExportException(
        'No receipts available to export for this period.',
      );
    }

    final fileName = buildFileName(
      category: category,
      range: range,
      selectedPeriodKey: selectedPeriodKey,
      extension: 'csv',
    );
    final csv = buildCsv(category: category, receipts: receipts);
    final file = await _writeTextFile(fileName, csv);

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: 'text/csv')],
        subject: '${category.name} tax export',
      ),
    );
  }

  Future<void> exportPdf({
    required ExpenseCategory category,
    required CategoryTimeRange range,
    required String? selectedPeriodKey,
    required List<Receipt> receipts,
  }) async {
    if (receipts.isEmpty) {
      throw const CategoryExportException(
        'No receipts available to export for this period.',
      );
    }

    final document = PdfDocument();
    document.pageSettings.margins.all = 0;
    document.documentInformation.title = '${category.name} tax export';

    try {
      for (final receipt in receipts) {
        final bytes = await _receiptRepository.getReceiptFileBytes(
          receipt.file.storagePath,
        );
        if (bytes == null || bytes.isEmpty) {
          throw const CategoryExportException(
            'A receipt file could not be loaded for export.',
          );
        }

        if (receipt.isPdf) {
          _appendPdfReceipt(document, bytes);
          continue;
        }

        await _appendImageReceipt(document, bytes);
      }

      final fileName = buildFileName(
        category: category,
        range: range,
        selectedPeriodKey: selectedPeriodKey,
        extension: 'pdf',
      );
      final file = await _writeBytesFile(fileName, document.saveSync());

      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'application/pdf')],
          subject: '${category.name} tax export',
        ),
      );
    } on CategoryExportException {
      rethrow;
    } catch (_) {
      throw const CategoryExportException(
        'We could not generate this PDF export. Please try again.',
      );
    } finally {
      document.dispose();
    }
  }

  static String buildFileName({
    required ExpenseCategory category,
    required CategoryTimeRange range,
    required String? selectedPeriodKey,
    required String extension,
  }) {
    final baseName = categoryExportBaseName(
      category,
      range: range,
      selectedPeriodKey: selectedPeriodKey,
    );
    return '$baseName.$extension';
  }

  static String buildCsv({
    required ExpenseCategory category,
    required List<Receipt> receipts,
  }) {
    final rows = <List<String>>[
      const <String>['Category', 'Merchant', 'Date', 'Amount'],
    ];
    var total = 0.0;

    for (final receipt in receipts) {
      final amount = receipt.effectiveTotalAmount ?? 0;
      total += amount;
      rows.add(<String>[
        category.name,
        _merchantName(receipt),
        _csvDate(receipt.effectiveDate),
        amount.toStringAsFixed(2),
      ]);
    }

    rows.add(<String>['Total', '', '', total.toStringAsFixed(2)]);
    return rows.map(_csvRow).join('\n');
  }

  static String _merchantName(Receipt receipt) {
    return receipt.merchant?.canonicalName ??
        receipt.merchant?.rawName ??
        receipt.extraction?.supplierName?.value?.toString() ??
        receipt.file.originalName;
  }

  static String _csvDate(DateTime? date) {
    if (date == null) return '';
    return _csvDateFormat.format(date);
  }

  static String _csvRow(List<String> fields) {
    return fields.map((field) => '"${field.replaceAll('"', '""')}"').join(',');
  }

  void _appendPdfReceipt(PdfDocument document, Uint8List bytes) {
    final source = PdfDocument(inputBytes: bytes);
    try {
      for (var index = 0; index < source.pages.count; index++) {
        final sourcePage = source.pages[index];
        document.pageSettings = PdfPageSettings(sourcePage.size);
        document.pageSettings.margins.all = 0;
        final page = document.pages.add();
        page.graphics.drawPdfTemplate(
          sourcePage.createTemplate(),
          ui.Offset.zero,
          sourcePage.size,
        );
      }
    } finally {
      source.dispose();
    }
  }

  Future<void> _appendImageReceipt(
    PdfDocument document,
    Uint8List bytes,
  ) async {
    final decoded = await _decodeImage(bytes);
    final orientation = decoded.width >= decoded.height
        ? PdfPageOrientation.landscape
        : PdfPageOrientation.portrait;

    document.pageSettings = PdfPageSettings(PdfPageSize.a4, orientation);
    document.pageSettings.margins.all = 0;

    final page = document.pages.add();
    final pageWidth = page.getClientSize().width;
    final pageHeight = page.getClientSize().height;
    const padding = 16.0;
    final availableWidth = pageWidth - (padding * 2);
    final availableHeight = pageHeight - (padding * 2);
    final scale = _min(
      availableWidth / decoded.width,
      availableHeight / decoded.height,
    );
    final targetWidth = decoded.width * scale;
    final targetHeight = decoded.height * scale;
    final left = (pageWidth - targetWidth) / 2;
    final top = (pageHeight - targetHeight) / 2;

    page.graphics.drawImage(
      PdfBitmap(decoded.pngBytes),
      ui.Rect.fromLTWH(left, top, targetWidth, targetHeight),
    );
  }

  Future<_DecodedImage> _decodeImage(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final pngData = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (pngData == null) {
        throw const CategoryExportException(
          'A receipt image could not be prepared for PDF export.',
        );
      }
      return _DecodedImage(
        pngBytes: pngData.buffer.asUint8List(),
        width: frame.image.width.toDouble(),
        height: frame.image.height.toDouble(),
      );
    } catch (_) {
      final image = PdfBitmap(bytes);
      return _DecodedImage(
        pngBytes: bytes,
        width: image.width.toDouble(),
        height: image.height.toDouble(),
      );
    }
  }

  Future<File> _writeTextFile(String fileName, String contents) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(contents, encoding: utf8, flush: true);
    return file;
  }

  Future<File> _writeBytesFile(String fileName, List<int> bytes) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  double _min(double a, double b) => a < b ? a : b;
}

class _DecodedImage {
  const _DecodedImage({
    required this.pngBytes,
    required this.width,
    required this.height,
  });

  final Uint8List pngBytes;
  final double width;
  final double height;
}
