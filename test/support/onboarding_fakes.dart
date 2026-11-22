import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:recieptnest_ai/src/core/config/public_app_config.dart';
import 'package:recieptnest_ai/src/features/receipts/data/receipt_repository.dart';
import 'package:recieptnest_ai/src/features/getting_started/data/native_onboarding_repository.dart';
import 'package:recieptnest_ai/src/features/getting_started/data/onboarding_analytics.dart';
import 'package:recieptnest_ai/src/features/receipts/models/receipt.dart';

class SilentAnalytics extends OnboardingAnalytics {
  final List<String> events = [];
  @override
  Future<void> event(
    String name, [
    Map<String, Object> parameters = const {},
  ]) async {
    events.add(name);
  }

  @override
  Future<void> identify(String? uid) async {}
}

class FakeNativeCloud {
  FakeNativeCloud({
    this.count = 0,
    this.status = 'new',
    this.receiptId,
    this.viewedAt,
  });
  final int count;
  final String status;
  final String? receiptId;
  final int? viewedAt;
  bool offline = false;
  bool notDeployed = false;
  bool loseAcknowledgement = false;
  final List<Map<String, dynamic>> writes = [];
  final Map<String, NativeOnboardingProgress> accounts = {};
  NativeOnboardingRepository repository() => NativeOnboardingRepository(call);
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data,
  ) async {
    if (offline) {
      throw FirebaseFunctionsException(code: 'unavailable', message: 'offline');
    }
    if (notDeployed && name != 'getGettingStartedState') {
      throw FirebaseFunctionsException(
        code: 'not-found',
        message: 'not deployed',
      );
    }
    if (name == 'getGettingStartedState') {
      return {
        'receiptCount': count,
        'progress': {'status': 'completed'},
      };
    }
    final uid = data['expectedUserId'] as String;
    final initial = accounts.putIfAbsent(
      uid,
      () => NativeOnboardingProgress(
        status: status,
        receiptId: receiptId,
        viewedAt: viewedAt,
        firstOpenedAt: 100,
        baselineReceiptCount: count,
        updatedAt: 100,
      ),
    );
    if (name == 'getNativeOnboardingState') {
      return {'receiptCount': count, 'progress': initial.toMap()};
    }
    writes.add(Map.of(data));
    final next = initial.change(
      data['action'] as String,
      receiptId: data['receiptId'] as String?,
    );
    accounts[uid] = next;
    if (loseAcknowledgement) {
      loseAcknowledgement = false;
      throw FirebaseFunctionsException(
        code: 'unavailable',
        message: 'response lost',
      );
    }
    return {'progress': next.toMap()};
  }
}

Receipt exampleReceipt({
  String id = 'r1',
  DateTime? createdAt,
  String date = '2026-10-01',
  String status = ReceiptStatuses.finalStatus,
  double? amount = 12.5,
}) => Receipt(
  id: id,
  userId: 'u',
  status: status,
  file: const ReceiptFile(
    storagePath: 'users/u/receipts/r1.jpg',
    originalName: 'Cafe receipt.jpg',
    mimeType: 'image/jpeg',
    sizeBytes: 1024,
  ),
  merchant: const ReceiptMerchant(
    canonicalId: null,
    canonicalName: 'Your local café',
    rawName: 'Your local café',
    matchConfidence: 1,
    matchedBy: 'manual',
  ),
  totalAmount: amount,
  date: date,
  createdAt: createdAt ?? DateTime(2026, 11, 22),
  category: const ReceiptCategory(
    id: 'restaurants',
    name: 'Restaurants',
    confidence: 1,
    assignedBy: 'ai',
  ),
);

class MemoryReceiptRepository implements ReceiptRepository {
  MemoryReceiptRepository([List<Receipt> initial = const []]) {
    for (final receipt in initial) {
      records[receipt.id] = receipt;
    }
  }
  final records = <String, Receipt>{};
  final _changes = StreamController<void>.broadcast();
  final uploads = <String>[];
  bool failDelete = false;

  Stream<List<Receipt>> get receiptChanges async* {
    yield records.values.toList();
    yield* _changes.stream.map((_) => records.values.toList());
  }

  Stream<Receipt?> receiptChangesFor(String id) async* {
    yield records[id];
    yield* _changes.stream.map((_) => records[id]);
  }

  @override
  Stream<List<Receipt>> watchReceipts(String uid) => receiptChanges;
  @override
  Future<Map<String, dynamic>> generateForwardingAddress() async => {
    'emailAddress': 'test@receipts.example',
  };
  @override
  Future<String> getReceiptFileUrl(String path) async =>
      throw StateError('Preview omitted in the test fixture');
  @override
  UploadValidationResult validateFile(
    UploadFileData file, {
    PublicAppConfig? appConfig,
  }) => const UploadValidationResult(valid: true);
  @override
  Future<Receipt> uploadReceipt({
    required String userId,
    required UploadFileData file,
    PublicAppConfig? appConfig,
    ValueChanged<double>? onProgress,
    String? uploadId,
  }) async {
    final id = uploadId!;
    uploads.add(id);
    final receipt = exampleReceipt(
      id: id,
      status: ReceiptStatuses.processing,
      createdAt: DateTime.now(),
    );
    records[id] = receipt;
    _changes.add(null);
    onProgress?.call(1);
    return receipt;
  }

  void finishProcessing(String id) {
    records[id] = exampleReceipt(id: id, createdAt: records[id]?.createdAt);
    _changes.add(null);
  }

  @override
  Future<void> deleteReceipt(String uid, Receipt receipt) async {
    if (failDelete) throw StateError('Simulated deletion failure');
    records.remove(receipt.id);
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected receipt call: ${invocation.memberName}',
  );
}
