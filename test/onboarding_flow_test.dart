import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:recieptnest_ai/src/core/theme/app_theme.dart';
import 'package:recieptnest_ai/src/core/config/public_app_config.dart';
import 'package:recieptnest_ai/src/features/auth/models/user_profile.dart';
import 'package:recieptnest_ai/src/features/home/presentation/home_screen.dart';
import 'package:recieptnest_ai/src/features/receipts/presentation/receipt_detail_screen.dart';
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
  MemoryReceiptRepository? repository,
  bool dark = false,
  GoRouter? router,
  double textScale = 1,
}) {
  final fake = cloud ?? FakeNativeCloud();
  final overrides = [
    currentUserIdProvider.overrideWithValue('u'),
    currentUserProfileProvider.overrideWith(
      (ref) => Stream.value(
        const UserProfile(
          id: 'u',
          firstName: 'Test',
          lastName: '',
          email: 'test@example.test',
        ),
      ),
    ),
    publicAppConfigProvider.overrideWith(
      (ref) => Stream.value(const PublicAppConfig()),
    ),
    if (repository != null)
      receiptRepositoryProvider.overrideWithValue(repository),
    if (repository != null)
      receiptFileUrlProvider.overrideWith(
        (ref, path) => repository.getReceiptFileUrl(path),
      ),
    nativeOnboardingRepositoryProvider.overrideWithValue(fake.repository()),
    onboardingAnalyticsProvider.overrideWithValue(SilentAnalytics()),
    receiptsStreamProvider.overrideWith(
      (ref) =>
          repository?.receiptChanges ??
          Stream.value(receipt == null ? [] : [receipt]),
    ),
    receiptWatchProvider.overrideWith(
      (ref, id) =>
          repository?.receiptChangesFor(id) ?? stream ?? Stream.value(receipt),
    ),
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

  testWidgets(
    'a completed guide does not reopen its deleted receipt for a new upload',
    (tester) async {
      phone(tester);
      final cloud = FakeNativeCloud(
        count: 0,
        status: 'completed',
        receiptId: 'r1',
        viewedAt: 200,
      );
      await tester.pumpWidget(
        fixture(child: const NativeOnboardingScreen(), cloud: cloud),
      );
      await tester.pumpAndSettle();
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Choose a file'), findsOneWidget);
      expect(
        find.textContaining('We couldn’t open this receipt'),
        findsNothing,
      );
      expect(cloud.accounts['u']!.completed, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a deleted receipt in an unfinished guide returns directly to source choices',
    (tester) async {
      phone(tester);
      final cloud = FakeNativeCloud(
        count: 0,
        status: 'in_progress',
        receiptId: 'r1',
      );
      await tester.pumpWidget(
        fixture(child: const NativeOnboardingScreen(), cloud: cloud),
      );
      await tester.pumpAndSettle();
      expect(find.text('Take a photo'), findsOneWidget);
      expect(
        find.textContaining('We couldn’t open this receipt'),
        findsNothing,
      );
      expect(cloud.accounts['u']!.receiptId, isNull);
      expect(cloud.accounts['u']!.firstOpenedAt, 100);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'deleting the last receipt then adding a replacement follows the actual Home flow',
    (tester) async {
      phone(tester);
      final repository = MemoryReceiptRepository([exampleReceipt()]);
      addTearDown(repository.dispose);
      final cloud = FakeNativeCloud(
        count: 1,
        status: 'completed',
        receiptId: 'r1',
        viewedAt: 200,
      );
      final router = GoRouter(
        initialLocation: '/app/home',
        routes: [
          GoRoute(path: '/app/home', builder: (_, state) => const HomeScreen()),
          GoRoute(
            path: '/app/receipt/:id',
            builder: (_, state) => ReceiptDetailScreen(
              receiptId: state.pathParameters['id']!,
              guided: state.uri.queryParameters['guide'] == '1',
              onboardingReplay: state.uri.queryParameters['replay'] == '1',
            ),
          ),
          GoRoute(
            path: '/app/onboarding',
            builder: (_, state) => NativeOnboardingScreen(
              startFresh: state.uri.queryParameters['fresh'] == '1',
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      FilePicker.platform = _SelectedReceiptFilePicker();
      await tester.pumpWidget(
        fixture(
          child: const SizedBox(),
          cloud: cloud,
          repository: repository,
          router: router,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('featured-recent-receipt')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Delete receipt'),
        400,
        scrollable: find
            .descendant(
              of: find.byType(ReceiptDetailScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Delete receipt'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(repository.records, isEmpty);
      expect(find.byType(EmptyReceiptHome), findsOneWidget);
      await tester.ensureVisible(find.text('Add my first receipt'));
      await tester.tap(find.text('Add my first receipt'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<NativeOnboardingScreen>(find.byType(NativeOnboardingScreen))
            .startFresh,
        isTrue,
      );
      expect(find.text('Start with\none receipt.'), findsOneWidget);
      expect(find.text('Take a photo'), findsOneWidget);
      await tester.tap(find.text('Choose a file'));
      await tester.pumpAndSettle();
      expect(find.text('Replacement receipt.pdf'), findsOneWidget);
      await tester.tap(find.text('Upload receipt'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(repository.uploads, hasLength(1));
      final replacementId = repository.uploads.single;
      expect(replacementId, isNot('r1'));
      expect(find.text('The details,\ncoming together.'), findsOneWidget);
      repository.finishProcessing(replacementId);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('View my receipt'), findsOneWidget);
      expect(find.textContaining('We couldn’t'), findsNothing);
      expect(cloud.accounts['u']!.completed, isTrue);
      expect(
        cloud.accounts['u']!.receiptId,
        'r1',
      ); // Completion history is preserved.
      await tester.tap(find.text('View my receipt'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReceiptDetailScreen>(find.byType(ReceiptDetailScreen))
            .receiptId,
        replacementId,
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View my receipts'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('featured-recent-receipt')),
        findsOneWidget,
      );
      expect(
        cloud.writes.where((event) => event['action'] != 'observe'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'cancelled and failed deletions retain both the receipt and its guide',
    (tester) async {
      phone(tester);
      for (final failDelete in [false, true]) {
        final repository = MemoryReceiptRepository([exampleReceipt()])
          ..failDelete = failDelete;
        final cloud = FakeNativeCloud(
          count: 1,
          status: 'paused',
          receiptId: 'r1',
        );
        await tester.pumpWidget(
          fixture(
            child: const ReceiptDetailScreen(receiptId: 'r1'),
            cloud: cloud,
            repository: repository,
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Delete receipt'),
          400,
          scrollable: find
              .descendant(
                of: find.byType(ReceiptDetailScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.text('Delete receipt'));
        await tester.pumpAndSettle();
        await tester.tap(
          failDelete
              ? find.widgetWithText(FilledButton, 'Delete')
              : find.text('Cancel'),
        );
        await tester.pumpAndSettle();
        expect(repository.records.keys, ['r1']);
        expect(cloud.accounts['u']!.receiptId, 'r1');
        expect(
          cloud.writes.where((event) => event['action'] == 'restart'),
          isEmpty,
        );
        if (failDelete) {
          expect(
            find.textContaining('We couldn’t delete this receipt'),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await repository.dispose();
      }
    },
  );

  testWidgets(
    'Home features only the first two receipts and removes completed onboarding prompts',
    (tester) async {
      phone(tester);
      for (final count in [1, 2, 3, 4, 5]) {
        final receipts = List.generate(
          count,
          (index) => exampleReceipt(
            id: 'r$index',
            createdAt: DateTime(2026, 11, index + 1),
          ),
        );
        final repository = MemoryReceiptRepository(receipts);
        final cloud = FakeNativeCloud(count: count, status: 'completed');
        await tester.pumpWidget(
          fixture(
            child: const HomeScreen(),
            cloud: cloud,
            repository: repository,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('featured-recent-receipt')),
          count < 3 ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('YOUR RECENT RECEIPT'),
          count < 3 ? findsOneWidget : findsNothing,
        );
        expect(find.text('Continue receipt guide'), findsNothing);
        expect(find.text('Your first receipt is in.'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await repository.dispose();
      }
    },
  );

  testWidgets(
    'Home leads with the newest upload above its optional resume link',
    (tester) async {
      phone(tester);
      final repository = MemoryReceiptRepository([
        exampleReceipt(
          id: 'old',
          date: '2026-11-22',
          createdAt: DateTime(2026, 11, 1),
        ),
        exampleReceipt(
          id: 'new',
          date: '2026-01-01',
          createdAt: DateTime(2026, 11, 22),
        ),
      ]);
      addTearDown(repository.dispose);
      final router = GoRouter(
        initialLocation: '/app/home',
        routes: [
          GoRoute(path: '/app/home', builder: (_, state) => const HomeScreen()),
          GoRoute(
            path: '/app/receipt/:id',
            builder: (_, state) =>
                Scaffold(body: Text('opened:${state.pathParameters['id']}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        fixture(
          child: const SizedBox(),
          cloud: FakeNativeCloud(count: 2, status: 'paused'),
          repository: repository,
          router: router,
        ),
      );
      await tester.pumpAndSettle();
      final featured = find.byKey(const ValueKey('featured-recent-receipt'));
      expect(
        tester.getTopLeft(find.text('Continue receipt guide')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(featured).dy),
      );
      await tester.tap(featured);
      await tester.pumpAndSettle();
      expect(find.text('opened:new'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a connection error preserves the saved receipt for retry', (
    tester,
  ) async {
    phone(tester);
    final cloud = FakeNativeCloud(status: 'paused', receiptId: 'r1');
    await tester.pumpWidget(
      fixture(
        child: const NativeOnboardingScreen(),
        cloud: cloud,
        stream: Stream.error(Exception('offline')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Check your connection'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Take a photo'), findsNothing);
    expect(cloud.accounts['u']!.receiptId, 'r1');
    expect(
      cloud.writes.where((event) => event['action'] == 'restart'),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a receipt deleted while the guide is open recovers without an error page',
    (tester) async {
      phone(tester);
      final stream = StreamController<Receipt?>();
      addTearDown(stream.close);
      final cloud = FakeNativeCloud(
        count: 1,
        status: 'in_progress',
        receiptId: 'r1',
      );
      await tester.pumpWidget(
        fixture(
          child: const NativeOnboardingScreen(),
          cloud: cloud,
          stream: stream.stream,
        ),
      );
      stream.add(exampleReceipt());
      await tester.pumpAndSettle();
      expect(find.text('View my receipt'), findsOneWidget);
      stream.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Choose a file'), findsOneWidget);
      expect(find.textContaining('We couldn’t'), findsNothing);
      expect(cloud.accounts['u']!.receiptId, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'explicit fresh entry discards an unfinished task and survives re-entry',
    (tester) async {
      phone(tester);
      final cloud = FakeNativeCloud(
        status: 'paused',
        receiptId: 'r1',
        viewedAt: 200,
      );
      await tester.pumpWidget(
        fixture(
          child: const NativeOnboardingScreen(startFresh: true),
          cloud: cloud,
          receipt: exampleReceipt(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('View my receipts'), findsNothing);
      expect(cloud.accounts['u']!.receiptId, isNull);
      expect(cloud.accounts['u']!.viewedAt, isNull);
      expect(cloud.accounts['u']!.firstOpenedAt, 100);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        fixture(child: const NativeOnboardingScreen(), cloud: cloud),
      );
      await tester.pumpAndSettle();
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.textContaining('We couldn’t'), findsNothing);
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

class _SelectedReceiptFilePicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([
    PlatformFile(
      name: 'Replacement receipt.pdf',
      size: 4,
      bytes: Uint8List.fromList([37, 80, 68, 70]),
    ),
  ]);
}
