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
  bool hasReceipts = true,
}) {
  final repository = ai ?? InsightsTestAi();
  final receipts = InsightsTestReceipts();
  if (!hasReceipts) receipts.records.clear();
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
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: RepaintBoundary(key: _capture, child: child!),
            ),
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
        final upgrade = find.byKey(const ValueKey('insights-upgrade'));
        expect(upgrade.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(upgrade).bottom,
          lessThan(tester.getRect(find.byType(NavigationBar)).top),
        );
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
          final upgrade = find.byKey(const ValueKey('insights-upgrade'));
          expect(upgrade.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(upgrade).bottom,
            lessThan(tester.getRect(find.byType(NavigationBar)).top),
          );
          await capture(tester, 'upgrade-small-large-text');
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'upgrade stays visible while benefits scroll with device insets',
    (tester) async {
      viewport(tester, const Size(320, 568));
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await tester.pumpWidget(insightsFixture(textScale: 2));
      await tester.pumpAndSettle();
      final upgrade = find.byKey(const ValueKey('insights-upgrade'));
      final initial = tester.getRect(upgrade);
      expect(upgrade.hitTestable(), findsOneWidget);
      expect(
        initial.bottom,
        lessThan(tester.getRect(find.byType(NavigationBar)).top),
      );
      await tester.drag(
        find.byKey(const ValueKey('insights-upgrade-scroll')),
        const Offset(0, -1200),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(upgrade), initial);
      expect(upgrade.hitTestable(), findsOneWidget);
      expect(find.text('Spending trends').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
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
    await tester.tap(find.text('Upgrade to Pro'));
    await tester.pumpAndSettle();
    expect(find.text('Pricing destination'), findsOneWidget);
  });

  testWidgets('Pro empty states have a useful hierarchy on phone and tablet', (
    tester,
  ) async {
    viewport(tester);
    for (final scenario in [
      (const Size(390, 844), false),
      (const Size(390, 844), true),
      (const Size(1024, 900), true),
    ]) {
      final (size, dark) = scenario;
      tester.view.physicalSize = size;
      await tester.pumpWidget(insightsFixture(pro: true, dark: dark));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('insights-heading')), findsOneWidget);
      expect(find.text('Ask about your spending'), findsOneWidget);
      expect(find.byKey(const ValueKey('insights-composer')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(
        tester,
        size.width > 900
            ? 'pro-tablet'
            : dark
            ? 'pro-phone'
            : 'pro-phone-light',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'long answers scroll while the composer and header stay anchored',
    (tester) async {
      viewport(tester, const Size(320, 568));
      await tester.pumpWidget(insightsFixture(pro: true));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('insights-message-input')),
        'Summarize my spending',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('insights-send')));
      await tester.pumpAndSettle();
      final composer = find.byKey(const ValueKey('insights-composer'));
      final before = tester.getRect(composer);
      await tester.ensureVisible(
        find.textContaining('Review the original receipts'),
      );
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
    final navigation = tester.getRect(
      find.byKey(const ValueKey('primary-navigation')),
    );
    expect(composer.bottom, lessThanOrEqualTo(navigation.top));
    expect(navigation.bottom, lessThanOrEqualTo(568 - 260));
    for (final label in ['Home', 'Insights', 'Collections']) {
      expect(
        find
            .descendant(
              of: find.byKey(const ValueKey('primary-navigation')),
              matching: find.text(label),
            )
            .hitTestable(),
        findsOneWidget,
      );
    }
    expect(composer.height, lessThan(150));
    expect(tester.takeException(), isNull);
    await capture(tester, 'keyboard-small');
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
    expect(find.text('Summarize my spending'), findsWidgets);
    await tester.tap(find.byTooltip('New question'));
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

  testWidgets('saved threads stay in history until explicitly opened', (
    tester,
  ) async {
    viewport(tester);
    final history = StreamController<List<AiChatHistoryItem>>.broadcast();
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
    await tester.tap(find.byTooltip('Conversation history'));
    await tester.pump();
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
    expect(ai.loaded, isEmpty);
    expect(find.text('Your saved spending conversation.'), findsNothing);
    expect(find.text('Conversations'), findsOneWidget);
    await capture(tester, 'history');
    await tester.tap(find.textContaining('earlier spending conversation'));
    await tester.pumpAndSettle();
    expect(ai.loaded, ['earlier']);
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

  testWidgets(
    'Insights starts with just a question, and keeps Home guidance for empty accounts',
    (tester) async {
      viewport(tester);
      for (final hasReceipts in [true, false]) {
        await tester.pumpWidget(
          insightsFixture(pro: true, hasReceipts: hasReceipts),
        );
        await tester.pumpAndSettle();
        expect(find.text('Generate insights'), findsNothing);
        expect(find.text('Add receipt'), findsNothing);
        expect(find.text('View plans'), findsNothing);
        expect(find.text('Conversations'), findsNothing);
        expect(find.text('Ask about your spending'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('insights-message-input')).hitTestable(),
          findsOneWidget,
        );
        if (!hasReceipts) {
          expect(
            find.textContaining('Add your first receipt from Home'),
            findsOneWidget,
          );
          expect(
            find.text('How did my spending change this month?'),
            findsNothing,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'keyboard navigation preserves the question, draft, and background answer',
    (tester) async {
      viewport(tester);
      final ai = InsightsTestAi()
        ..pendingResponse = Completer<List<AiChatMessage>>();
      final router = GoRouter(
        initialLocation: '/app/insights',
        routes: [
          for (final tab in ['home', 'insights', 'folders'])
            GoRoute(
              path: '/app/$tab',
              builder: (_, state) => AppShellScreen(
                location: '/app/$tab',
                child: tab == 'insights'
                    ? const AiInsightsScreen()
                    : Center(child: Text('$tab destination')),
              ),
            ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        insightsFixture(pro: true, ai: ai, router: router),
      );
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('insights-message-input'));
      await tester.enterText(input, 'Which category was largest?');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('insights-send')));
      await tester.pump();
      expect(find.text('Which category was largest?'), findsWidgets);
      await tester.enterText(input, 'Compare it with last month');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('primary-navigation')),
          matching: find.text('Home'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('home destination'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding();
      ai.pendingResponse!.complete([
        AiChatMessage(
          id: 'question',
          role: 'user',
          content: 'Which category was largest?',
          timestamp: DateTime(2026),
        ),
        AiChatMessage(
          id: 'answer',
          role: 'assistant',
          content: 'Your dining category was largest.',
          timestamp: DateTime(2026),
        ),
      ]);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('primary-navigation')),
          matching: find.text('Insights'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your dining category was largest.'), findsOneWidget);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Compare it with last month',
      );
      expect(ai.sent, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'landscape and enlarged text retain accessible navigation above the keyboard',
    (tester) async {
      viewport(tester, const Size(844, 390));
      await tester.pumpWidget(insightsFixture(pro: true, textScale: 1.6));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('insights-message-input')));
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.pumpAndSettle();
      final nav = tester.getRect(
        find.byKey(const ValueKey('primary-navigation')),
      );
      expect(nav.bottom, lessThanOrEqualTo(140));
      expect(
        find.byKey(const ValueKey('insights-message-input')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'typing hides introductory prompts even when there is plenty of vertical room',
    (tester) async {
      viewport(tester);
      await tester.pumpWidget(insightsFixture(pro: true));
      await tester.pumpAndSettle();
      expect(find.text('Ask about your spending'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('insights-message-input')));
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      await tester.pumpAndSettle();
      expect(find.text('Ask about your spending'), findsNothing);
      expect(find.text('How did my spending change this month?'), findsNothing);
      expect(
        find.byKey(const ValueKey('insights-message-input')).hitTestable(),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('primary-navigation'))).bottom,
        lessThanOrEqualTo(664),
      );
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(find.text('Ask about your spending'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a fresh question resets a scrolled conversation to the beginning',
    (tester) async {
      viewport(tester);
      await tester.pumpWidget(insightsFixture(pro: true));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('insights-message-input')),
        'Summarize my spending',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('insights-send')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.textContaining('Review the original receipts'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('New question'));
      await tester.pumpAndSettle();
      final content = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('insights-content')),
      );
      expect(content.controller!.offset, 0);
      expect(
        find.text('Ask about your spending').hitTestable(),
        findsOneWidget,
      );
      expect(find.textContaining('Review the original receipts'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
