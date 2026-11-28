import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:recieptnest_ai/src/core/config/public_app_config.dart';
import 'package:recieptnest_ai/src/features/receipts/data/receipt_repository.dart';
import 'package:recieptnest_ai/src/features/receipts/data/receipt_upload_activity.dart';
import 'package:recieptnest_ai/src/features/receipts/models/receipt.dart';
import 'package:recieptnest_ai/src/features/receipts/models/receipt_file_label.dart';
import 'package:recieptnest_ai/src/features/receipts/presentation/receipt_upload_batch.dart';
import 'package:recieptnest_ai/src/features/receipts/presentation/upload_receipt_sheet.dart';
import 'receipt_upload_flow_test.dart' as flow;

class BatchRepository extends flow.UploadTestRepository {
  final attemptsByName = <String, List<String>>{};
  final failures = <String>{};
  final validationErrors = <String, String>{};
  @override
  UploadValidationResult validateFile(
    UploadFileData file, {
    PublicAppConfig? appConfig,
  }) => UploadValidationResult(
    valid: !validationErrors.containsKey(file.name),
    error: validationErrors[file.name],
  );
  String? limitAt;
  Completer<void>? gate;
  int active = 0;
  int maximumActive = 0;
  @override
  Future<Receipt> uploadReceipt({
    required String userId,
    required UploadFileData file,
    PublicAppConfig? appConfig,
    ValueChanged<double>? onProgress,
    String? uploadId,
  }) async {
    attemptsByName.putIfAbsent(file.name, () => []).add(uploadId!);
    active++;
    if (active > maximumActive) maximumActive = active;
    try {
      await gate?.future;
      if (file.name == limitAt) {
        throw Exception(
          'Free plan includes up to 10 receipts total. Upgrade to add more.',
        );
      }
      if (failures.contains(file.name)) {
        throw FirebaseException(plugin: 'storage', code: 'unavailable');
      }
      return await super.uploadReceipt(
        userId: userId,
        file: file,
        uploadId: uploadId,
        appConfig: appConfig,
        onProgress: onProgress,
      );
    } finally {
      active--;
    }
  }
}

class MultiFilePicker extends flow.TestFilePicker {
  List<PlatformFile> files = [];
  bool? multiple;
  bool cancel = false;
  bool throwError = false;
  Completer<FilePickerResult?>? pending;
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
  }) async {
    multiple = allowMultiple;
    if (throwError) throw StateError('picker unavailable');
    if (pending != null) return pending!.future;
    return cancel ? null : FilePickerResult(files);
  }
}

class MultiImagePicker extends ImagePicker {
  List<XFile> images = [];
  int singleCalls = 0;
  int multiCalls = 0;
  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    multiCalls++;
    return images;
  }

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    singleCalls++;
    return images.firstOrNull;
  }
}

PlatformFile pdf(String name, {int size = 4}) => PlatformFile(
  name: name,
  size: size,
  bytes: Uint8List.fromList([37, 80, 68, 70]),
);

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
}

Future<void> selectFiles(WidgetTester tester) async {
  await tester.tap(find.text('Files'));
  await tester.pumpAndSettle();
}

Future<void> upload(WidgetTester tester, int count) async {
  await tester.tap(find.text('Upload $count files'));
  await tester.pumpAndSettle();
}

