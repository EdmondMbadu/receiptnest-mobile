import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:recieptnest_ai/src/core/theme/app_theme.dart';
import 'package:recieptnest_ai/src/features/auth/data/auth_repository.dart';
import 'package:recieptnest_ai/src/features/auth/models/user_profile.dart';
import 'package:recieptnest_ai/src/features/ai/data/ai_repository.dart';
import 'package:recieptnest_ai/src/features/ai/models/chat_models.dart';
import 'package:recieptnest_ai/src/features/ai/presentation/ai_insights_screen.dart';
import 'package:recieptnest_ai/src/features/shell/presentation/app_shell_screen.dart';
import 'package:recieptnest_ai/src/features/receipts/data/receipt_repository.dart';
import 'support/ai_fakes.dart';

final _capture = GlobalKey();

Widget insightsFixture({
  bool pro = false,
  bool dark = true,
  double textScale = 1,
  InsightsTestAi? ai,
  Stream<List<AiChatHistoryItem>>? history,
  GoRouter? router,
}) {
  final repository = ai ?? InsightsTestAi();
  final receipts = InsightsTestReceipts();
  return ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('u'),
      currentUserProfileProvider.overrideWith(
        (ref) => Stream.value(
          UserProfile(
            id: 'u',
            firstName: 'Test',
            lastName: '',
            email: 'test@example.test',
            subscriptionPlan: pro ? 'pro' : 'free',
          ),
        ),
      ),
      aiChatHistoryProvider.overrideWith(
        (ref) => history ?? Stream.value(const <AiChatHistoryItem>[]),
      ),
      aiRepositoryProvider.overrideWithValue(repository),
      receiptRepositoryProvider.overrideWithValue(receipts),
      receiptsStreamProvider.overrideWith(
        (ref) => Stream.value(receipts.records.values.toList()),
      ),
      aiSuggestedQuestionsProvider.overrideWithValue(const [
        'How did my spending change this month?',
        'Which categories account for most of my spending?',
        'What were my largest purchases?',
      ]),
    ],
    child: router == null
        ? MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: RepaintBoundary(key: _capture, child: child!),
            ),
            home: const AppShellScreen(
              location: '/app/insights',
              child: AiInsightsScreen(),
            ),
          )
        : MaterialApp.router(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            routerConfig: router,
          ),
  );
}

