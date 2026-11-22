import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
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
import 'package:recieptnest_ai/src/features/home/presentation/home_screen.dart';
import 'package:recieptnest_ai/src/features/receipts/data/receipt_repository.dart';
import 'package:recieptnest_ai/src/features/receipts/data/receipt_upload_activity.dart';
import 'package:recieptnest_ai/src/features/receipts/models/receipt.dart';
import 'package:recieptnest_ai/src/features/receipts/presentation/receipt_upload_outcome.dart';
import 'package:recieptnest_ai/src/features/receipts/presentation/receipt_upload_result.dart';
import 'package:recieptnest_ai/src/features/shell/presentation/app_shell_screen.dart';
import 'support/onboarding_fakes.dart';

final captureKey = GlobalKey();

class UploadTestRepository extends MemoryReceiptRepository {
  UploadTestRepository()
    : super([
        for (var i = 0; i < 8; i++)
          exampleReceipt(id: 'existing-$i', date: '2026-11-21', amount: 10),
      ]);
  Completer<void>? transfer;
  bool fail = false;
  bool finishImmediately = false;
  final attempts = <String>[];
  @override
  Future<Receipt> uploadReceipt({
    required String userId,
    required UploadFileData file,
    PublicAppConfig? appConfig,
    ValueChanged<double>? onProgress,
    String? uploadId,
  }) async {
    attempts.add(uploadId!);
    onProgress?.call(.64);
    await transfer?.future;
    if (fail) {
      throw FirebaseException(plugin: 'firebase_storage', code: 'unavailable');
    }
    uploads.add(uploadId);
    final receipt = finishImmediately
        ? exampleReceipt(id: uploadId, date: '2026-08-14')
        : Receipt(
            id: uploadId,
            userId: userId,
            status: ReceiptStatuses.processing,
            file: ReceiptFile(
              storagePath: 'users/u/receipts/$uploadId.pdf',
              originalName: file.name,
              mimeType: 'application/pdf',
              sizeBytes: file.sizeBytes,
              uploadedAt: DateTime.now(),
            ),
            createdAt: DateTime.now(),
          );
    publishReceipt(receipt);
    onProgress?.call(1);
    return receipt;
  }
}

GoRouter testRouter() => GoRouter(
  initialLocation: '/app/home',
  routes: [
    ShellRoute(
      builder: (context, state, child) =>
          AppShellScreen(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/app/home', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/app/insights',
          builder: (_, _) => const Center(child: Text('Another app tab')),
        ),
      ],
    ),
    GoRoute(
      path: '/app/receipt/:id',
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Receipt details destination')),
        body: Text(state.pathParameters['id']!),
      ),
    ),
  ],
);

Widget app(
  UploadTestRepository repository,
  GoRouter router, {
  bool dark = true,
  double textScale = 1,
  StateProvider<String?>? userState,
  StateProvider<bool>? connectionDown,
}) => ProviderScope(
  overrides: [
    currentUserIdProvider.overrideWith(
      (ref) => userState == null ? 'u' : ref.watch(userState),
    ),
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
    receiptRepositoryProvider.overrideWithValue(repository),
    receiptsStreamProvider.overrideWith(
      (ref) => ref.watch(currentUserIdProvider) == 'u'
          ? repository.receiptChanges
          : Stream.value([]),
    ),
    receiptWatchProvider.overrideWith(
      (ref, id) => ref.watch(currentUserIdProvider) != 'u'
          ? Stream.value(null)
          : connectionDown != null && ref.watch(connectionDown)
          ? Stream.error(
              FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
            )
          : repository.receiptChangesFor(id),
    ),
    receiptFileUrlProvider.overrideWith(
      (ref, path) => repository.getReceiptFileUrl(path),
    ),
    selectedMonthProvider.overrideWith((ref) => 11),
    selectedYearProvider.overrideWith((ref) => 2026),
    nativeOnboardingRepositoryProvider.overrideWithValue(
      FakeNativeCloud(count: 8, status: 'completed').repository(),
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
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: RepaintBoundary(key: captureKey, child: child!),
    ),
  ),
);

