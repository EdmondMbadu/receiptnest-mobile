import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:recieptnest_ai/src/features/getting_started/data/native_onboarding_repository.dart';
import 'package:recieptnest_ai/src/features/receipts/models/receipt.dart';
import 'support/onboarding_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'all accounts below five receipts enter the new native introduction',
    () {
      for (final count in [0, 1, 2, 3, 4]) {
        expect(
          NativeOnboardingState(
            receiptCount: count,
            progress: const NativeOnboardingProgress(),
          ).enterGuide,
          isTrue,
        );
      }
      for (final count in [5, 200]) {
        expect(
          NativeOnboardingState(
            receiptCount: count,
            progress: const NativeOnboardingProgress(),
          ).enterGuide,
          isFalse,
        );
        expect(
          NativeOnboardingState(
            receiptCount: count,
            progress: const NativeOnboardingProgress(status: 'in_progress'),
          ).enterGuide,
          isFalse,
        );
      }
      for (final status in ['paused', 'completed']) {
        expect(
          NativeOnboardingState(
            receiptCount: 0,
            progress: NativeOnboardingProgress(status: status),
          ).enterGuide,
          isFalse,
        );
      }
    },
  );
  test(
    'web completion and the old device dismissal never suppress native onboarding',
    () async {
      SharedPreferences.setMockInitialValues({
        'getting_started_prompt_v1:u': true,
      });
      final cloud = FakeNativeCloud()..notDeployed = true;
      final state = await cloud.repository().load('u');
      expect(state.enterGuide, isTrue);
      expect(cloud.writes, isEmpty);
    },
  );
  test(
    'zero and refunds are usable; processing and failed extraction are not',
    () {
      for (final amount in [0.0, -12.0, 12.5]) {
        expect(
          isUsableReceipt(
            exampleReceipt(status: ReceiptStatuses.needsReview, amount: amount),
          ),
          isTrue,
        );
      }
      expect(
        isUsableReceipt(
          exampleReceipt(status: ReceiptStatuses.needsReview, amount: null),
        ),
        isFalse,
      );
      expect(
        isUsableReceipt(exampleReceipt(status: ReceiptStatuses.processing)),
        isFalse,
      );
      expect(
        isUsableReceipt(exampleReceipt(status: ReceiptStatuses.extracted)),
        isFalse,
      );
    },
  );
  test(
    'successive actions have distinct revisions even within one clock tick',
    () {
      var progress = const NativeOnboardingProgress(updatedAt: 9999999999999);
      for (final action in ['introduce', 'pause', 'introduce', 'restart']) {
        final next = progress.change(action);
        expect(next.updatedAt, greaterThan(progress.updatedAt));
        progress = next;
      }
    },
  );

  test(
    'paused task keeps its receipt, changing receipt clears its old view',
    () {
      final viewed = const NativeOnboardingProgress()
          .change('upload', receiptId: 'r1')
          .change('view', receiptId: 'r1');
      expect(viewed.change('pause').receiptId, 'r1');
      expect(viewed.change('introduce').receiptId, 'r1');
      expect(viewed.change('upload', receiptId: 'r2').viewedAt, isNull);
      expect(viewed.change('restart').receiptId, isNull);
      expect(viewed.change('complete').change('restart').completed, isTrue);
      expect(viewed.change('complete').change('restart').receiptId, 'r1');
    },
  );
  test(
    'offline progress is checkpointed before navigation and retries after process restart',
    () async {
      final cloud = FakeNativeCloud();
      final repository = cloud.repository();
      final initial = await repository.load('u');
      final paused = initial.progress.change('pause');
      cloud.offline = true;
      await repository.checkpoint('u', paused, 'pause');
      await repository.flush('u');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList('native_onboarding_v2:u:pending'),
        hasLength(1),
      );
      cloud.offline = false;
      final afterRestart = await cloud.repository().load('u');
      expect(afterRestart.progress.status, 'paused');
      expect(afterRestart.progress.firstOpenedAt, 100);
      expect(prefs.getStringList('native_onboarding_v2:u:pending'), isEmpty);
    },
  );
  test(
    'a previously started guide remains usable offline without assuming a new count',
    () async {
      final cloud = FakeNativeCloud(count: 2);
      final repository = cloud.repository();
      final state = await repository.load('u');
      await repository.checkpoint('u', state.progress.change('pause'), 'pause');
      cloud.offline = true;
      final offline = await cloud.repository().load('u');
      expect(offline.receiptCount, 2);
      expect(offline.progress.status, 'paused');
    },
  );

  test(
    'lost acknowledgement retries in order and keeps first view stable',
    () async {
      final cloud = FakeNativeCloud();
      final repository = cloud.repository();
      var progress = (await repository.load(
        'u',
      )).progress.change('upload', receiptId: 'r1');
      await repository.checkpoint('u', progress, 'upload', receiptId: 'r1');
      progress = progress.change('view', receiptId: 'r1');
      await repository.checkpoint('u', progress, 'view', receiptId: 'r1');
      cloud.loseAcknowledgement = true;
      await repository.flush('u');
      await repository.flush('u');
      final viewedAt = cloud.accounts['u']!.viewedAt;
      await repository.checkpoint(
        'u',
        progress.change('complete'),
        'complete',
        receiptId: 'r1',
      );
      await repository.flush('u');
      expect(cloud.accounts['u']!.completed, isTrue);
      expect(cloud.accounts['u']!.viewedAt, viewedAt);
      expect(cloud.writes.map((e) => e['action']), [
        'upload',
        'upload',
        'view',
        'complete',
      ]);
    },
  );
  test('pending work remains isolated to its account', () async {
    final cloud = FakeNativeCloud();
    final repository = cloud.repository();
    await repository.load('a');
    await repository.load('b');
    await repository.checkpoint(
      'a',
      const NativeOnboardingProgress().change('pause'),
      'pause',
    );
    await repository.flush('b');
    expect(cloud.writes, isEmpty);
    await repository.flush('a');
    expect(cloud.writes.single['expectedUserId'], 'a');
    expect(cloud.accounts['b']!.status, 'new');
  });
  test(
    'a failed count is an error rather than incorrectly assuming zero receipts',
    () async {
      final repository = NativeOnboardingRepository(
        (name, data) async => throw FirebaseFunctionsException(
          code: 'unavailable',
          message: 'offline',
        ),
      );
      await expectLater(
        repository.load('u'),
        throwsA(isA<FirebaseFunctionsException>()),
      );
    },
  );
}
