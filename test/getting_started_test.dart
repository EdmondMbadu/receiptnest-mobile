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
  testWidgets(
    'Home offers a small resume link only for unfinished early onboarding',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      for (final scenario in [
        (1, 'paused', true),
        (2, 'in_progress', true),
        (1, 'completed', false),
        (0, 'paused', false),
        (3, 'paused', false),
        (5, 'new', false),
      ]) {
        final cloud = FakeNativeCloud(count: scenario.$1, status: scenario.$2);
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
                  receiptCount: scenario.$1,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Continue receipt guide'),
          scenario.$3 ? findsOneWidget : findsNothing,
        );
        expect(find.text('Your first receipt is in.'), findsNothing);
        expect(find.text('Add a receipt'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

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