void viewport(WidgetTester tester, [Size size = const Size(390, 844)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('output/upload').create(recursive: true);
    await File(
      'output/upload/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> chooseFile(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Files'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Upload receipt'));
  await tester.tap(find.text('Upload receipt'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FilePicker.platform = TestFilePicker();
  });

  testWidgets(
    'PDF upload stays visible, reveals its actual month, and keeps the dashboard month unchanged',
    (tester) async {
      viewport(tester);
      final repository = UploadTestRepository();
      addTearDown(repository.dispose);
      final router = testRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(app(repository, router));
      await tester.pumpAndSettle();
      await chooseFile(tester);
      expect(find.text('Upload saved'), findsOneWidget);
      expect(find.text('Reading your receipt'), findsOneWidget);
      expect(find.text('Sample café receipt.pdf'), findsOneWidget);
      await shot(tester, 'reading-dark');
      final id = repository.uploads.single;
      repository.publishReceipt(exampleReceipt(id: id, date: '2026-08-14'));
      await tester.pumpAndSettle();
      expect(find.text('Filed under'), findsOneWidget);
      expect(find.text('August 2026'), findsOneWidget);
      expect(find.text('View August'), findsOneWidget);
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      expect(scope.read(selectedMonthProvider), 11);
      expect(scope.read(selectedMonthSpendProvider), 80);
      await shot(tester, 'ready-dark');
      await tester.tap(find.text('View August'));
      await tester.pumpAndSettle();
      expect(scope.read(selectedMonthProvider), 8);
      expect(scope.read(selectedMonthSpendProvider), 12.5);
      expect(find.byType(ReceiptUploadOutcome), findsNothing);
      expect(scope.read(receiptUploadActivityProvider), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'minimized progress follows the exact receipt across tabs and becomes a ready banner',
    (tester) async {
      viewport(tester);
      final repository = UploadTestRepository();
      addTearDown(repository.dispose);
      final router = testRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(app(repository, router));
      await tester.pumpAndSettle();
      await chooseFile(tester);
      await tester.ensureVisible(find.text('Continue browsing'));
      await tester.tap(find.text('Continue browsing'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('receipt-upload-activity')),
        findsOneWidget,
      );
      expect(find.text('Your receipt is being organized'), findsOneWidget);
      router.go('/app/insights');
      await tester.pumpAndSettle();
      expect(find.text('Your receipt is being organized'), findsOneWidget);
      repository.finishProcessing(repository.uploads.single);
      await tester.pumpAndSettle();
      expect(find.text('Your receipt is ready'), findsOneWidget);
      await shot(tester, 'ready-activity');
      await tester.tap(find.byKey(const ValueKey('receipt-upload-activity')));
      await tester.pumpAndSettle();
      expect(find.text('Your local café'), findsOneWidget);
      await tester.tap(find.byTooltip('Close receipt result'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('receipt-upload-activity')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'the transfer shows real progress immediately and prevents accidental dismissal',
    (tester) async {
      viewport(tester);
      final repository = UploadTestRepository()..transfer = Completer<void>();
      addTearDown(repository.dispose);
      final router = testRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(app(repository, router));
      await tester.pumpAndSettle();
      await chooseFile(tester);
      expect(find.text('64%'), findsOneWidget);
      expect(find.text('On its way.'), findsOneWidget);
      expect(find.text('Upload saved'), findsNothing);
      await Navigator.of(tester.element(find.text('64%'))).maybePop();
      await tester.pump();
      expect(find.text('64%'), findsOneWidget);
      repository.transfer!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.uploads, hasLength(1));
      expect(find.text('Upload saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'failed uploads retain the selected file and reuse the same identity on retry',
    (tester) async {
      viewport(tester);
      final repository = UploadTestRepository()..fail = true;
      addTearDown(repository.dispose);
      final router = testRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(app(repository, router));
      await tester.pumpAndSettle();
      await chooseFile(tester);
      await tester.pumpAndSettle();
      expect(find.text('Sample café receipt.pdf'), findsOneWidget);
      expect(find.text('Try upload again'), findsOneWidget);
      expect(repository.uploads, isEmpty);
      repository.fail = false;
      await tester.ensureVisible(find.text('Try upload again'));
      await tester.tap(find.text('Try upload again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.attempts, hasLength(2));
      expect(repository.attempts.toSet(), hasLength(1));
      expect(find.text('Upload saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a result that is already ready appears without a minimum processing delay',
    (tester) async {
      viewport(tester);
      final repository = UploadTestRepository()..finishImmediately = true;
      addTearDown(repository.dispose);
      final router = testRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(app(repository, router, dark: false));
      await tester.pumpAndSettle();
      await chooseFile(tester);
      await tester.pumpAndSettle();
      expect(find.text('Receipt organized'), findsOneWidget);
      expect(find.text('Reading your receipt'), findsNothing);
      await shot(tester, 'ready-light');
      await tester.tap(find.text('Add another receipt'));
      await tester.pumpAndSettle();
      expect(find.text('Add your receipt'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(find.text('Sample café receipt.pdf'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'missing extraction fields invite review and never claim a finished receipt',
    (tester) async {
      viewport(tester);
      final repository = UploadTestRepository();
      addTearDown(repository.dispose);
      final router = testRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(app(repository, router));
      await tester.pumpAndSettle();
      await chooseFile(tester);
      final id = repository.uploads.single;
      repository.publishReceipt(
        Receipt(
          id: id,
          userId: 'u',
          status: ReceiptStatuses.needsReview,
          file: repository.records[id]!.file,
          createdAt: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Check receipt details'), findsOneWidget);
      expect(find.text('Amount needs review'), findsOneWidget);
      expect(find.text('Date needs review'), findsOneWidget);
      expect(find.text('Receipt organized'), findsNothing);
      expect(find.text('Filed under'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('large text on a narrow phone keeps result actions reachable', (
    tester,
  ) async {
    viewport(tester, const Size(320, 568));
    final repository = UploadTestRepository()..finishImmediately = true;
    addTearDown(repository.dispose);
    final router = testRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(app(repository, router, textScale: 1.6));
    await tester.pumpAndSettle();
    await chooseFile(tester);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View receipt'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('View receipt')).bottom, lessThan(568));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'deleting an upload clears its activity without showing false processing',
    (tester) async {
      viewport(tester);
      final repository = UploadTestRepository();
      addTearDown(repository.dispose);
      final router = testRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(app(repository, router));
      await tester.pumpAndSettle();
      await chooseFile(tester);
      final receipt = repository.records[repository.uploads.single]!;
      await repository.deleteReceipt('u', receipt);
      await tester.pumpAndSettle();
      expect(find.textContaining('This receipt was deleted.'), findsOneWidget);
      expect(find.text('Reading your receipt'), findsNothing);
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      expect(scope.read(receiptUploadActivityProvider), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'restored activity opens the saved receipt without another upload',
    (tester) async {
      viewport(tester);
      SharedPreferences.setMockInitialValues({
        'receipt_upload_activity_v1:u': jsonEncode([
          {
            'id': 'resumed',
            'startedAt': '2026-11-22T10:00:00',
            'guided': false,
          },
        ]),
      });
      final repository = UploadTestRepository();
      addTearDown(repository.dispose);
      repository.publishReceipt(
        exampleReceipt(id: 'resumed', status: ReceiptStatuses.processing),
      );
      final router = testRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(app(repository, router));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('receipt-upload-activity')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Upload saved'), findsOneWidget);
      repository.finishProcessing('resumed');
      await tester.pumpAndSettle();
      expect(find.text('Receipt organized'), findsOneWidget);
      expect(repository.uploads, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'connection errors preserve a saved receipt and retry checking without reuploading',
    (tester) async {
      viewport(tester);
      final repository = UploadTestRepository();
      addTearDown(repository.dispose);
      final down = StateProvider<bool>((ref) => false);
      final router = testRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(app(repository, router, connectionDown: down));
      await tester.pumpAndSettle();
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      await chooseFile(tester);
      scope.read(down.notifier).state = true;
      await tester.pumpAndSettle();
      expect(find.text('Check progress again'), findsOneWidget);
      expect(find.textContaining('Your upload is saved.'), findsOneWidget);
      expect(repository.uploads, hasLength(1));
      scope.read(down.notifier).state = false;
      repository.finishProcessing(repository.uploads.single);
      await tester.tap(find.text('Check progress again'));
      await tester.pumpAndSettle();
      expect(find.text('Receipt organized'), findsOneWidget);
      expect(repository.uploads, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('multiple minimized uploads keep independent live results', (
    tester,
  ) async {
    viewport(tester);
    final repository = UploadTestRepository();
    addTearDown(repository.dispose);
    final router = testRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(app(repository, router));
    await tester.pumpAndSettle();
    await chooseFile(tester);
    await tester.ensureVisible(find.text('Continue browsing'));
    await tester.tap(find.text('Continue browsing'));
    await tester.pumpAndSettle();
    await chooseFile(tester);
    await tester.ensureVisible(find.text('Continue browsing'));
    await tester.tap(find.text('Continue browsing'));
    await tester.pumpAndSettle();
    expect(find.text('2 recent uploads'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('receipt-upload-activity')));
    await tester.pumpAndSettle();
    repository.finishProcessing(repository.uploads.first);
    await tester.pumpAndSettle();
    expect(find.text('Receipt organized'), findsOneWidget);
    expect(find.text('Upload saved · Reading details'), findsOneWidget);
    await tester.tap(find.text('Your local café'));
    await tester.pumpAndSettle();
    expect(find.byType(ReceiptUploadResult), findsOneWidget);
    await tester.tap(find.byTooltip('Close receipt result'));
    await tester.pumpAndSettle();
    expect(find.text('Your receipt is being organized'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'an account change closes the old upload and ignores its late completion',
    (tester) async {
      viewport(tester);
      final repository = UploadTestRepository()..transfer = Completer<void>();
      addTearDown(repository.dispose);
      final user = StateProvider<String?>((ref) => 'u');
      final router = testRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(app(repository, router, userState: user));
      await tester.pumpAndSettle();
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      await chooseFile(tester);
      scope.read(user.notifier).state = 'different-user';
      await tester.pumpAndSettle();
      expect(find.text('64%'), findsNothing);
      repository.transfer!.complete();
      await tester.pumpAndSettle();
      expect(scope.read(receiptUploadActivityProvider), isEmpty);
      expect(
        find.byKey(const ValueKey('receipt-upload-activity')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('viewing the result opens its exact receipt above the sheet', (
    tester,
  ) async {
    viewport(tester);
    final repository = UploadTestRepository()..finishImmediately = true;
    addTearDown(repository.dispose);
    final router = testRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(app(repository, router));
    await tester.pumpAndSettle();
    await chooseFile(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View receipt'));
    await tester.pumpAndSettle();
    expect(find.text('Receipt details destination'), findsOneWidget);
    expect(find.text(repository.uploads.single), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'a missing receipt date must never become the upload month in the result',
    () {
      final value = Receipt(
        id: 'x',
        userId: 'u',
        status: ReceiptStatuses.needsReview,
        file: exampleReceipt().file,
        createdAt: DateTime(2026, 11, 22),
      );
      expect(value.effectiveDate, isNotNull);
      expect(receiptTransactionDate(value), isNull);
      expect(receiptUploadNeedsReview(value), isTrue);
    },
  );
}

class TestFilePicker extends FilePicker {
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
      name: 'Sample café receipt.pdf',
      size: 4,
      bytes: Uint8List.fromList([37, 80, 68, 70]),
    ),
  ]);
}
