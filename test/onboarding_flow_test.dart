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
import 'package:recieptnest_ai/src/features/auth/presentation/account_access_screen.dart';
import 'package:recieptnest_ai/src/features/getting_started/data/native_onboarding_repository.dart';
import 'package:recieptnest_ai/src/features/getting_started/data/onboarding_analytics.dart';
import 'package:recieptnest_ai/src/features/getting_started/presentation/native_onboarding_screen.dart';
import 'package:recieptnest_ai/src/features/getting_started/presentation/getting_started_prompt.dart';
import 'package:recieptnest_ai/src/features/receipts/data/receipt_repository.dart';
import 'package:recieptnest_ai/src/features/receipts/models/receipt.dart';
import 'package:recieptnest_ai/src/features/static/presentation/landing_screen.dart';
import 'support/onboarding_fakes.dart';

final _capture = GlobalKey();

Future<void> screenshot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    await precacheImage(
      const AssetImage('assets/images/receipt-nest.png'),
      _capture.currentContext!,
    );
  });
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage(pixelRatio: 2);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    await Directory('output/onboarding').create(recursive: true);
    await File(
      'output/onboarding/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

Widget fixture({
  required Widget child,
  FakeNativeCloud? cloud,
  Receipt? receipt,
  Stream<Receipt?>? stream,
  bool dark = false,
  GoRouter? router,
  double textScale = 1,
}) {
  final fake = cloud ?? FakeNativeCloud();
  final overrides = [
    currentUserIdProvider.overrideWithValue('u'),
    nativeOnboardingRepositoryProvider.overrideWithValue(fake.repository()),
    onboardingAnalyticsProvider.overrideWithValue(SilentAnalytics()),
    sortedReceiptsProvider.overrideWithValue(receipt == null ? [] : [receipt]),
    receiptWatchProvider(
      'r1',
    ).overrideWith((ref) => stream ?? Stream.value(receipt)),
  ];
  Widget wrap(BuildContext context, Widget? body) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: RepaintBoundary(key: _capture, child: body!),
  );
  return ProviderScope(
    overrides: overrides,
    child: router == null
        ? MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: wrap,
            home: child,
          )
        : MaterialApp.router(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: wrap,
            routerConfig: router,
          ),
  );
}

