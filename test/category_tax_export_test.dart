import 'package:flutter_test/flutter_test.dart';
import 'package:recieptnest_ai/src/features/folders/data/category_export_service.dart';
import 'package:recieptnest_ai/src/features/folders/models/category_period_filter.dart';
import 'package:recieptnest_ai/src/features/receipts/models/category.dart';
import 'package:recieptnest_ai/src/features/receipts/models/receipt.dart';

void main() {
  group('category period filtering', () {
    test('filters receipts by the selected month', () {
      final receipts = <Receipt>[
        _receipt(
          id: 'jan',
          categoryId: 'gas_fuel',
          date: DateTime(2025, 1, 12),
          amount: 24.50,
        ),
        _receipt(
          id: 'feb',
          categoryId: 'gas_fuel',
          date: DateTime(2025, 2, 2),
          amount: 40.00,
        ),
      ];

      final periods = buildCategoryPeriods(receipts, CategoryTimeRange.month);
      expect(periods.map((period) => period.key), <String>[
        '2025-02',
        '2025-01',
      ]);

      final filtered = filterReceiptsByCategoryPeriod(
        receipts,
        range: CategoryTimeRange.month,
        selectedPeriodKey: '2025-01',
      );

      expect(filtered.map((receipt) => receipt.id), <String>['jan']);
    });

    test('filters receipts by the selected year', () {
      final receipts = <Receipt>[
        _receipt(
          id: 'recent',
          categoryId: 'restaurants',
          date: DateTime(2025, 6, 8),
          amount: 18.75,
        ),
        _receipt(
          id: 'older',
          categoryId: 'restaurants',
          date: DateTime(2024, 11, 3),
          amount: 42.10,
        ),
      ];

      final filtered = filterReceiptsByCategoryPeriod(
        receipts,
        range: CategoryTimeRange.year,
        selectedPeriodKey: '2025',
      );

      expect(filtered.map((receipt) => receipt.id), <String>['recent']);
    });
  });

  group('category tax export filenames', () {
    test('builds filenames from category and filing period', () {
      final gas = categoryById('gas_fuel');
      final restaurants = categoryById('restaurants');

      expect(
        CategoryExportService.buildFileName(
          category: gas,
          range: CategoryTimeRange.year,
          selectedPeriodKey: '2025',
          extension: 'csv',
        ),
        'gas-fuel-2025.csv',
      );

      expect(
        CategoryExportService.buildFileName(
          category: gas,
          range: CategoryTimeRange.month,
          selectedPeriodKey: '2025-01',
          extension: 'pdf',
        ),
        'gas-fuel-jan-2025.pdf',
      );

      expect(
        CategoryExportService.buildFileName(
          category: restaurants,
          range: CategoryTimeRange.allTime,
          selectedPeriodKey: null,
          extension: 'csv',
        ),
        'restaurants-dining-all-time.csv',
      );
    });
  });

  test('csv export includes category, filtered rows, and a total', () {
    final category = categoryById('gas_fuel');
    final csv = CategoryExportService.buildCsv(
      category: category,
      receipts: <Receipt>[
        _receipt(
          id: 'one',
          categoryId: 'gas_fuel',
          merchantName: 'Shell',
          date: DateTime(2025, 1, 12),
          amount: 24.50,
        ),
        _receipt(
          id: 'two',
          categoryId: 'gas_fuel',
          merchantName: 'Chevron',
          date: DateTime(2025, 1, 29),
          amount: 40.00,
        ),
      ],
    );

    expect(
      csv,
      '"Category","Merchant","Date","Amount"\n'
      '"Gas & Fuel","Shell","2025-01-12","24.50"\n'
      '"Gas & Fuel","Chevron","2025-01-29","40.00"\n'
      '"Total","","","64.50"',
    );
  });
}

Receipt _receipt({
  required String id,
  required String categoryId,
  String merchantName = 'Merchant',
  required DateTime date,
  required double amount,
}) {
  return Receipt(
    id: id,
    userId: 'user-1',
    status: ReceiptStatuses.finalStatus,
    file: ReceiptFile(
      storagePath: 'receipts/$id.jpg',
      originalName: 'receipt.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: 1,
    ),
    merchant: ReceiptMerchant(
      canonicalId: null,
      canonicalName: merchantName,
      rawName: merchantName,
      matchConfidence: 1,
      matchedBy: 'manual',
    ),
    category: ReceiptCategory(
      id: categoryId,
      name: categoryById(categoryId).name,
      confidence: 1,
      assignedBy: 'manual',
    ),
    totalAmount: amount,
    date: date.toIso8601String(),
    createdAt: date,
  );
}
