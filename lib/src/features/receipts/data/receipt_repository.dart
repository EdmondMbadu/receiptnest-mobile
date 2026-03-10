import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/firestore_utils.dart';
import '../../auth/data/auth_repository.dart';
import '../models/monthly_summary.dart';
import '../models/receipt.dart';

const maxFileSizeBytes = 10 * 1024 * 1024;

const allowedFileMimeTypes = <String>{
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
  'application/pdf',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
};

const allowedFileExtensions = <String>{
  'jpg',
  'jpeg',
  'png',
  'webp',
  'heic',
  'heif',
  'pdf',
  'doc',
  'docx',
};

final receiptRepositoryProvider = Provider<ReceiptRepository>((ref) {
  return ReceiptRepository(
    db: ref.watch(firestoreProvider),
    storage: FirebaseStorage.instance,
    functions: ref.watch(functionsProvider),
  );
});

final receiptsStreamProvider = StreamProvider<List<Receipt>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream.value(const []);
  }
  return ref.watch(receiptRepositoryProvider).watchReceipts(uid);
});

final receiptFileUrlProvider = FutureProvider.family<String, String>((
  ref,
  storagePath,
) {
  return ref.watch(receiptRepositoryProvider).getReceiptFileUrl(storagePath);
});

final selectedMonthProvider = StateProvider<int>((ref) => DateTime.now().month);
final selectedYearProvider = StateProvider<int>((ref) => DateTime.now().year);

final selectedMonthLabelProvider = Provider<String>((ref) {
  final month = ref.watch(selectedMonthProvider);
  final year = ref.watch(selectedYearProvider);
  return DateFormat('MMMM y').format(DateTime(year, month, 1));
});

final selectedMonthReceiptsProvider = Provider<List<Receipt>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  final year = ref.watch(selectedYearProvider);
  final receipts = ref.watch(receiptsStreamProvider).valueOrNull ?? const [];

  return receipts.where((receipt) {
    final date = receipt.effectiveDate;
    if (date == null) return false;
    return date.month == month && date.year == year;
  }).toList();
});

final selectedMonthSpendProvider = Provider<double>((ref) {
  final receipts = ref.watch(selectedMonthReceiptsProvider);
  return receipts.fold<double>(
    0,
    (runningTotal, r) => runningTotal + (r.effectiveTotalAmount ?? 0),
  );
});

final selectedMonthReceiptCountProvider = Provider<int>((ref) {
  return ref.watch(selectedMonthReceiptsProvider).length;
});

final previousMonthSpendProvider = Provider<double>((ref) {
  final month = ref.watch(selectedMonthProvider);
  final year = ref.watch(selectedYearProvider);
  final receipts = ref.watch(receiptsStreamProvider).valueOrNull ?? const [];

  final previous = DateTime(year, month - 1, 1);
  return receipts
      .where((receipt) {
        final date = receipt.effectiveDate;
        if (date == null) return false;
        return date.month == previous.month && date.year == previous.year;
      })
      .fold<double>(
        0,
        (runningTotal, r) => runningTotal + (r.effectiveTotalAmount ?? 0),
      );
});

final monthOverMonthChangeProvider = Provider<MonthOverMonthChange?>((ref) {
  final current = ref.watch(selectedMonthSpendProvider);
  final previous = ref.watch(previousMonthSpendProvider);

  if (previous == 0) return null;
  final delta = ((current - previous) / previous) * 100;
  return MonthOverMonthChange(
    percent: delta.abs().round(),
    isIncrease: delta > 0,
  );
});

final dailySpendingDataProvider = Provider<List<DailySpendingPoint>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  final year = ref.watch(selectedYearProvider);
  final receipts = ref.watch(selectedMonthReceiptsProvider);

  final daysInMonth = DateTime(year, month + 1, 0).day;
  final totals = List<double>.filled(daysInMonth, 0);

  for (final receipt in receipts) {
    final amount = receipt.effectiveTotalAmount;
    final date = receipt.effectiveDate;
    if (amount == null || date == null) continue;
    if (date.day >= 1 && date.day <= daysInMonth) {
      totals[date.day - 1] += amount;
    }
  }

  var cumulative = 0.0;
  return List.generate(daysInMonth, (index) {
    cumulative += totals[index];
    return DailySpendingPoint(
      day: index + 1,
      amount: totals[index],
      cumulative: cumulative,
      pointDate: DateTime(year, month, index + 1),
    );
  });
});

final receiptByIdProvider = Provider.family<Receipt?, String>((ref, id) {
  final receipts = ref.watch(receiptsStreamProvider).valueOrNull ?? const [];
  for (final receipt in receipts) {
    if (receipt.id == id) return receipt;
  }
  return null;
});

final receiptFutureProvider = FutureProvider.family<Receipt?, String>((
  ref,
  id,
) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;

  final fromCache = ref.watch(receiptByIdProvider(id));
  if (fromCache != null) {
    return fromCache;
  }

  return ref.watch(receiptRepositoryProvider).getReceipt(uid, id);
});

class MonthOverMonthChange {
  const MonthOverMonthChange({required this.percent, required this.isIncrease});

  final int percent;
  final bool isIncrease;
}

class DailySpendingPoint {
  const DailySpendingPoint({
    required this.day,
    required this.amount,
    required this.cumulative,
    required this.pointDate,
  });

  final int day;
  final double amount;
  final double cumulative;
  final DateTime pointDate;
}