GoRouter sheetRouter(BatchRepository repository, {bool guided = false}) =>
    GoRouter(
      initialLocation: '/app/home',
      routes: [
        GoRoute(
          path: '/app/home',
          builder: (context, state) => Scaffold(
            floatingActionButton: FloatingActionButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                isDismissible: false,
                enableDrag: false,
                constraints: BoxConstraints(
                  maxWidth: 540,
                  maxHeight: MediaQuery.sizeOf(context).height * .92,
                ),
                builder: (_) => UploadReceiptSheet(
                  userId: 'u',
                  guided: guided,
                  repository: repository,
                  onUploaded: (_) {},
                ),
              ),
              child: const Icon(Icons.add),
            ),
          ),
        ),
      ],
    );

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
  late MultiFilePicker picker;
  setUp(() {
    picker = MultiFilePicker()
      ..files = [pdf('First.pdf'), pdf('Second.pdf'), pdf('Third.pdf')];
    FilePicker.platform = picker;
  });

  testWidgets(
    'one native selection supports multiple files and retries only failures with the same IDs',
    (tester) async {
      flow.viewport(tester);
      final repository = BatchRepository()..failures.add('Second.pdf');
      addTearDown(repository.dispose);
      final router = flow.testRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(flow.app(repository, router));
      await tester.pumpAndSettle();
      await openSheet(tester);
      await selectFiles(tester);
      expect(picker.multiple, isTrue);
      expect(find.text('3 files selected'), findsOneWidget);
      expect(find.text('Upload 3 files'), findsOneWidget);
      await flow.shot(tester, 'batch-selection-dark');
      await upload(tester, 3);
      expect(find.textContaining('2 of 3 files saved'), findsOneWidget);
      expect(repository.uploads, hasLength(2));
      expect(repository.maximumActive, 1);
      repository.failures.clear();
      await tester.tap(find.text('Retry 1 file'));
      await tester.pumpAndSettle();
      expect(find.textContaining('3 of 3 files saved'), findsOneWidget);
      expect(repository.attemptsByName['First.pdf'], hasLength(1));
      expect(repository.attemptsByName['Third.pdf'], hasLength(1));
      expect(repository.attemptsByName['Second.pdf'], hasLength(2));
      expect(repository.attemptsByName['Second.pdf']!.toSet(), hasLength(1));
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(UploadReceiptSheet)),
      );
      expect(scope.read(receiptUploadActivityProvider), hasLength(3));
      await flow.shot(tester, 'batch-saved-dark');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('saved batch rows follow extraction and open the exact receipt', (
    tester,
  ) async {
    flow.viewport(tester);
    final repository = BatchRepository();
    addTearDown(repository.dispose);
    final router = flow.testRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(flow.app(repository, router));
    await tester.pumpAndSettle();
    await openSheet(tester);
    await selectFiles(tester);
    await upload(tester, 3);
    expect(find.text('Saved · Reading details'), findsNWidgets(3));
    expect(find.text('View progress'), findsNWidgets(3));
    expect(find.text('Done'), findsNothing);
    expect(find.text('Continue browsing'), findsOneWidget);
    final id = repository.uploads[1];
    repository.finishProcessing(id);
    await tester.pumpAndSettle();
    expect(find.text('Your local café'), findsOneWidget);
    expect(find.text(r'$12.50 · Oct 1, 2026'), findsOneWidget);
    expect(find.text('1 ready · 2 reading details'), findsOneWidget);
    await flow.shot(tester, 'batch-mixed-results-dark');
    await tester.tap(find.text('View receipt'));
    await tester.pumpAndSettle();
    expect(find.text('Receipt details destination'), findsOneWidget);
    expect(find.text(id), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'picker cancellation and errors preserve previous selections; removal leaves a normal single upload',
    (tester) async {
      flow.viewport(tester);
      final repository = BatchRepository();
      addTearDown(repository.dispose);
      final router = flow.testRouter();
      addTearDown(router.dispose);
      picker.files = [pdf('First.pdf'), pdf('Second.pdf')];
      await tester.pumpWidget(flow.app(repository, router));
      await tester.pumpAndSettle();
      await openSheet(tester);
      await selectFiles(tester);
      picker.cancel = true;
      await selectFiles(tester);
      expect(find.text('2 files selected'), findsOneWidget);
      picker.throwError = true;
      await selectFiles(tester);
      expect(find.text('2 files selected'), findsOneWidget);
      expect(find.textContaining('Could not open file picker'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove Second.pdf'));
      await tester.pumpAndSettle();
      expect(find.text('1 file selected'), findsOneWidget);
      expect(find.text('Upload receipt'), findsOneWidget);
      await tester.tap(find.text('Upload receipt'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Upload saved'), findsOneWidget);
      expect(find.byType(ReceiptUploadBatch), findsNothing);
      expect(repository.uploads, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('each invalid file is explained without blocking valid files', (
    tester,
  ) async {
    flow.viewport(tester);
    final repository = BatchRepository();
    addTearDown(repository.dispose);
    final router = flow.testRouter();
    addTearDown(router.dispose);
    repository.validationErrors.addAll({
      'Empty.pdf': 'This file is empty. Please choose another receipt.',
      'Large.pdf': 'File too large. Maximum size is 10MB.',
    });
    picker.files = [
      pdf('Good.pdf'),
      pdf('Empty.pdf', size: 0),
      pdf('Large.pdf', size: 11 * 1024 * 1024),
    ];
    await tester.pumpWidget(flow.app(repository, router));
    await tester.pumpAndSettle();
    await openSheet(tester);
    await selectFiles(tester);
    await upload(tester, 3);
    expect(find.textContaining('1 of 3 files saved'), findsOneWidget);
    expect(find.textContaining('This file is empty'), findsOneWidget);
    expect(find.textContaining('File too large'), findsOneWidget);
    expect(repository.attemptsByName.keys, ['Good.pdf']);
    await tester.tap(find.byTooltip('Remove Empty.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove Large.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('Continue browsing'), findsOneWidget);
    expect(repository.uploads, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'free-plan limit leaves remaining files available without repeated server calls',
    (tester) async {
      flow.viewport(tester);
      final repository = BatchRepository()..limitAt = 'Second.pdf';
      addTearDown(repository.dispose);
      final router = flow.testRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(flow.app(repository, router));
      await tester.pumpAndSettle();
      await openSheet(tester);
      await selectFiles(tester);
      await upload(tester, 3);
      expect(repository.attemptsByName.keys, ['First.pdf', 'Second.pdf']);
      expect(find.textContaining('Free plan includes'), findsNWidgets(2));
      expect(find.text('Retry 2 files'), findsOneWidget);
      repository.limitAt = null;
      await tester.tap(find.text('Retry 2 files'));
      await tester.pumpAndSettle();
      expect(repository.uploads, hasLength(3));
      expect(repository.attemptsByName['First.pdf'], hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('account change stops the batch before any subsequent transfer', (
    tester,
  ) async {
    flow.viewport(tester);
    final repository = BatchRepository()..gate = Completer<void>();
    addTearDown(repository.dispose);
    final user = StateProvider<String?>((ref) => 'u');
    final router = flow.testRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(flow.app(repository, router, userState: user));
    await tester.pumpAndSettle();
    await openSheet(tester);
    await selectFiles(tester);
    final scope = ProviderScope.containerOf(
      tester.element(find.byType(UploadReceiptSheet)),
    );
    await tester.tap(find.text('Upload 3 files'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.attemptsByName, hasLength(1));
    await Navigator.of(
      tester.element(find.byType(ReceiptUploadBatch)),
    ).maybePop();
    await tester.pump();
    expect(find.byType(ReceiptUploadBatch), findsOneWidget);
    scope.read(user.notifier).state = 'other';
    await tester.pumpAndSettle();
    repository.gate!.complete();
    await tester.pumpAndSettle();
    expect(repository.attemptsByName, hasLength(1));
    expect(scope.read(receiptUploadActivityProvider), isEmpty);
    expect(find.byType(UploadReceiptSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'late picker completion cannot select files for another account',
    (tester) async {
      flow.viewport(tester);
      picker.pending = Completer<FilePickerResult?>();
      final repository = BatchRepository();
      addTearDown(repository.dispose);
      final user = StateProvider<String?>((ref) => 'u');
      final router = flow.testRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(flow.app(repository, router, userState: user));
      await tester.pumpAndSettle();
      await openSheet(tester);
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(UploadReceiptSheet)),
      );
      await tester.tap(find.text('Files'));
      await tester.pump();
      scope.read(user.notifier).state = 'other';
      await tester.pumpAndSettle();
      picker.pending!.complete(FilePickerResult(picker.files));
      await tester.pumpAndSettle();
      expect(repository.uploads, isEmpty);
      expect(find.byType(UploadReceiptSheet), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Gallery selects multiple photos in one visit; Camera appends a photo',
    (tester) async {
      flow.viewport(tester);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('receipt-picker-test'),
      ))!;
      addTearDown(() => dir.delete(recursive: true));
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jc1sAAAAASUVORK5CYII=',
      );
      final images = <XFile>[];
      for (var i = 0; i < 3; i++) {
        final file = File('${dir.path}/Photo-$i.png');
        await tester.runAsync(() => file.writeAsBytes(bytes));
        images.add(XFile.fromData(bytes, path: file.path));
      }
      final imagePicker = MultiImagePicker()..images = images.take(2).toList();
      final repository = BatchRepository();
      addTearDown(repository.dispose);
      final router = flow.testRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        flow.app(repository, router, imagePicker: imagePicker),
      );
      await tester.pumpAndSettle();
      await openSheet(tester);
      await tester.tap(find.text('Gallery'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(imagePicker.multiCalls, 1);
      expect(imagePicker.singleCalls, 0);
      expect(find.text('2 files selected'), findsOneWidget);
      // The same local photo is not appended twice.
      await tester.tap(find.text('Gallery'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('2 files selected'), findsOneWidget);
      imagePicker.images = [images.last];
      await tester.tap(find.text('Camera'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(imagePicker.singleCalls, 1);
      expect(find.text('3 files selected'), findsOneWidget);
      await upload(tester, 3);
      expect(repository.uploads, hasLength(3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'mixed file types and distinct files with the same name stay independent',
    (tester) async {
      flow.viewport(tester);
      final repository = BatchRepository();
      addTearDown(repository.dispose);
      final router = flow.testRouter();
      addTearDown(router.dispose);
      picker.files = [
        pdf('Receipt.pdf'),
        PlatformFile(
          name: 'Receipt.pdf',
          size: 4,
          bytes: Uint8List.fromList([37, 80, 68, 71]),
        ),
        pdf('Invoice.docx'),
        PlatformFile(
          name: 'Receipt.png',
          size: 68,
          bytes: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jc1sAAAAASUVORK5CYII=',
          ),
        ),
      ];
      await tester.pumpWidget(flow.app(repository, router));
      await tester.pumpAndSettle();
      await openSheet(tester);
      await selectFiles(tester);
      expect(find.text('4 files selected'), findsOneWidget);
      await upload(tester, 4);
      expect(repository.uploads.toSet(), hasLength(4));
      expect(repository.attemptsByName['Receipt.pdf']!.toSet(), hasLength(2));
      expect(
        repository.attemptsByName.keys,
        containsAll(['Invoice.docx', 'Receipt.png']),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('removing the last rejected file returns to an empty selection', (
    tester,
  ) async {
    flow.viewport(tester);
    final repository = BatchRepository()
      ..failures.addAll(['First.pdf', 'Second.pdf']);
    addTearDown(repository.dispose);
    final router = flow.testRouter();
    addTearDown(router.dispose);
    picker.files = [pdf('First.pdf'), pdf('Second.pdf')];
    await tester.pumpWidget(flow.app(repository, router));
    await tester.pumpAndSettle();
    await openSheet(tester);
    await selectFiles(tester);
    await upload(tester, 2);
    await tester.tap(find.byTooltip('Remove First.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove Second.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('Add receipts'), findsOneWidget);
    expect(find.text('Upload receipts'), findsOneWidget);
    expect(find.text('0 of 0 files saved'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the guided picker stays focused on one file', (tester) async {
    flow.viewport(tester);
    final repository = BatchRepository();
    addTearDown(repository.dispose);
    final router = sheetRouter(repository, guided: true);
    addTearDown(router.dispose);
    picker.files = [pdf('First.pdf')];
    await tester.pumpWidget(flow.app(repository, router));
    await tester.pumpAndSettle();
    await openSheet(tester);
    await selectFiles(tester);
    expect(picker.multiple, isFalse);
    expect(find.text('Looking good?'), findsOneWidget);
    await tester.tap(find.text('Upload receipt'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.uploads, hasLength(1));
    expect(find.byType(UploadReceiptSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'generated picker names have calm display labels without changing meaningful filenames',
    () {
      expect(receiptFileLabel('image_picker_123-456.jpg'), 'Receipt photo');
      expect(
        receiptFileLabel('IMAGE_PICKER_123-456.heic', receiptNumber: 2),
        'Receipt 2',
      );
      expect(
        receiptFileLabel(
          '12345678-abcd-1234-abcd-123456789abc.png',
          receiptNumber: 1,
        ),
        'Receipt 1',
      );
      expect(
        receiptFileLabel('Invoice November.pdf', receiptNumber: 1),
        'Invoice November.pdf',
      );
      expect(receiptFileLabel('IMG_1234.jpg'), 'IMG_1234.jpg');
    },
  );

  testWidgets(
    'generated filenames stay hidden through selection and progress while original uploads are preserved',
    (tester) async {
      flow.viewport(tester);
      final repository = BatchRepository();
      addTearDown(repository.dispose);
      final router = flow.testRouter();
      addTearDown(router.dispose);
      const first = 'image_picker_A1B2C3.pdf';
      const second = 'image_picker_D4E5F6.pdf';
      picker.files = [pdf(first), pdf(second)];
      await tester.pumpWidget(flow.app(repository, router));
      await tester.pumpAndSettle();
      await openSheet(tester);
      await selectFiles(tester);
      expect(find.text('Receipt 1'), findsOneWidget);
      expect(find.text('Receipt 2'), findsOneWidget);
      expect(find.text(first), findsNothing);
      expect(find.text(second), findsNothing);
      await upload(tester, 2);
      expect(repository.attemptsByName.keys, [first, second]);
      expect(find.text('Receipt 1'), findsOneWidget);
      expect(find.text('Receipt 2'), findsOneWidget);
      await tester.tap(find.text('View progress').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Receipt document'), findsOneWidget);
      expect(find.text(first), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Continue browsing preserves processing activity and result updates',
    (tester) async {
      flow.viewport(tester);
      final repository = BatchRepository();
      addTearDown(repository.dispose);
      final router = flow.testRouter();
      addTearDown(router.dispose);
      picker.files = [pdf('First.pdf'), pdf('Second.pdf')];
      await tester.pumpWidget(flow.app(repository, router));
      await tester.pumpAndSettle();
      await openSheet(tester);
      await selectFiles(tester);
      await upload(tester, 2);
      expect(find.text('2 reading details'), findsOneWidget);
      expect(
        find.text('Your receipts are saved. We’ll keep reading the details.'),
        findsOneWidget,
      );
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(UploadReceiptSheet)),
      );
      await tester.tap(find.text('Continue browsing'));
      await tester.pumpAndSettle();
      expect(find.byType(UploadReceiptSheet), findsNothing);
      expect(scope.read(receiptUploadActivityProvider), hasLength(2));
      repository.finishProcessing(repository.uploads.first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('receipt-upload-activity')));
      await tester.pumpAndSettle();
      expect(find.text('Receipt organized'), findsOneWidget);
      expect(find.text('Upload saved · Reading details'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'uncertain results show review and never invent missing dates or amounts',
    (tester) async {
      flow.viewport(tester);
      final repository = BatchRepository();
      addTearDown(repository.dispose);
      final router = flow.testRouter();
      addTearDown(router.dispose);
      picker.files = [pdf('First.pdf'), pdf('Second.pdf')];
      await tester.pumpWidget(flow.app(repository, router));
      await tester.pumpAndSettle();
      await openSheet(tester);
      await selectFiles(tester);
      await upload(tester, 2);
      final id = repository.uploads.first;
      repository.publishReceipt(
        Receipt(
          id: id,
          userId: 'u',
          status: ReceiptStatuses.needsReview,
          file: repository.records[id]!.file,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 to review · 1 reading details'), findsOneWidget);
      expect(
        find.text(
          'Amount needs review · Date needs review · Details need review',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Review receipt'));
      await tester.pumpAndSettle();
      expect(find.text(id), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'two receipts show readable names and a live result in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        flow.viewport(tester);
        final repository = BatchRepository();
        addTearDown(repository.dispose);
        final router = flow.testRouter();
        addTearDown(router.dispose);
        picker.files = [
          pdf('image_picker_FIRST.pdf'),
          pdf('image_picker_SECOND.pdf'),
        ];
        await tester.pumpWidget(flow.app(repository, router, dark: dark));
        await tester.pumpAndSettle();
        await openSheet(tester);
        await selectFiles(tester);
        await upload(tester, 2);
        repository.finishProcessing(repository.uploads.first);
        await tester.pumpAndSettle();
        expect(find.text('Your local café'), findsOneWidget);
        expect(find.text('Receipt 2'), findsOneWidget);
        expect(find.text('View receipt'), findsOneWidget);
        expect(find.text('View progress'), findsOneWidget);
        expect(find.textContaining('image_picker'), findsNothing);
        await flow.shot(tester, 'batch-results-${dark ? 'dark' : 'light'}');
        repository.finishProcessing(repository.uploads.last);
        await tester.pumpAndSettle();
        expect(find.text('2 ready'), findsOneWidget);
        expect(find.text('View receipt'), findsNWidgets(2));
        expect(find.text('Continue browsing'), findsOneWidget);
        expect(
          find.text('Your receipts are saved. We’ll keep reading the details.'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final dark in [false, true]) {
    testWidgets(
      'many files keep upload and retry visible on a small phone with large text (${dark ? 'dark' : 'light'})',
      (tester) async {
        flow.viewport(tester, const Size(320, 568));
        final repository = BatchRepository()..failures.add('File-0.pdf');
        addTearDown(repository.dispose);
        final router = sheetRouter(repository);
        addTearDown(router.dispose);
        picker.files = [for (var i = 0; i < 25; i++) pdf('File-$i.pdf')];
        await tester.pumpWidget(
          flow.app(repository, router, dark: dark, textScale: 1.6),
        );
        await tester.pumpAndSettle();
        await openSheet(tester);
        await selectFiles(tester);
        final button = find.text('Upload 25 files');
        expect(tester.getRect(button).bottom, lessThan(568));
        await flow.shot(tester, 'batch-small-${dark ? 'dark' : 'light'}');
        expect(tester.takeException(), isNull);
        await upload(tester, 25);
        expect(tester.getRect(find.text('Retry 1 file')).bottom, lessThan(568));
        expect(tester.takeException(), isNull);
        repository.finishProcessing(repository.uploads.first);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('View receipt'), 120);
        await tester.ensureVisible(find.text('View receipt'));
        await tester.pumpAndSettle();
        expect(find.text('View receipt').hitTestable(), findsOneWidget);
        expect(
          tester.getRect(find.text('View receipt')).bottom,
          lessThan(tester.getRect(find.text('Retry 1 file')).top),
        );
        await flow.shot(
          tester,
          'batch-results-small-${dark ? 'dark' : 'light'}',
        );
        expect(tester.getRect(find.text('Retry 1 file')).bottom, lessThan(568));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
