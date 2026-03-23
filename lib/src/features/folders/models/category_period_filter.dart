import 'package:intl/intl.dart';

import '../../receipts/models/category.dart';
import '../../receipts/models/receipt.dart';

enum CategoryTimeRange { month, year, allTime }

class CategoryPeriodOption {
  const CategoryPeriodOption({required this.key, required this.label});

  final String key;
  final String label;
}

String categoryTimeRangeQueryValue(CategoryTimeRange range) {
  switch (range) {
    case CategoryTimeRange.month:
      return 'month';
    case CategoryTimeRange.year:
      return 'year';
    case CategoryTimeRange.allTime:
      return 'all-time';
  }
}

CategoryTimeRange categoryTimeRangeFromQuery(String? value) {
  switch (value) {
    case 'year':
      return CategoryTimeRange.year;
    case 'all-time':
      return CategoryTimeRange.allTime;
    case 'month':
    default:
      return CategoryTimeRange.month;
  }
}

String categoryPeriodKey(DateTime date, CategoryTimeRange range) {
  switch (range) {
    case CategoryTimeRange.month:
      return '${date.year}-${date.month.toString().padLeft(2, '0')}';
    case CategoryTimeRange.year:
      return '${date.year}';
    case CategoryTimeRange.allTime:
      return 'all-time';
  }
}

List<CategoryPeriodOption> buildCategoryPeriods(
  List<Receipt> receipts,
  CategoryTimeRange range,
) {
  if (range == CategoryTimeRange.allTime) {
    return const [];
  }

  final seen = <String, CategoryPeriodOption>{};
  for (final receipt in receipts) {
    final date = receipt.effectiveDate;
    if (date == null) continue;

    final key = categoryPeriodKey(date, range);
    seen.putIfAbsent(
      key,
      () => CategoryPeriodOption(
        key: key,
        label: categoryPeriodLabel(range, key) ?? key,
      ),
    );
  }

  final periods = seen.values.toList()..sort((a, b) => b.key.compareTo(a.key));
  return periods;
}

String? normalizeSelectedCategoryPeriod({
  required CategoryTimeRange range,
  required List<CategoryPeriodOption> periods,
  required String? selectedPeriodKey,
}) {
  if (range == CategoryTimeRange.allTime) {
    return null;
  }
  if (periods.isEmpty) {
    return null;
  }
  if (selectedPeriodKey != null &&
      periods.any((period) => period.key == selectedPeriodKey)) {
    return selectedPeriodKey;
  }
  return periods.first.key;
}

List<Receipt> filterReceiptsByCategoryPeriod(
  List<Receipt> receipts, {
  required CategoryTimeRange range,
  required String? selectedPeriodKey,
}) {
  if (range == CategoryTimeRange.allTime) {
    return receipts;
  }

  if (selectedPeriodKey == null) {
    return const [];
  }

  return receipts.where((receipt) {
    final date = receipt.effectiveDate;
    if (date == null) return false;
    return categoryPeriodKey(date, range) == selectedPeriodKey;
  }).toList();
}

String? categoryPeriodLabel(CategoryTimeRange range, String? key) {
  if (key == null || key.isEmpty) {
    return null;
  }

  switch (range) {
    case CategoryTimeRange.month:
      final parts = key.split('-');
      if (parts.length != 2) return key;
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      if (year == null || month == null) return key;
      return DateFormat('MMM yyyy').format(DateTime(year, month));
    case CategoryTimeRange.year:
      return key;
    case CategoryTimeRange.allTime:
      return 'All Time';
  }
}

String categoryExportBaseName(
  ExpenseCategory category, {
  required CategoryTimeRange range,
  required String? selectedPeriodKey,
}) {
  final categorySlug = _slugify(category.name);
  final periodSlug = categoryExportPeriodSlug(
    range: range,
    selectedPeriodKey: selectedPeriodKey,
  );
  return '$categorySlug-$periodSlug';
}

String categoryExportPeriodSlug({
  required CategoryTimeRange range,
  required String? selectedPeriodKey,
}) {
  switch (range) {
    case CategoryTimeRange.month:
      final label = categoryPeriodLabel(range, selectedPeriodKey);
      if (label == null) return 'month';
      return _slugify(label);
    case CategoryTimeRange.year:
      return selectedPeriodKey ?? 'year';
    case CategoryTimeRange.allTime:
      return 'all-time';
  }
}

String _slugify(String value) {
  final normalized = value
      .toLowerCase()
      .replaceAll('&', ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return normalized.isEmpty ? 'export' : normalized;
}
