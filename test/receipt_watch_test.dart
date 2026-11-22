import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recieptnest_ai/src/features/receipts/data/receipt_repository.dart';
import 'package:recieptnest_ai/src/features/receipts/models/receipt.dart';

void main() {
  test(
    'cache misses and pending deletions never publish a missing receipt',
    () async {
      final updates = receiptUpdatesFromSnapshots(
        Stream.fromIterable([
          _Snapshot(exists: false, fromCache: true),
          _Snapshot(exists: true, status: ReceiptStatuses.processing),
          _Snapshot(
            exists: false,
            pending: true,
          ), // Optimistic delete, not committed.
          _Snapshot(
            exists: false,
            fromCache: true,
          ), // Connection drops before ack.
          _Snapshot(
            exists: true,
            status: ReceiptStatuses.finalStatus,
          ), // Rejected write rolls back.
          _Snapshot(exists: false), // Server finally confirms actual deletion.
        ]),
      );
      expect((await updates.toList()).map((receipt) => receipt?.status), [
        ReceiptStatuses.processing,
        ReceiptStatuses.finalStatus,
        null,
      ]);
    },
  );

  test(
    'a connection error propagates without turning the receipt into a deletion',
    () async {
      final snapshots =
          StreamController<DocumentSnapshot<Map<String, dynamic>>>();
      final values = <Receipt?>[];
      final errors = <Object>[];
      final subscription = receiptUpdatesFromSnapshots(
        snapshots.stream,
      ).listen(values.add, onError: errors.add);
      snapshots.add(_Snapshot(exists: true));
      snapshots.addError(StateError('Connection dropped'));
      await snapshots.close();
      expect(values, hasLength(1));
      expect(values.single?.id, 'r1');
      expect(errors, hasLength(1));
      await subscription.cancel();
    },
  );
}

// Firestore has no public snapshot constructor. This test-only double supplies
// metadata sequences without starting Firebase or writing any account data.
// ignore: subtype_of_sealed_class
class _Snapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot({
    required this.exists,
    bool fromCache = false,
    bool pending = false,
    this.status = ReceiptStatuses.finalStatus,
  }) : metadata = _Metadata(fromCache: fromCache, pending: pending);
  @override
  final bool exists;
  @override
  final SnapshotMetadata metadata;
  final String status;
  @override
  String get id => 'r1';
  @override
  Map<String, dynamic>? data() => exists
      ? {
          'userId': 'u',
          'status': status,
          'file': {
            'storagePath': 'users/u/receipts/r1.jpg',
            'originalName': 'receipt.jpg',
            'mimeType': 'image/jpeg',
            'sizeBytes': 10,
          },
        }
      : null;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected snapshot access');
}

class _Metadata implements SnapshotMetadata {
  _Metadata({required bool fromCache, required bool pending})
    : isFromCache = fromCache,
      hasPendingWrites = pending;
  @override
  final bool isFromCache;
  @override
  final bool hasPendingWrites;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected metadata access');
}
