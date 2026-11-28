import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfx/pdfx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:recieptnest_ai/src/core/theme/app_theme.dart';
import 'package:recieptnest_ai/src/features/auth/data/auth_repository.dart';
import 'package:recieptnest_ai/src/features/getting_started/data/onboarding_analytics.dart';
import 'package:recieptnest_ai/src/features/getting_started/data/native_onboarding_repository.dart';
import 'package:recieptnest_ai/src/features/receipts/data/receipt_file_preview.dart';
import 'package:recieptnest_ai/src/features/receipts/data/receipt_repository.dart';
import 'package:recieptnest_ai/src/features/receipts/models/receipt.dart';
import 'package:recieptnest_ai/src/features/receipts/presentation/receipt_file_preview.dart';
import 'package:recieptnest_ai/src/features/receipts/presentation/receipt_detail_screen.dart';
import 'support/onboarding_fakes.dart';

late Uint8List _png;
final _account = StateProvider<String?>((ref) => 'u');
final _capture = GlobalKey();

Receipt _receipt({
  String name = 'Receipt.pdf',
  String mime = 'application/pdf',
}) => Receipt(
  id: 'original',
  userId: 'u',
  status: ReceiptStatuses.finalStatus,
  file: ReceiptFile(
    storagePath: 'users/u/receipts/$name',
    originalName: name,
    mimeType: mime,
    sizeBytes: 1024,
  ),
  merchant: const ReceiptMerchant(
    canonicalId: null,
    canonicalName: 'Northside Market',
    rawName: 'Northside Market',
    matchConfidence: 1,
    matchedBy: 'manual',
  ),
  totalAmount: 43.20,
  date: '2026-10-15',
);

class _Files extends MemoryReceiptRepository {
  int downloads = 0;
  int externalRequests = 0;
  bool fail = false;
  Uint8List? data = Uint8List.fromList([37, 80, 68, 70, 45]);
  Completer<Uint8List?>? pending;
  @override
  Future<Uint8List?> getReceiptFileBytes(
    String path, {
    int maxSizeBytes = 50 * 1024 * 1024,
  }) async {
    downloads++;
    expect(maxSizeBytes, receiptPreviewMaxBytes);
    if (fail) throw StateError('offline');
    return pending?.future ?? data;
  }

  @override
  Future<String> getReceiptFileUrl(String path) async {
    externalRequests++;
    return 'https://example.test/original';
  }
}

class _Pdf extends Fake implements PdfDocument {
  _Pdf({this.pagesCount = 2, this.height = 840});
  @override
  final int pagesCount;
  final double height;
  final events = <String>[];
  bool closed = false;
  bool failRender = false;
  bool pageOpen = false;
  Completer<void>? pendingRender;
  final sizes = <Size>[];
  @override
  Future<PdfPage> getPage(int number, {bool autoCloseAndroid = false}) async {
    expect(closed, isFalse);
    expect(pageOpen, isFalse);
    events.add('open $number');
    pageOpen = true;
    return _Page(this, number);
  }

  @override
  Future<void> close() async {
    expect(pageOpen, isFalse);
    events.add('close document');
    closed = true;
  }
}

class _Page extends Fake implements PdfPage {
  _Page(this.doc, this.number);
  final _Pdf doc;
  final int number;
  @override
  double get width => 600;
  @override
  double get height => doc.height;
  @override
  Future<PdfPageImage?> render({
    required double width,
    required double height,
    PdfPageImageFormat format = PdfPageImageFormat.jpeg,
    String? backgroundColor,
    ui.Rect? cropRect,
    int quality = 100,
    bool forPrint = false,
    bool removeTempFile = true,
  }) async {
    expect(backgroundColor, '#FFFFFF');
    doc.sizes.add(Size(width, height));
    await doc.pendingRender?.future;
    if (doc.failRender) throw StateError('render failed');
    return _PageImage();
  }

  @override
  Future<void> close() async {
    doc.events.add('close $number');
    doc.pageOpen = false;
  }
}

class _PageImage extends Fake implements PdfPageImage {
  @override
  Uint8List get bytes => Uint8List.fromList(_png);
}

Future<void> _screen(
  WidgetTester tester, {
  Receipt? receipt,
  _Files? files,
  _Pdf? document,
  Future<PdfDocument> Function(Uint8List)? opener,
  bool dark = false,
  bool details = false,
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final item = receipt ?? _receipt();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWith((ref) => ref.watch(_account)),
        receiptRepositoryProvider.overrideWithValue(files ?? _Files()),
        receiptPdfOpenerProvider.overrideWithValue(
          opener ?? (_) async => document ?? _Pdf(),
        ),
        receiptWatchProvider.overrideWith((ref, id) => Stream.value(item)),
        onboardingAnalyticsProvider.overrideWithValue(SilentAnalytics()),
        nativeOnboardingRepositoryProvider.overrideWithValue(
          FakeNativeCloud().repository(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: _capture, child: child!),
        ),
        home: details
            ? ReceiptDetailScreen(receiptId: item.id)
            : Scaffold(
                appBar: AppBar(title: const Text('Receipt')),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ReceiptFilePreview(receipt: item),
                ),
              ),
      ),
    ),
  );
}

