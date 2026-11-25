import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:recieptnest_ai/src/core/theme/app_theme.dart';
import 'package:recieptnest_ai/src/features/auth/models/user_profile.dart';
import 'package:recieptnest_ai/src/features/shell/presentation/app_shell_screen.dart';
import 'package:recieptnest_ai/src/features/receipts/data/receipt_repository.dart';
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
    'help keeps the main action and optional links visible in both themes',
    (tester) async {
      for (final dark in [false, true]) {
        await _help(tester, dark: dark);
        expect(find.text('Show me how').hitTestable(), findsOneWidget);
        expect(find.text('Contact support').hitTestable(), findsOneWidget);
        final nav = tester.getRect(find.byType(NavigationBar));
        expect(
          tester.getRect(find.text('Contact support')).bottom,
          lessThan(nav.top),
        );
        expect(find.textContaining('Search on Home.'), findsNothing);
        expect(
          find.text('Replay the guided receipt walkthrough'),
          findsNothing,
        );
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.byIcon(Icons.bar_chart_outlined), findsOneWidget);
        expect(find.byIcon(Icons.layers_outlined), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _captureHelp(tester, dark ? 'dark' : 'light');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'quick help expands one short answer at a time and supports closing it',
    (tester) async {
      await _help(tester);
      await tester.tap(find.text('Find or edit a receipt'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Search on Home. Open a receipt to review or edit its details.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Forward an email'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Search on Home.'), findsNothing);
      expect(find.text('Get my receipt address'), findsOneWidget);
      await _captureHelp(tester, 'email-help');
      await tester.tap(find.text('Forward an email'));
      await tester.pumpAndSettle();
      expect(find.text('Get my receipt address'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the guide resumes onboarding or replays a completed guide', (
    tester,
  ) async {
    for (final completed in [false, true]) {
      await _help(tester, completed: completed);
      await tester.tap(find.text('Show me how'));
      await tester.pumpAndSettle();
      expect(find.text('Guided receipt replay=$completed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('each short answer opens its relevant app screen', (
    tester,
  ) async {
    for (final scenario in [
      ('Find or edit a receipt', 'Open my receipts', 'My receipts'),
      ('Forward an email', 'Get my receipt address', 'Your receipt address'),
      ('Export receipts', 'Open Collections', 'Collections screen'),
    ]) {
      await _help(tester);
      await tester.tap(find.text(scenario.$1));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(scenario.$2));
      await tester.tap(find.text(scenario.$2));
      await tester.pumpAndSettle();
      expect(find.text(scenario.$3), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('support opens from the quiet footer link', (tester) async {
    await _help(tester);
    await tester.tap(find.text('Contact support'));
    await tester.pumpAndSettle();
    expect(find.text('Contact support screen'), findsOneWidget);
  });

  testWidgets('video failures keep the help page usable with a clear message', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async => false,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/url_launcher'),
            null,
          ),
    );
    await _help(tester);
    await tester.tap(find.text('Watch the video · 85 sec'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not open the video. Please try again when you are online.',
      ),
      findsOneWidget,
    );
    expect(find.text('Show me how'), findsOneWidget);
    expect(
      gettingStartedVideoUrl,
      'https://receipt-nest.com/getting-started#walkthrough',
    );
  });

  testWidgets(
    'small screens and larger text can reach every action without overflow',
    (tester) async {
      await _help(tester, size: const Size(320, 568), scale: 1.5, dark: true);
      await tester.tap(find.text('Show me how'));
      await tester.pumpAndSettle();
      expect(find.text('Guided receipt replay=false'), findsOneWidget);
      final context = tester.element(find.text('Guided receipt replay=false'));
      GoRouter.of(context).pop();
      await tester.pumpAndSettle();
      await _revealHelpAction(tester, 'Export receipts');
      await tester.tap(find.text('Export receipts'));
      await tester.pumpAndSettle();
      await _revealHelpAction(tester, 'Open Collections');
      expect(find.text('Open Collections').hitTestable(), findsOneWidget);
      await _revealHelpAction(tester, 'Contact support');
      expect(find.text('Contact support').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _captureHelp(tester, 'small-large-text');
    },
  );
}

final _helpCapture = GlobalKey();

Future<void> _revealHelpAction(WidgetTester tester, String label) async {
  final target = find.text(label);
  for (var i = 0; i < 10 && target.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(
      find.byKey(const ValueKey('help-content')),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
  }
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> _help(
  WidgetTester tester, {
  bool dark = false,
  bool completed = false,
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/app/help',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShellScreen(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/app/help',
            builder: (_, state) => const GettingStartedScreen(),
          ),
          GoRoute(
            path: '/app/home',
            builder: (_, state) => const Center(child: Text('My receipts')),
          ),
          GoRoute(
            path: '/app/folders',
            builder: (_, state) =>
                const Center(child: Text('Collections screen')),
          ),
        ],
      ),
      GoRoute(
        path: '/app/onboarding',
        builder: (_, state) => Scaffold(
          body: Text(
            'Guided receipt replay=${state.uri.queryParameters['replay'] == '1'}',
          ),
        ),
      ),
      GoRoute(
        path: '/app/forward-email',
        builder: (_, state) =>
            const Scaffold(body: Text('Your receipt address')),
      ),
      GoRoute(
        path: '/support',
        builder: (_, state) =>
            const Scaffold(body: Text('Contact support screen')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('u'),
        currentUserProfileProvider.overrideWith(
          (ref) => Stream.value(
            const UserProfile(
              id: 'u',
              firstName: 'Alex',
              lastName: '',
              email: 'alex@example.test',
            ),
          ),
        ),
        receiptsStreamProvider.overrideWith((ref) => Stream.value(const [])),
        nativeOnboardingRepositoryProvider.overrideWithValue(
          FakeNativeCloud(
            status: completed ? 'completed' : 'paused',
          ).repository(),
        ),
        onboardingAnalyticsProvider.overrideWithValue(SilentAnalytics()),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: _helpCapture, child: child!),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _captureHelp(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _helpCapture.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('output/help').create(recursive: true);
    await File(
      'output/help/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
