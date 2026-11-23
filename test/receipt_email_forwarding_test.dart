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
import 'package:recieptnest_ai/src/core/config/public_app_config.dart';
import 'package:recieptnest_ai/src/core/theme/app_theme.dart';
import 'package:recieptnest_ai/src/features/auth/data/auth_repository.dart';
import 'package:recieptnest_ai/src/features/auth/models/user_profile.dart';
import 'package:recieptnest_ai/src/features/getting_started/data/native_onboarding_repository.dart';
import 'package:recieptnest_ai/src/features/getting_started/data/onboarding_analytics.dart';
import 'package:recieptnest_ai/src/features/getting_started/presentation/native_onboarding_screen.dart';
import 'package:recieptnest_ai/src/features/home/presentation/home_screen.dart';
import 'package:recieptnest_ai/src/features/receipts/data/receipt_email_forwarding.dart';
import 'package:recieptnest_ai/src/features/receipts/data/receipt_repository.dart';
import 'package:recieptnest_ai/src/features/receipts/data/receipt_upload_activity.dart';
import 'package:recieptnest_ai/src/features/receipts/presentation/forward_email_screen.dart';
import 'package:recieptnest_ai/src/features/receipts/presentation/upload_receipt_sheet.dart';
import 'support/onboarding_fakes.dart';
import 'package:recieptnest_ai/src/features/shell/presentation/app_shell_screen.dart';
import 'package:recieptnest_ai/src/features/auth/data/account_local_state.dart';

const _profile = UserProfile(
  id: 'u',
  firstName: 'Alex',
  lastName: '',
  email: 'alex@example.test',
);
final _account = StateProvider<String?>((ref) => 'u');
final _capture = GlobalKey();
String? _clipboard;

class _ForwardRepository extends MemoryReceiptRepository {
  _ForwardRepository({this.address = 'alex@receipts.example.com'});
  final String address;
  int calls = 0;
  bool fail = false;
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> generateForwardingAddress() async {
    calls++;
    if (pending != null) return pending!.future;
    if (fail) throw StateError('offline');
    return {'emailAddress': address};
  }
}

ProviderContainer _container(
  _ForwardRepository repo, {
  UserProfile? profile,
  Stream<UserProfile?>? profiles,
  String? uid = 'u',
}) => ProviderContainer(
  overrides: [
    currentUserIdProvider.overrideWithValue(uid),
    currentUserProfileProvider.overrideWith(
      (ref) => profiles ?? Stream.value(profile ?? _profile),
    ),
    receiptRepositoryProvider.overrideWithValue(repo),
  ],
);

Future<GoRouter> _screen(
  WidgetTester tester,
  _ForwardRepository repo, {
  String initial = '/app/forward-email',
  bool dark = false,
  Size size = const Size(390, 844),
  double scale = 1,
  FakeNativeCloud? cloud,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/app/forward-email',
        builder: (_, state) => const ForwardEmailScreen(),
      ),
      GoRoute(
        path: '/app/onboarding',
        builder: (_, state) => const NativeOnboardingScreen(),
      ),
      GoRoute(
        path: '/app/home',
        builder: (_, state) =>
            const AppShellScreen(location: '/app/home', child: HomeScreen()),
      ),
      GoRoute(
        path: '/app/receipt/:id',
        builder: (_, state) => const Scaffold(body: Text('Receipt details')),
      ),
      GoRoute(
        path: '/upload',
        builder: (_, state) => Scaffold(
          body: UploadReceiptSheet(
            userId: 'u',
            repository: repo,
            onUploaded: (_) {},
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('u'),
        currentUserProfileProvider.overrideWith(
          (ref) => Stream.value(_profile),
        ),
        receiptRepositoryProvider.overrideWithValue(repo),
        receiptWatchProvider.overrideWith(
          (ref, id) => repo.receiptChangesFor(id),
        ),
        publicAppConfigProvider.overrideWith(
          (ref) => Stream.value(const PublicAppConfig()),
        ),
        nativeOnboardingRepositoryProvider.overrideWithValue(
          (cloud ?? FakeNativeCloud()).repository(),
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
          child: RepaintBoundary(key: _capture, child: child!),
        ),
      ),
    ),
  );
  return router;
}

