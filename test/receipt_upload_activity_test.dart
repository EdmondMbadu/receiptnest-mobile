import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:recieptnest_ai/src/features/receipts/data/receipt_upload_activity.dart';
import 'support/onboarding_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'pending uploads survive restart without persisting receipt contents',
    () async {
      final controller = ReceiptUploadActivityController('u');
      await controller.restored;
      controller.track(exampleReceipt(), guided: true);
      await controller.settled;
      controller.dispose();
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getString('receipt_upload_activity_v1:u')!;
      expect(stored, isNot(contains('café')));
      expect(stored, isNot(contains('storagePath')));
      final restored = ReceiptUploadActivityController('u');
      addTearDown(restored.dispose);
      await restored.restored;
      expect(restored.state.single.id, 'r1');
      expect(restored.state.single.guided, isTrue);
      expect(restored.state.single.seed, isNull);
    },
  );

  test('uploads from one account never appear in another account', () async {
    final first = ReceiptUploadActivityController('u');
    addTearDown(first.dispose);
    first.track(exampleReceipt());
    await first.settled;
    final second = ReceiptUploadActivityController('another-account');
    addTearDown(second.dispose);
    await second.restored;
    expect(second.state, isEmpty);
    second.track(exampleReceipt());
    expect(second.state, isEmpty);
  });

  test('a fast new upload preserves earlier-session pending uploads', () async {
    SharedPreferences.setMockInitialValues({
      'receipt_upload_activity_v1:u': jsonEncode([
        {'id': 'older', 'startedAt': '2026-11-22T10:00:00', 'guided': false},
      ]),
    });
    final controller = ReceiptUploadActivityController('u');
    addTearDown(controller.dispose);
    controller.track(exampleReceipt(id: 'newer'));
    await controller.settled;
    expect(controller.state.map((item) => item.id), ['older', 'newer']);
    final restored = ReceiptUploadActivityController('u');
    addTearDown(restored.dispose);
    await restored.restored;
    expect(restored.state.map((item) => item.id), ['older', 'newer']);
  });

  test(
    'acknowledging before restoration does not resurrect the receipt',
    () async {
      SharedPreferences.setMockInitialValues({
        'receipt_upload_activity_v1:u': jsonEncode([
          {'id': 'r1', 'startedAt': '2026-11-22T10:00:00'},
          {'id': 'r2', 'startedAt': '2026-11-22T10:01:00'},
        ]),
      });
      final controller = ReceiptUploadActivityController('u');
      addTearDown(controller.dispose);
      controller.acknowledge('r1');
      await controller.settled;
      expect(controller.state.map((item) => item.id), ['r2']);
      final restored = ReceiptUploadActivityController('u');
      addTearDown(restored.dispose);
      await restored.restored;
      expect(restored.state.map((item) => item.id), ['r2']);
    },
  );

  test('retries and duplicate restored references remain one upload', () async {
    SharedPreferences.setMockInitialValues({
      'receipt_upload_activity_v1:u': jsonEncode([
        {'id': 'r1', 'startedAt': '2026-11-22T10:00:00'},
        {'id': 'r1', 'startedAt': '2026-11-22T10:00:00'},
        {'id': 'not/a/receipt', 'startedAt': '2026-11-22T10:00:00'},
        {'id': 'invalid-date', 'startedAt': 'invalid'},
      ]),
    });
    final controller = ReceiptUploadActivityController('u');
    addTearDown(controller.dispose);
    await controller.restored;
    expect(controller.state, hasLength(1));
    controller.track(exampleReceipt());
    controller.track(exampleReceipt());
    await controller.settled;
    expect(controller.state, hasLength(1));
  });

  test(
    'corrupt storage never prevents a new upload or persists dismissed items',
    () async {
      SharedPreferences.setMockInitialValues({
        'receipt_upload_activity_v1:u': '{broken',
      });
      final controller = ReceiptUploadActivityController('u');
      addTearDown(controller.dispose);
      await controller.restored;
      controller.track(exampleReceipt());
      controller.acknowledge('r1');
      await controller.settled;
      final restored = ReceiptUploadActivityController('u');
      addTearDown(restored.dispose);
      await restored.restored;
      expect(restored.state, isEmpty);
    },
  );
}