Future<void> _screenshot(WidgetTester tester, String name) async {
  // Widget tests must wait for the real image codec, not only for the Image
  // widget to exist; otherwise a blank canvas can falsely look like success.
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pumpAndSettle();
  expect(
    tester
        .widgetList<RawImage>(find.byType(RawImage))
        .any((image) => image.image != null),
    isTrue,
  );
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('output/receipt-preview').create(recursive: true);
    await File(
      'output/receipt-preview/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
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
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 900, 1260),
      Paint()..color = Colors.white,
    );
    void text(
      String value,
      double y, {
      double size = 28,
      FontWeight weight = FontWeight.w400,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: size,
            color: Colors.black,
            fontWeight: weight,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 760);
      painter.paint(canvas, Offset(70, y));
    }

    text('NORTHSIDE MARKET', 80, size: 42, weight: FontWeight.w700);
    text('Original receipt', 150);
    text('October 15, 2026', 205);
    canvas.drawLine(
      const Offset(70, 285),
      const Offset(830, 285),
      Paint()
        ..color = Colors.grey
        ..strokeWidth = 2,
    );
    text('Coffee                           5.20', 340);
    text('Lunch                           18.00', 415);
    text('Groceries                       20.00', 490);
    canvas.drawLine(
      const Offset(70, 610),
      const Offset(830, 610),
      Paint()
        ..color = Colors.grey
        ..strokeWidth = 2,
    );
    text('TOTAL     \$43.20', 670, size: 48, weight: FontWeight.w700);
    text('Paid by card', 770);
    text('Thank you for visiting.', 1000);
    final picture = recorder.endRecording();
    final image = await picture.toImage(900, 1260);
    _png = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
  });

  test(
    'PDF and image classification handles MIME types and case-insensitive extensions',
    () {
      expect(
        receiptPreviewKind(
          _receipt(name: 'scan.PDF', mime: 'application/octet-stream'),
        ),
        ReceiptPreviewKind.pdf,
      );
      expect(
        receiptPreviewKind(
          _receipt(name: 'original', mime: 'application/pdf; charset=binary'),
        ),
        ReceiptPreviewKind.pdf,
      );
      expect(
        receiptPreviewKind(
          _receipt(name: 'photo.HEIC', mime: 'application/octet-stream'),
        ),
        ReceiptPreviewKind.image,
      );
      expect(
        receiptPreviewKind(
          _receipt(name: 'file.docx', mime: 'application/msword'),
        ),
        ReceiptPreviewKind.unsupported,
      );
    },
  );

  test(
    'original bytes are private to the signed-in account and empty files fail',
    () async {
      final files = _Files();
      final scope = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue('u'),
          receiptRepositoryProvider.overrideWithValue(files),
        ],
      );
      addTearDown(scope.dispose);
      await expectLater(
        scope.read(
          receiptPreviewBytesProvider('users/other/receipts/file.pdf').future,
        ),
        throwsStateError,
      );
      expect(files.downloads, 0);
      files.data = Uint8List(0);
      await expectLater(
        scope.read(
          receiptPreviewBytesProvider('users/u/receipts/empty.pdf').future,
        ),
        throwsStateError,
      );
    },
  );

  testWidgets(
    'PDF pages render inside the app and close each page before opening the next',
    (tester) async {
      final doc = _Pdf();
      final files = _Files();
      await _screen(tester, files: files, document: doc);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(find.text('Open original file'), findsNothing);
      await _screenshot(tester, 'pdf-inline-light');
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(doc.events, ['open 1', 'close 1', 'open 2', 'close 2']);
      await tester.tap(find.byTooltip('Previous page'));
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(doc.closed, isTrue);
      expect(files.externalRequests, 0);
    },
  );

  testWidgets(
    'the single preview expand action opens the native PDF viewer with one shared download',
    (tester) async {
      final files = _Files();
      final docs = <_Pdf>[];
      await _screen(
        tester,
        files: files,
        details: true,
        opener: (_) async {
          final doc = _Pdf();
          docs.add(doc);
          return doc;
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('Receipt.pdf'), findsOneWidget);
      expect(find.byTooltip('View full receipt'), findsOneWidget);
      await tester.tap(find.byTooltip('View full receipt'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptOriginalScreen), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byTooltip('Fit receipt'), findsOneWidget);
      expect(files.downloads, 1);
      expect(files.externalRequests, 0);
      await _screenshot(tester, 'pdf-fullscreen');
      await tester.tap(find.byTooltip('Close receipt'));
      await tester.pumpAndSettle();
      expect(docs.last.closed, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(docs.every((doc) => doc.closed), isTrue);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'receipt details keep one clean preview and reveal details sooner in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        final files = _Files()..data = _png;
        const name = 'image_picker_B23E927B-42DA-46F2-8CE5-93CDDFCB5B0D.jpg';
        await _screen(
          tester,
          files: files,
          receipt: _receipt(name: name, mime: 'image/jpeg'),
          details: true,
          dark: dark,
        );
        await tester.pumpAndSettle();
        expect(find.byType(ReceiptFilePreview), findsOneWidget);
        expect(find.byTooltip('View full receipt'), findsOneWidget);
        expect(find.text('Original receipt'), findsOneWidget);
        expect(find.text('Receipt photo'), findsNothing);
        expect(find.text(name), findsNothing);
        expect(tester.getRect(find.text('Details')).bottom, lessThan(844));
        await _screenshot(tester, 'details-clean-${dark ? 'dark' : 'light'}');
        // The receipt image itself remains a second way to use the same viewer.
        await tester.tap(find.byType(Image).first);
        await tester.pumpAndSettle();
        expect(find.byType(ReceiptOriginalScreen), findsOneWidget);
        expect(find.byType(InteractiveViewer), findsOneWidget);
        expect(find.text('Receipt photo'), findsNothing);
        expect(find.text(name), findsNothing);
        expect(files.downloads, 1);
        await tester.tap(find.byTooltip('Close receipt'));
        await tester.pumpAndSettle();
        expect(find.byType(ReceiptDetailScreen), findsOneWidget);
        expect(files.externalRequests, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('photos open in a zoomable viewer in dark mode', (tester) async {
    final files = _Files()..data = _png;
    await _screen(
      tester,
      files: files,
      receipt: _receipt(name: 'receipt.jpg', mime: 'image/jpeg'),
      dark: true,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('View full receipt'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final image = find.byType(InteractiveViewer);
    final point = tester.getCenter(image);
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(1),
    );
    await tester.tap(find.byTooltip('Fit receipt'));
    await tester.pumpAndSettle();
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
    await _screenshot(tester, 'image-fullscreen-dark');
    expect(files.externalRequests, 0);
  });

  testWidgets('download failures offer a working in-app retry', (tester) async {
    final files = _Files()..fail = true;
    await _screen(tester, files: files);
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    files.fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(files.downloads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native render errors retry without reopening a browser or leaking a page',
    (tester) async {
      final doc = _Pdf()..failRender = true;
      final files = _Files();
      await _screen(tester, files: files, document: doc);
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      expect(doc.pageOpen, isFalse);
      doc.failRender = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(doc.pageOpen, isFalse);
      expect(files.externalRequests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(doc.closed, isTrue);
    },
  );

  testWidgets(
    'a document-open failure offers retry and can recover in the app',
    (tester) async {
      var calls = 0;
      final doc = _Pdf();
      await _screen(
        tester,
        opener: (_) async {
          if (calls++ == 0) throw StateError('damaged or encrypted document');
          return doc;
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'an empty PDF has a recoverable error instead of a blank success',
    (tester) async {
      final doc = _Pdf(pagesCount: 0);
      await _screen(tester, document: doc);
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(doc.closed, isTrue);
    },
  );

  testWidgets(
    'a document that opens after the viewer closes is released immediately',
    (tester) async {
      final pending = Completer<PdfDocument>();
      final doc = _Pdf();
      await _screen(tester, opener: (_) => pending.future);
      await tester.pump();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(doc);
      await tester.pump();
      await tester.pump();
      expect(doc.closed, isTrue);
      expect(doc.events, ['close document']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closing the screen during a native render releases page then document safely',
    (tester) async {
      final pending = Completer<void>();
      final doc = _Pdf()..pendingRender = pending;
      await _screen(tester, document: doc);
      await tester.pump();
      await tester.pump();
      expect(doc.pageOpen, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(doc.closed, isFalse);
      pending.complete();
      await tester.pump();
      await tester.pump();
      expect(doc.events.last, 'close document');
      expect(doc.pageOpen, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching accounts immediately hides the old receipt', (
    tester,
  ) async {
    final doc = _Pdf();
    await _screen(tester, document: doc);
    await tester.pumpAndSettle();
    final scope = ProviderScope.containerOf(
      tester.element(find.byType(ReceiptFilePreview)),
    );
    scope.read(_account.notifier).state = 'other';
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(doc.closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long PDF pages and small-screen controls remain bounded and readable',
    (tester) async {
      final doc = _Pdf(height: 100000);
      await _screen(
        tester,
        document: doc,
        size: const Size(320, 568),
        scale: 1.5,
      );
      await tester.pumpAndSettle();
      expect(doc.sizes.single.height, lessThanOrEqualTo(4096));
      expect(
        doc.sizes.single.width * doc.sizes.single.height,
        lessThanOrEqualTo(2048 * 4096),
      );
      await tester.ensureVisible(find.byTooltip('Next page'));
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