class UploadFileData {
  const UploadFileData({
    required this.name,
    required this.sizeBytes,
    this.mimeType,
    this.bytes,
    this.path,
  });

  final String name;
  final String? mimeType;
  final int sizeBytes;
  final Uint8List? bytes;
  final String? path;
}

class UploadValidationResult {
  const UploadValidationResult({required this.valid, this.error});

  final bool valid;
  final String? error;
}

class ReceiptRepository {
  ReceiptRepository({
    required FirebaseFirestore db,
    required FirebaseStorage storage,
    required FirebaseFunctions functions,
  }) : _db = db,
       _storage = storage,
       _functions = functions;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;

  Stream<List<Receipt>> watchReceipts(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('receipts')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Receipt.fromSnapshot).toList());
  }

  Future<Receipt?> getReceipt(String userId, String receiptId) async {
    final snapshot = await _db
        .collection('users')
        .doc(userId)
        .collection('receipts')
        .doc(receiptId)
        .get();

    if (!snapshot.exists) return null;
    return Receipt.fromSnapshot(snapshot);
  }

  UploadValidationResult validateFile(UploadFileData file) {
    final ext = file.name.split('.').last.toLowerCase();
    final mime = (file.mimeType ?? '').toLowerCase();

    if (!allowedFileMimeTypes.contains(mime) &&
        !allowedFileExtensions.contains(ext)) {
      return const UploadValidationResult(
        valid: false,
        error: 'Invalid file type. Allowed: images, PDF, DOC, DOCX',
      );
    }

    if (file.sizeBytes > maxFileSizeBytes) {
      return const UploadValidationResult(
        valid: false,
        error: 'File too large. Maximum size is 10MB.',
      );
    }

    return const UploadValidationResult(valid: true);
  }

  Future<Receipt> uploadReceipt({
    required String userId,
    required UploadFileData file,
    ValueChanged<double>? onProgress,
  }) async {
    final validation = validateFile(file);
    if (!validation.valid) {
      throw Exception(validation.error ?? 'Invalid file');
    }

    final userSnap = await _db.collection('users').doc(userId).get();
    final plan = (userSnap.data()?['subscriptionPlan'] as String?) ?? 'free';
    if (plan != 'pro') {
      final countSnap = await _db
          .collection('users')
          .doc(userId)
          .collection('receipts')
          .count()
          .get();
      final count = countSnap.count ?? 0;
      if (count >= 200) {
        throw Exception('FREE_PLAN_LIMIT_REACHED');
      }
    }

    final storagePath =
        'users/$userId/receipts/${DateTime.now().millisecondsSinceEpoch}_${sanitizeFileName(file.name)}';
    final ref = _storage.ref(storagePath);

    Uint8List uploadBytes;
    if (file.bytes != null) {
      uploadBytes = file.bytes!;
    } else if (file.path != null) {
      uploadBytes = await File(file.path!).readAsBytes();
    } else {
      throw Exception('No file data found for upload.');
    }

    final task = ref.putData(
      uploadBytes,
      SettableMetadata(contentType: file.mimeType ?? _inferMimeType(file.name)),
    );

    task.snapshotEvents.listen((event) {
      final total = event.totalBytes == 0 ? 1 : event.totalBytes;
      onProgress?.call(event.bytesTransferred / total);
    });

    await task;

    final docRef = await _db
        .collection('users')
        .doc(userId)
        .collection('receipts')
        .add({
          'userId': userId,
          'status': ReceiptStatuses.uploaded,
          'file': {
            'storagePath': storagePath,
            'originalName': file.name,
            'mimeType': file.mimeType ?? _inferMimeType(file.name),
            'sizeBytes': file.sizeBytes,
            'uploadedAt': FieldValue.serverTimestamp(),
          },
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

    await docRef.update({'id': docRef.id});

    final receipt = await getReceipt(userId, docRef.id);
    if (receipt == null) {
      throw Exception(
        'Upload succeeded but receipt record could not be loaded.',
      );
    }
    return receipt;
  }

  Future<void> updateReceipt(
    String userId,
    String receiptId,
    Map<String, dynamic> updates,
  ) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('receipts')
        .doc(receiptId)
        .update({...updates, 'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> deleteReceipt(String userId, Receipt receipt) async {
    if (receipt.file.storagePath.isNotEmpty) {
      try {
        await _storage.ref(receipt.file.storagePath).delete();
      } catch (_) {
        // Continue even if file delete fails.
      }
    }

    await _db
        .collection('users')
        .doc(userId)
        .collection('receipts')
        .doc(receipt.id)
        .delete();
  }

  Future<String> getReceiptFileUrl(String storagePath) async {
    return _storage.ref(storagePath).getDownloadURL();
  }

  Future<List<MonthlySummary>> getMonthlySummaries(
    String userId, {
    int? limit,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection('users')
        .doc(userId)
        .collection('monthlySummaries')
        .orderBy(FieldPath.documentId, descending: false);

    if (limit != null && limit > 0) {
      query = query.limit(limit);
    }

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => MonthlySummary.fromDoc(doc.id, doc.data()))
        .toList();
  }

  Future<Map<String, dynamic>> generateForwardingAddress() async {
    final callable = _functions.httpsCallable(
      'generateReceiptForwardingAddress',
    );
    final response = await callable.call(<String, dynamic>{});
    final data = response.data;
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }

  String _inferMimeType(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
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
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }
}
