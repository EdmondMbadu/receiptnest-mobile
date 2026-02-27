import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_utils.dart';

class ReceiptStatuses {
  static const uploaded = 'uploaded';
  static const processing = 'processing';
  static const extracted = 'extracted';
  static const needsReview = 'needs_review';
  static const finalStatus = 'final';

  static const values = <String>{
    uploaded,
    processing,
    extracted,
    needsReview,
    finalStatus,
  };
}

class ExtractionField<T> {
  const ExtractionField({
    required this.value,
    required this.confidence,
    this.rawText,
  });

  final T value;
  final double confidence;
  final String? rawText;

  static ExtractionField<dynamic>? fromMap(dynamic input) {
    if (input is! Map<String, dynamic>) return null;
    final value = input['value'];
    if (value == null) return null;

    return ExtractionField<dynamic>(
      value: value,
      confidence: ((input['confidence'] as num?) ?? 0).toDouble(),
      rawText: input['rawText'] as String?,
    );
  }
}

class ReceiptExtraction {
  const ReceiptExtraction({
    this.source,
    this.processedAt,
    this.totalAmount,
    this.currency,
    this.date,
    this.supplierName,
    this.overallConfidence,
    this.rawResponse,
  });

  final String? source;
  final DateTime? processedAt;
  final ExtractionField<dynamic>? totalAmount;
  final ExtractionField<dynamic>? currency;
  final ExtractionField<dynamic>? date;
  final ExtractionField<dynamic>? supplierName;
  final double? overallConfidence;
  final String? rawResponse;

  static ReceiptExtraction? fromMap(dynamic input) {
    if (input is! Map<String, dynamic>) return null;
    return ReceiptExtraction(
      source: input['source'] as String?,
      processedAt: asDateTime(input['processedAt']),
      totalAmount: ExtractionField.fromMap(input['totalAmount']),
      currency: ExtractionField.fromMap(input['currency']),
      date: ExtractionField.fromMap(input['date']),
      supplierName: ExtractionField.fromMap(input['supplierName']),
      overallConfidence: (input['overallConfidence'] as num?)?.toDouble(),
      rawResponse: input['rawResponse'] as String?,
    );
  }
}

class ReceiptMerchant {
  const ReceiptMerchant({
    this.canonicalId,
    required this.canonicalName,
    required this.rawName,
    required this.matchConfidence,
    required this.matchedBy,
  });

  final String? canonicalId;
  final String canonicalName;
  final String rawName;
  final double matchConfidence;
  final String matchedBy;

  factory ReceiptMerchant.fromMap(Map<String, dynamic> data) {
    return ReceiptMerchant(
      canonicalId: data['canonicalId'] as String?,
      canonicalName: (data['canonicalName'] as String?) ?? '',
      rawName: (data['rawName'] as String?) ?? '',
      matchConfidence: ((data['matchConfidence'] as num?) ?? 0).toDouble(),
      matchedBy: (data['matchedBy'] as String?) ?? 'manual',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'canonicalId': canonicalId,
      'canonicalName': canonicalName,
      'rawName': rawName,
      'matchConfidence': matchConfidence,
      'matchedBy': matchedBy,
    };
  }
}

class ReceiptCategory {
  const ReceiptCategory({
    required this.id,
    required this.name,
    required this.confidence,
    required this.assignedBy,
  });

  final String id;
  final String name;
  final double confidence;
  final String assignedBy;

  factory ReceiptCategory.fromMap(Map<String, dynamic> data) {
    return ReceiptCategory(
      id: (data['id'] as String?) ?? 'other',
      name: (data['name'] as String?) ?? 'Other',
      confidence: ((data['confidence'] as num?) ?? 0).toDouble(),
      assignedBy: (data['assignedBy'] as String?) ?? 'default',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'confidence': confidence,
      'assignedBy': assignedBy,
    };
  }
}

class ReceiptFile {
  const ReceiptFile({
    required this.storagePath,
    required this.originalName,
    required this.mimeType,
    required this.sizeBytes,
    this.uploadedAt,
  });

  final String storagePath;
  final String originalName;
  final String mimeType;
  final int sizeBytes;
  final DateTime? uploadedAt;

  factory ReceiptFile.fromMap(Map<String, dynamic> data) {
    return ReceiptFile(
      storagePath: (data['storagePath'] as String?) ?? '',
      originalName: (data['originalName'] as String?) ?? '',
      mimeType: (data['mimeType'] as String?) ?? '',
      sizeBytes: (data['sizeBytes'] as num?)?.toInt() ?? 0,
      uploadedAt: asDateTime(data['uploadedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'storagePath': storagePath,
      'originalName': originalName,
      'mimeType': mimeType,
      'sizeBytes': sizeBytes,
      'uploadedAt': FieldValue.serverTimestamp(),
    };
  }
}

class Receipt {
  const Receipt({
    required this.id,
    required this.userId,
    required this.status,
    required this.file,
    this.extraction,
    this.merchant,
    this.category,
    this.totalAmount,
    this.currency,
    this.date,
    this.notes,
    this.tags = const [],
    this.createdAt,
    this.updatedAt,
    this.source,
  });

  final String id;
  final String userId;
  final String status;
  final ReceiptFile file;
  final ReceiptExtraction? extraction;
  final ReceiptMerchant? merchant;
  final ReceiptCategory? category;
  final double? totalAmount;
  final String? currency;
  final String? date;
  final String? notes;
  final List<String> tags;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? source;

  factory Receipt.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};

    return Receipt(
      id: doc.id,
      userId: (data['userId'] as String?) ?? '',
      status: (data['status'] as String?) ?? ReceiptStatuses.uploaded,
      file: ReceiptFile.fromMap((data['file'] as Map<String, dynamic>?) ?? const {}),
      extraction: ReceiptExtraction.fromMap(data['extraction']),
      merchant: data['merchant'] is Map<String, dynamic>
          ? ReceiptMerchant.fromMap(data['merchant'] as Map<String, dynamic>)
          : null,
      category: data['category'] is Map<String, dynamic>
          ? ReceiptCategory.fromMap(data['category'] as Map<String, dynamic>)
          : null,
      totalAmount: (data['totalAmount'] as num?)?.toDouble(),
      currency: data['currency'] as String?,
      date: data['date'] as String?,
      notes: data['notes'] as String?,
      tags: (data['tags'] as List<dynamic>? ?? const []).whereType<String>().toList(),
      createdAt: asDateTime(data['createdAt']),
      updatedAt: asDateTime(data['updatedAt']),
      source: data['source'] as String?,
    );
  }

  DateTime? get effectiveDate {
    if (date != null) {
      final parsed = DateTime.tryParse(date!);
      if (parsed != null) return parsed;
    }
    return createdAt;
  }

  bool get isPdf =>
      file.mimeType == 'application/pdf' || file.originalName.toLowerCase().endsWith('.pdf');
}