Future<void> screenshot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    await precacheImage(
      const AssetImage('assets/images/receipt-nest.png'),
      _capture.currentContext!,
    );
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('output/forward-email').create(recursive: true);
    await File(
      'output/forward-email/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      '.SF Pro Display',
    )..addFont(rootBundle.load('assets/fonts/Manrope.ttf'))).load();
    await (FontLoader(
      'Manrope',
    )..addFont(rootBundle.load('assets/fonts/Manrope.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            _clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') return {'text': _clipboard};
          return null;
        });
  });

  test(
    'a zero-receipt account gets an address; an existing address is reused',
    () async {
      final repo = _ForwardRepository();
      final fresh = _container(repo);
      addTearDown(fresh.dispose);
      expect(
        await fresh.read(receiptForwardingAddressProvider.future),
        repo.address,
      );
      expect(repo.calls, 1);
      final existing = _container(
        repo,
        profile: const UserProfile(
          id: 'u',
          firstName: 'Alex',
          lastName: '',
          email: 'alex@example.test',
          receiptForwardingAddress: 'existing@receipts.example.com',
        ),
      );
      addTearDown(existing.dispose);
      expect(
        await existing.read(receiptForwardingAddressProvider.future),
        'existing@receipts.example.com',
      );
      expect(repo.calls, 1);
    },
  );

  test(
    'signed-out and mismatched accounts never allocate an address',
    () async {
      final repo = _ForwardRepository();
      final signedOut = _container(repo, uid: null);
      addTearDown(signedOut.dispose);
      expect(
        await signedOut.read(receiptForwardingAddressProvider.future),
        isNull,
      );
      final wrong = _container(
        repo,
        profile: const UserProfile(
          id: 'other',
          firstName: 'Other',
          lastName: '',
          email: 'other@example.test',
        ),
      );
      addTearDown(wrong.dispose);
      await expectLater(
        wrong.read(receiptForwardingAddressProvider.future),
        throwsStateError,
      );
      expect(repo.calls, 0);
    },
  );

  test(
    'account creation waits for profile loading before allocating',
    () async {
      final repo = _ForwardRepository();
      final profiles = StreamController<UserProfile?>();
      final scope = _container(repo, profiles: profiles.stream);
      addTearDown(scope.dispose);
      final listener = scope.listen(
        receiptForwardingAddressProvider,
        (_, _) {},
      );
      addTearDown(listener.close);
      final result = scope.read(receiptForwardingAddressProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls, 0);
      profiles.add(_profile);
      expect(await result, repo.address);
      await profiles.close();
    },
  );

  test(
    'an empty or malformed server response cannot be copied as an address',
    () async {
      final repo = _ForwardRepository(address: 'not-an-address');
      final scope = _container(repo);
      addTearDown(scope.dispose);
      await expectLater(
        scope.read(receiptForwardingAddressProvider.future),
        throwsStateError,
      );
    },
  );

  test(
    'a profile that is still being created automatically recovers when ready',
    () async {
      final repo = _ForwardRepository();
      final profiles = StreamController<UserProfile?>();
      final scope = _container(repo, profiles: profiles.stream);
      addTearDown(scope.dispose);
      final listener = scope.listen(
        receiptForwardingAddressProvider,
        (_, _) {},
      );
      addTearDown(listener.close);
      profiles.add(null);
      await expectLater(
        scope.read(receiptForwardingAddressProvider.future),
        throwsStateError,
      );
      profiles.add(_profile);
      await Future<void>.delayed(Duration.zero);
      expect(
        await scope.read(receiptForwardingAddressProvider.future),
        repo.address,
      );
      await profiles.close();
    },
  );

  test(
    'account deletion clears the forwarding checkpoint only for that account',
    () async {
      SharedPreferences.setMockInitialValues({
        'receipt_email_pending_v1:u': 'pending',
        'receipt_email_pending_v1:other': 'keep',
      });
      await clearDeletedAccountLocalState('u');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('receipt_email_pending_v1:u'), isFalse);
      expect(prefs.getString('receipt_email_pending_v1:other'), 'keep');
    },
  );

  test(
    'account switch discards an in-flight address and starts the next account cleanly',
    () async {
      final repo = _ForwardRepository()..pending = Completer();
      final scope = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWith((ref) => ref.watch(_account)),
          currentUserProfileProvider.overrideWith(
            (ref) => Stream.value(
              UserProfile(
                id: ref.watch(currentUserIdProvider)!,
                firstName: 'Test',
                lastName: '',
                email: 'test@example.test',
              ),
            ),
          ),
          receiptRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(scope.dispose);
      final sub = scope.listen(receiptForwardingAddressProvider, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      final old = repo.pending!;
      repo.pending = null;
      scope.read(_account.notifier).state = 'other';
      expect(
        await scope.read(receiptForwardingAddressProvider.future),
        repo.address,
      );
      old.complete({'emailAddress': 'old@receipts.example.com'});
      await Future<void>.delayed(Duration.zero);
      expect(scope.read(receiptForwardingAddressProvider).value, repo.address);
    },
  );

  test(
    'historical emails stay quiet; each newly arriving email is tracked once',
    () async {
      final activity = ReceiptUploadActivityController('u');
      final arrivals = EmailReceiptArrivalController('u', activity);
      addTearDown(arrivals.dispose);
      addTearDown(activity.dispose);
      await arrivals.restored;
      final old = exampleReceipt(id: 'old', source: 'email');
      final incoming = exampleReceipt(
        id: 'new',
        source: 'email',
        createdAt: DateTime.now(),
        date: '2026-08-19',
      );
      arrivals.observe([old]);
      expect(activity.state, isEmpty);
      arrivals.observe([incoming, old, exampleReceipt(id: 'photo')]);
      arrivals.observe([incoming, old]);
      expect(activity.state.single.id, 'new');
      expect(activity.state.single.seed!.date, '2026-08-19');
      expect(activity.state.single.first, isFalse);
      await activity.settled;
    },
  );

  test(
    'copying records an expectation, not a receipt; arrival survives restarting the app',
    () async {
      final firstActivity = ReceiptUploadActivityController('u');
      final first = EmailReceiptArrivalController('u', firstActivity);
      await first.restored;
      final old = exampleReceipt(
        id: 'old',
        source: 'email',
        createdAt: DateTime.now(),
      );
      first.observe([old]);
      first.expectReceipt();
      await first.settled;
      expect(firstActivity.state, isEmpty);
      first.dispose();
      firstActivity.dispose();
      final activity = ReceiptUploadActivityController('u');
      final restarted = EmailReceiptArrivalController('u', activity);
      addTearDown(restarted.dispose);
      addTearDown(activity.dispose);
      final arrived = exampleReceipt(
        id: 'arrived',
        source: 'email',
        createdAt: DateTime.now(),
      );
      restarted.observe([arrived, old]);
      await restarted.restored;
      expect(activity.state.single.id, 'arrived');
      await restarted.settled;
      await activity.settled;
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('receipt_email_pending_v1:u'), isFalse);
    },
  );

  test('pending email and arrivals never cross accounts', () async {
    final firstActivity = ReceiptUploadActivityController('u');
    final first = EmailReceiptArrivalController('u', firstActivity);
    addTearDown(first.dispose);
    addTearDown(firstActivity.dispose);
    first.observe([]);
    first.expectReceipt();
    await first.settled;
    final activity = ReceiptUploadActivityController('other');
    final other = EmailReceiptArrivalController('other', activity);
    addTearDown(other.dispose);
    addTearDown(activity.dispose);
    await other.restored;
    other.observe([]);
    other.observe([exampleReceipt(source: 'email')]);
    expect(activity.state, isEmpty);
    expect(other.state, isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'forwarding is clear in ${dark ? 'dark' : 'light'} mode and copying does not finish onboarding',
      (tester) async {
        final repo = _ForwardRepository();
        final cloud = FakeNativeCloud();
        await _screen(tester, repo, dark: dark, cloud: cloud);
        await tester.pumpAndSettle();
        expect(find.text(repo.address), findsOneWidget);
        await screenshot(tester, dark ? 'dark' : 'light');
        await tester.tap(find.text('Copy address'));
        await tester.pumpAndSettle();
        expect(_clipboard, repo.address);
        expect(find.text('Address copied'), findsOneWidget);
        expect(find.text('Receipt saved'), findsNothing);
        expect(cloud.writes, isEmpty);
        await tester.ensureVisible(find.text('Back to Home'));
        await tester.tap(find.text('Back to Home'));
        await tester.pumpAndSettle();
        expect(find.text('Add my first receipt'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await repo.dispose();
      },
    );
  }

  testWidgets('address errors are retryable and never disable returning Home', (
    tester,
  ) async {
    final repo = _ForwardRepository()..fail = true;
    await _screen(tester, repo);
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Copy address'), findsNothing);
    expect(find.text('Back to Home'), findsOneWidget);
    repo.fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text(repo.address), findsOneWidget);
    expect(repo.calls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await repo.dispose();
  });

  testWidgets(
    'new email shows the actual receipt and purchase month without requiring an upload',
    (tester) async {
      final repo = _ForwardRepository();
      await _screen(tester, repo);
      await tester.pumpAndSettle();
      repo.publishReceipt(
        exampleReceipt(
          source: 'email',
          date: '2026-08-19',
          createdAt: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your receipt is here.'), findsOneWidget);
      expect(find.text('August 2026'), findsOneWidget);
      expect(find.text('View receipt'), findsOneWidget);
      await screenshot(tester, 'received');
      await tester.ensureVisible(find.text('View receipt'));
      await tester.tap(find.text('View receipt'));
      await tester.pumpAndSettle();
      expect(find.text('Receipt details'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await repo.dispose();
    },
  );

  testWidgets(
    'new users can find forwarding on empty Home and in the first-receipt guide',
    (tester) async {
      final repo = _ForwardRepository();
      final router = await _screen(tester, repo, initial: '/app/home');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Forward an email'));
      await tester.tap(find.text('Forward an email'));
      await tester.pumpAndSettle();
      expect(find.text(repo.address), findsOneWidget);
      router.go('/app/onboarding');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Forward an email'));
      await screenshot(tester, 'choose');
      await tester.tap(find.text('Forward an email'));
      await tester.pumpAndSettle();
      expect(find.text(repo.address), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await repo.dispose();
    },
  );

  testWidgets(
    'a forwarded receipt stays visible on Home after returning from the mail app',
    (tester) async {
      final repo = _ForwardRepository();
      await _screen(tester, repo);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy address'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Back to Home'));
      await tester.tap(find.text('Back to Home'));
      await tester.pumpAndSettle();
      repo.publishReceipt(
        exampleReceipt(
          id: 'email-on-home',
          source: 'email',
          createdAt: DateTime.now(),
          date: '2026-08-19',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('receipt-upload-activity')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('featured-recent-receipt')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('receipt-upload-activity')));
      await tester.pumpAndSettle();
      expect(find.text('Your receipt is here.'), findsOneWidget);
      expect(find.text('August 2026'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      await repo.dispose();
    },
  );

  testWidgets('onboarding continues with the email that actually arrived', (
    tester,
  ) async {
    final repo = _ForwardRepository();
    final cloud = FakeNativeCloud();
    final router = await _screen(
      tester,
      repo,
      initial: '/app/onboarding',
      cloud: cloud,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Forward an email'));
    await tester.tap(find.text('Forward an email'));
    await tester.pumpAndSettle();
    repo.publishReceipt(
      exampleReceipt(
        id: 'first-email',
        source: 'email',
        createdAt: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your receipt is here.'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Your receipt is here.'), findsOneWidget);
    expect(
      cloud.writes.any(
        (write) =>
            write['action'] == 'upload' && write['receiptId'] == 'first-email',
      ),
      isTrue,
    );
    expect(cloud.writes.any((write) => write['action'] == 'complete'), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await repo.dispose();
  });

  testWidgets('the Add Receipt sheet opens the same forwarding screen', (
    tester,
  ) async {
    final repo = _ForwardRepository();
    await _screen(tester, repo, initial: '/app/home');
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(HomeScreen));
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (_) => UploadReceiptSheet(
          userId: 'u',
          repository: repo,
          onUploaded: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(UploadReceiptSheet),
        matching: find.widgetWithText(TextButton, 'Forward an email'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(repo.address), findsOneWidget);
    expect(find.byType(UploadReceiptSheet), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await repo.dispose();
  });

  testWidgets('long addresses and larger text remain usable on a small phone', (
    tester,
  ) async {
    final repo = _ForwardRepository(
      address: 'a.very.long.personal.receipt.address@receipts.example.com',
    );
    await _screen(tester, repo, size: const Size(320, 568), scale: 1.5);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Copy address'));
    expect(find.text('Copy address').hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.text('Back to Home'));
    expect(find.text('Back to Home').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await screenshot(tester, 'small-large-text');
    await tester.pumpWidget(const SizedBox.shrink());
    await repo.dispose();
  });
}
