import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:recieptnest_ai/src/features/getting_started/presentation/getting_started_prompt.dart';
import 'package:recieptnest_ai/src/features/auth/data/auth_repository.dart';
import 'package:recieptnest_ai/src/features/getting_started/data/native_onboarding_repository.dart';
import 'package:recieptnest_ai/src/features/getting_started/data/onboarding_analytics.dart';
import 'support/onboarding_fakes.dart';
import 'package:recieptnest_ai/src/features/getting_started/presentation/getting_started_screen.dart';

void main() {
  test(
    'prompt eligibility includes only accounts with zero to four receipts',
    () {
      for (final count in [0, 1, 4]) {
        expect(
          shouldShowGettingStartedPrompt(receiptCount: count, dismissed: false),
          isTrue,
        );
      }
      for (final count in [null, -1, 5, 200]) {
        expect(
          shouldShowGettingStartedPrompt(receiptCount: count, dismissed: false),
          isFalse,
        );
      }
      expect(
        shouldShowGettingStartedPrompt(receiptCount: 0, dismissed: true),
        isFalse,
      );
    },
  );

  testWidgets('native Home prompt offers collection and a resumable guide', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var uploads = 0;
    final cloud = FakeNativeCloud(count: 1, status: 'paused');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nativeOnboardingRepositoryProvider.overrideWithValue(
            cloud.repository(),
          ),
          onboardingAnalyticsProvider.overrideWithValue(SilentAnalytics()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: GettingStartedPrompt(
              userId: 'u',
              receiptCount: 1,
              onAddReceipt: () => uploads++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Continue guide'), findsOneWidget);
    await tester.tap(find.text('Add a receipt'));
    expect(uploads, 1);
    expect(find.text('Your first receipt is in.'), findsOneWidget);
  });

  testWidgets(
    'help always offers the video and mobile-specific instructions at phone width',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [currentUserIdProvider.overrideWithValue(null)],
          child: MaterialApp(home: Scaffold(body: GettingStartedScreen())),
        ),
      );
      expect(find.text('Watch the 85-second walkthrough'), findsOneWidget);
      expect(find.textContaining('Camera'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Find and export'), 300);
      expect(find.textContaining('Collections'), findsOneWidget);
      expect(find.textContaining('Upload receipt'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        gettingStartedVideoUrl,
        'https://receipt-nest.com/getting-started#walkthrough',
      );
    },
  );
}
