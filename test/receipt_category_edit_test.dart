import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recieptnest_ai/src/features/receipts/models/category.dart';
import 'package:recieptnest_ai/src/features/receipts/models/receipt.dart';
import 'package:recieptnest_ai/src/features/receipts/presentation/receipt_detail_screen.dart';

import 'onboarding_flow_test.dart' as onboarding;
import 'support/onboarding_fakes.dart';

class CategoryEditRepository extends MemoryReceiptRepository {
  CategoryEditRepository(Receipt receipt) : super([receipt]);
  Map<String, dynamic>? saved;
  @override
  Future<void> updateReceipt(
    String userId,
    String receiptId,
    Map<String, dynamic> updates,
  ) async {
    saved = updates;
  }
}

Receipt categorized(String? id, [String name = '']) => Receipt(
  id: 'r1',
  userId: 'u',
  status: ReceiptStatuses.finalStatus,
  file: const ReceiptFile(
    storagePath: 'users/u/receipt.docx',
    originalName: 'Receipt.docx',
    mimeType:
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    sizeBytes: 1024,
  ),
  merchant: exampleReceipt().merchant,
  totalAmount: 12.5,
  date: '2026-11-27',
  category: id == null
      ? null
      : ReceiptCategory(id: id, name: name, confidence: 1, assignedBy: 'ai'),
);

Future<void> openDetails(
  WidgetTester tester,
  CategoryEditRepository repository, {
  bool dark = false,
  double scale = 1,
}) async {
  onboarding.phone(tester);
  await tester.pumpWidget(
    onboarding.fixture(
      child: const ReceiptDetailScreen(receiptId: 'r1'),
      repository: repository,
      dark: dark,
      textScale: scale,
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save changes'));
  await tester.tap(find.text('Save changes'));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'the full known category menu has unique IDs, including money transfers',
    () {
      expect(
        defaultCategories.map((category) => category.id).toSet().length,
        defaultCategories.length,
      );
      expect(categoryById('money_transfers').name, 'Money transfers');
      for (final category in defaultCategories) {
        final options = categoryOptionsIncluding(
          category.id,
          savedName: category.name,
        );
        expect(
          options.where((option) => option.id == category.id),
          hasLength(1),
        );
      }
      expect(
        categoryOptionsIncluding('future_category').last.id,
        'future_category',
      );
      expect(
        categoryOptionsIncluding('future_category').last.name,
        'Future category',
      );
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'money transfers opens and saves without changing category (${dark ? 'dark' : 'light'})',
      (tester) async {
        final repository = CategoryEditRepository(
          categorized('money_transfers', 'Money transfers'),
        );
        addTearDown(repository.dispose);
        await openDetails(tester, repository, dark: dark);
        expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
        expect(tester.takeException(), isNull);
        await save(tester);
        expect(repository.saved!['category']['id'], 'money_transfers');
        expect(repository.saved!['category']['name'], 'Money transfers');
        expect(find.text('Receipt updated successfully.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'a future category stays selected and survives editing another field',
    (tester) async {
      final repository = CategoryEditRepository(
        categorized('office_supplies_v2', 'Office supplies'),
      );
      addTearDown(repository.dispose);
      await openDetails(tester, repository);
      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      expect(dropdown.initialValue, 'office_supplies_v2');
      expect(find.textContaining('Office supplies'), findsWidgets);
      final merchant = find.widgetWithText(TextField, 'Merchant');
      await tester.ensureVisible(merchant);
      await tester.enterText(merchant, 'Updated merchant');
      await save(tester);
      expect(
        repository.saved!['merchant']['canonicalName'],
        'Updated merchant',
      );
      expect(repository.saved!['category']['id'], 'office_supplies_v2');
      expect(repository.saved!['category']['name'], 'Office supplies');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a future category remains available after explicitly choosing a known category',
    (tester) async {
      final repository = CategoryEditRepository(
        categorized('future_category', 'Future category'),
      );
      addTearDown(repository.dispose);
      await openDetails(tester, repository);
      final field = find.byType(DropdownButtonFormField<String>);
      // Choose through the field callback, then verify the rebuilt menu keeps
      // the original unknown option available for changing the selection back.
      tester.widget<DropdownButtonFormField<String>>(field).onChanged!(
        'groceries',
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Future category', skipOffstage: false),
        findsWidgets,
      );
      await save(tester);
      expect(repository.saved!['category']['id'], 'groceries');
      expect(repository.saved!['category']['name'], 'Groceries');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a receipt without a category keeps the normal Other selection', (
    tester,
  ) async {
    final repository = CategoryEditRepository(categorized(null));
    addTearDown(repository.dispose);
    await openDetails(tester, repository);
    await save(tester);
    expect(repository.saved!['category']['id'], 'other');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