void phone(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await loader.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      '.SF Pro Text',
    )..addFont(rootBundle.load('assets/fonts/Manrope.ttf'))).load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'welcome keeps both actions visible on a small phone and opens social-first signup',
    (tester) async {
      phone(tester, size: const Size(375, 667));
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, state) => const LandingScreen()),
          GoRoute(
            path: '/register',
            builder: (_, state) => const AccountAccessScreen(signIn: false),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        fixture(child: const LandingScreen(), router: router),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Get started')).bottom, lessThan(667));
      expect(tester.getRect(find.text('Sign in')).bottom, lessThan(667));
      await screenshot(tester, 'welcome');
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Apple'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(
        tester.getTopLeft(find.text('Continue with Apple')).dy,
        lessThan(tester.getTopLeft(find.text('Continue with email')).dy),
      );
      await screenshot(tester, 'account');
      await tester.tap(find.text('Continue with email'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'authenticated entry gates zero-to-four accounts and respects paused or completed guides',
    (tester) async {
      phone(tester);
      for (final scenario in [
        (0, 'new', 'guide'),
        (4, 'new', 'guide'),
        (5, 'new', 'home'),
        (0, 'paused', 'home'),
        (1, 'completed', 'home'),
        (2, 'in_progress', 'guide'),
      ]) {
        final cloud = FakeNativeCloud(count: scenario.$1, status: scenario.$2);
        final router = GoRouter(
          initialLocation: '/app/entry',
          routes: [
            GoRoute(
              path: '/app/entry',
              builder: (_, state) => const NativeOnboardingEntryScreen(),
            ),
            GoRoute(
              path: '/app/onboarding',
              builder: (_, state) => const Scaffold(body: Text('guide')),
            ),
            GoRoute(
              path: '/app/home',
              builder: (_, state) => const Scaffold(body: Text('home')),
            ),
          ],
        );
        await tester.pumpWidget(
          fixture(child: const SizedBox(), cloud: cloud, router: router),
        );
        await tester.pumpAndSettle();
        expect(find.text(scenario.$3), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
      }
    },
  );

  testWidgets(
    'choosing later returns to Home and saves a resumable account checkpoint',
    (tester) async {
      phone(tester);
      final cloud = FakeNativeCloud();
      final router = GoRouter(
        initialLocation: '/app/onboarding',
        routes: [
          GoRoute(
            path: '/app/onboarding',
            builder: (_, state) => const NativeOnboardingScreen(),
          ),
          GoRoute(
            path: '/app/home',
            builder: (_, state) => const Scaffold(body: Text('home')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        fixture(child: const SizedBox(), cloud: cloud, router: router),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('I’ll do this later'));
      await tester.tap(find.text('I’ll do this later'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(cloud.accounts['u']!.status, 'paused');
    },
  );

  testWidgets(
    'the first-receipt introduction uses real source choices in light and dark mode',
    (tester) async {
      phone(tester);
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          fixture(child: const NativeOnboardingScreen(), dark: dark),
        );
        await tester.pumpAndSettle();
        expect(find.text('Take a photo'), findsOneWidget);
        expect(find.text('Choose a photo'), findsOneWidget);
        expect(find.text('Choose a file'), findsOneWidget);
        expect(find.text('I’ll do this later'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await screenshot(tester, dark ? 'guide-dark' : 'guide');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'processing becomes a ready receipt live without closing or restarting the guide',
    (tester) async {
      phone(tester);
      final stream = StreamController<Receipt?>();
      addTearDown(stream.close);
      final cloud = FakeNativeCloud(status: 'in_progress', receiptId: 'r1');
      await tester.pumpWidget(
        fixture(
          child: const NativeOnboardingScreen(),
          cloud: cloud,
          stream: stream.stream,
        ),
      );
      stream.add(exampleReceipt(status: ReceiptStatuses.processing));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('The details,\ncoming together.'), findsOneWidget);
      await screenshot(tester, 'processing');
      stream.add(exampleReceipt());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('View my receipt'), findsOneWidget);
      expect(find.text('Your local café'), findsOneWidget);
      await screenshot(tester, 'ready');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('failed extraction stays in review and never displays success', (
    tester,
  ) async {
    phone(tester);
    final cloud = FakeNativeCloud(status: 'in_progress', receiptId: 'r1');
    await tester.pumpWidget(
      fixture(
        child: const NativeOnboardingScreen(),
        cloud: cloud,
        receipt: exampleReceipt(
          status: ReceiptStatuses.needsReview,
          amount: null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Check receipt details'), findsOneWidget);
    expect(find.text('Try a clearer receipt instead'), findsOneWidget);
    expect(find.text('View my receipts'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'viewing a receipt needing review is not completion until confirmed',
    (tester) async {
      phone(tester);
      final cloud = FakeNativeCloud(
        status: 'in_progress',
        receiptId: 'r1',
        viewedAt: 200,
      );
      await tester.pumpWidget(
        fixture(
          child: const NativeOnboardingScreen(),
          cloud: cloud,
          receipt: exampleReceipt(status: ReceiptStatuses.needsReview),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Check receipt details'), findsOneWidget);
      expect(find.text('View my receipts'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a viewed, confirmed receipt offers a real success and next upload',
    (tester) async {
      phone(tester);
      final cloud = FakeNativeCloud(
        status: 'in_progress',
        receiptId: 'r1',
        viewedAt: 200,
      );
      await tester.pumpWidget(
        fixture(
          child: const NativeOnboardingScreen(),
          cloud: cloud,
          receipt: exampleReceipt(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('View my receipts'), findsOneWidget);
      expect(find.text('Add another receipt'), findsOneWidget);
      await screenshot(tester, 'success');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('large text remains readable and scrollable at narrow widths', (
    tester,
  ) async {
    phone(tester, size: const Size(320, 568));
    for (final screen in [
      const LandingScreen(),
      const AccountAccessScreen(signIn: false),
      const NativeOnboardingScreen(),
    ]) {
      await tester.pumpWidget(fixture(child: screen, textScale: 1.5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'empty Home focuses on adding a receipt without charts or setup',
    (tester) async {
      phone(tester);
      var added = false;
      await tester.pumpWidget(
        fixture(
          child: Scaffold(
            body: EmptyReceiptHome(
              onAdd: () => added = true,
              onRefresh: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await screenshot(tester, 'empty-home');
      await tester.ensureVisible(find.text('Add my first receipt'));
      await tester.tap(find.text('Add my first receipt'));
      expect(added, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