void viewport(WidgetTester tester, [Size size = const Size(390, 844)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

Future<void> capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage(pixelRatio: 2);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    await Directory('output/insights').create(recursive: true);
    await File(
      'output/insights/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    for (final name in ['Manrope', '.SF Pro Display']) {
      await (FontLoader(
        name,
      )..addFont(rootBundle.load('assets/fonts/Manrope.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'Insights upgrade content wraps cleanly inside the native shell',
    (tester) async {
      viewport(tester);
      for (final dark in [false, true]) {
        await tester.pumpWidget(insightsFixture(dark: dark));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('AI Insights'), findsOneWidget);
        await capture(tester, dark ? 'upgrade-dark' : 'upgrade-light');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'small phones and large text keep upgrade content and actions accessible',
    (tester) async {
      viewport(tester, const Size(320, 568));
      for (final pro in [false, true]) {
        await tester.pumpWidget(insightsFixture(pro: pro, textScale: 1.6));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (!pro) {
          await tester.ensureVisible(find.text('Upgrade to Pro'));
          expect(
            tester.getRect(find.text('Upgrade to Pro')).bottom,
            lessThanOrEqualTo(568),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('the upgrade action still opens pricing', (tester) async {
    viewport(tester);
    final router = GoRouter(
      initialLocation: '/app/insights',
      routes: [
        GoRoute(
          path: '/app/insights',
          builder: (_, state) => const AppShellScreen(
            location: '/app/insights',
            child: AiInsightsScreen(),
          ),
        ),
        GoRoute(
          path: '/app/pricing',
          builder: (_, state) =>
              const Scaffold(body: Text('Pricing destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(insightsFixture(router: router));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Upgrade to Pro'));
    await tester.tap(find.text('Upgrade to Pro'));
    await tester.pumpAndSettle();
    expect(find.text('Pricing destination'), findsOneWidget);
  });

  testWidgets('Pro empty states have a useful hierarchy on phone and tablet', (
    tester,
  ) async {
    viewport(tester);
    for (final size in [const Size(390, 844), const Size(1024, 900)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(insightsFixture(pro: true));
      await tester.pumpAndSettle();
      expect(find.text('AI Insights'), findsOneWidget);
      expect(find.text('Ask about your spending'), findsOneWidget);
      expect(find.byKey(const ValueKey('insights-composer')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, size.width > 900 ? 'pro-tablet' : 'pro-phone');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'long generated insights scroll while the composer stays anchored',
    (tester) async {
      viewport(tester, const Size(320, 568));
      await tester.pumpWidget(insightsFixture(pro: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('insights-generate')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('generated-insights')), findsOneWidget);
      final composer = find.byKey(const ValueKey('insights-composer'));
      final before = tester.getRect(composer);
      await tester.ensureVisible(find.textContaining('Insight 12:'));
      await tester.pumpAndSettle();
      expect(tester.getRect(composer), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the keyboard leaves a usable composer without double padding', (
    tester,
  ) async {
    viewport(tester, const Size(320, 568));
    await tester.pumpWidget(insightsFixture(pro: true, textScale: 1.4));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('insights-message-input')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.enterText(
      find.byKey(const ValueKey('insights-message-input')),
      'Compare this month with my previous spending and show the biggest changes in my categories.',
    );
    await tester.pumpAndSettle();
    final composer = tester.getRect(
      find.byKey(const ValueKey('insights-composer')),
    );
    expect(composer.bottom, lessThanOrEqualTo(568 - 260));
    expect(composer.height, lessThan(150));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long Markdown answers and user messages fit the conversation width',
    (tester) async {
      viewport(tester);
      final ai = InsightsTestAi();
      await tester.pumpWidget(insightsFixture(pro: true, ai: ai));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('insights-message-input')),
        'Give me a detailed breakdown of my spending, including my recurring purchases and the categories where the amounts have changed.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('insights-send')));
      await tester.pumpAndSettle();
      expect(ai.sent, hasLength(1));
      expect(find.textContaining('Review the original receipts'), findsWidgets);
      expect(tester.takeException(), isNull);
      await capture(tester, 'conversation');
    },
  );

  testWidgets('starting a new conversation ignores an older pending response', (
    tester,
  ) async {
    viewport(tester);
    final ai = InsightsTestAi()
      ..pendingResponse = Completer<List<AiChatMessage>>();
    await tester.pumpWidget(insightsFixture(pro: true, ai: ai));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('insights-message-input')),
      'Summarize my spending',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('insights-send')));
    await tester.pump();
    expect(ai.sent, hasLength(1));
    await tester.tap(find.byTooltip('Conversation options'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('New conversation'));
    await tester.pump();
    ai.pendingResponse!.complete([
      AiChatMessage(
        id: 'old',
        role: 'assistant',
        content: 'Old answer that must not replace the new conversation.',
        timestamp: DateTime(2026, 11, 22),
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Ask about your spending'), findsOneWidget);
    expect(find.textContaining('Old answer'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delayed history loads once and its drawer opens conversations', (
    tester,
  ) async {
    viewport(tester);
    final history = StreamController<List<AiChatHistoryItem>>();
    addTearDown(history.close);
    final ai = InsightsTestAi()
      ..historyMessages = [
        AiChatMessage(
          id: 'saved-answer',
          role: 'assistant',
          content: 'Your saved spending conversation.',
          timestamp: DateTime(2026, 11, 22),
        ),
      ];
    await tester.pumpWidget(
      insightsFixture(pro: true, ai: ai, history: history.stream),
    );
    await tester.pump();
    expect(ai.loaded, isEmpty);
    history.add([
      for (final id in ['latest', 'earlier'])
        AiChatHistoryItem(
          id: id,
          title: '$id spending conversation with a longer title',
          createdAt: DateTime(2026, 11, 22),
          updatedAt: DateTime(2026, 11, 22),
          messageCount: 2,
        ),
    ]);
    await tester.pumpAndSettle();
    expect(ai.loaded, ['latest']);
    expect(find.text('Your saved spending conversation.'), findsOneWidget);
    await tester.tap(find.byTooltip('Conversation history'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('earlier spending conversation'));
    await tester.pumpAndSettle();
    expect(ai.loaded, ['latest', 'earlier']);
    expect(find.text('Conversations'), findsNothing);
    expect(find.byKey(const ValueKey('insights-composer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed sends restore the question and keep the composer usable',
    (tester) async {
      viewport(tester);
      final ai = InsightsTestAi()..failSend = true;
      await tester.pumpWidget(insightsFixture(pro: true, ai: ai));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('insights-message-input')),
        'Which category was largest?',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('insights-send')));
      await tester.pumpAndSettle();
      expect(ai.sent, hasLength(1));
      expect(
        find.textContaining('We couldn’t send your question.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('insights-message-input')),
            )
            .controller!
            .text,
        'Which category was largest?',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
