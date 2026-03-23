import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../receipts/data/receipt_repository.dart';
import '../../receipts/models/category.dart';
import '../../receipts/models/receipt.dart';
import '../data/category_export_service.dart';
import '../models/category_period_filter.dart';
import 'widgets/tax_ready_helper_card.dart';

enum _CategoryExportFormat { pdf, csv }

class CategoryDetailScreen extends ConsumerStatefulWidget {
  const CategoryDetailScreen({
    super.key,
    required this.categoryId,
    this.initialRange = CategoryTimeRange.month,
    this.initialPeriodKey,
  });

  final String categoryId;
  final CategoryTimeRange initialRange;
  final String? initialPeriodKey;

  @override
  ConsumerState<CategoryDetailScreen> createState() =>
      _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends ConsumerState<CategoryDetailScreen> {
  late CategoryTimeRange _range;
  String? _selectedPeriod;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange;
    _selectedPeriod = widget.initialPeriodKey;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allReceipts =
        ref.watch(receiptsStreamProvider).valueOrNull ?? const <Receipt>[];

    final category = categoryById(widget.categoryId);
    final receipts =
        allReceipts.where((receipt) {
          final categoryId = receipt.category?.id ?? 'other';
          return categoryId == widget.categoryId;
        }).toList()..sort((a, b) {
          final dateA = a.effectiveDate;
          final dateB = b.effectiveDate;
          if (dateA == null && dateB == null) return 0;
          if (dateA == null) return 1;
          if (dateB == null) return -1;
          return dateB.compareTo(dateA);
        });

    final periods = buildCategoryPeriods(receipts, _range);
    _selectedPeriod = normalizeSelectedCategoryPeriod(
      range: _range,
      periods: periods,
      selectedPeriodKey: _selectedPeriod,
    );

    final filtered = filterReceiptsByCategoryPeriod(
      receipts,
      range: _range,
      selectedPeriodKey: _selectedPeriod,
    );

    final filteredTotal = filtered.fold<double>(
      0,
      (sum, receipt) => sum + (receipt.effectiveTotalAmount ?? 0),
    );
    final allTimeTotal = receipts.fold<double>(
      0,
      (sum, receipt) => sum + (receipt.effectiveTotalAmount ?? 0),
    );

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0E0E18)
          : const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Text('${category.icon} ${category.name}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF151520) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${filtered.length} receipt${filtered.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: cs.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatCurrency(filteredTotal),
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: cs.onSurface,
                              ),
                            ),
                            if (_range != CategoryTimeRange.allTime) ...[
                              const SizedBox(height: 2),
                              Text(
                                'All time: ${formatCurrency(allTimeTotal)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withValues(alpha: 0.35),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            category.icon,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _segmentedControl(cs, isDark),
                const SizedBox(height: 10),
                _filterActionRow(
                  cs: cs,
                  isDark: isDark,
                  periods: periods,
                  exportEnabled: filtered.isNotEmpty,
                  onExport: () => _showExportOptions(
                    category: category,
                    receipts: filtered,
                  ),
                ),
                const SizedBox(height: 10),
                const TaxReadyHelperCard(
                  title: 'Tax-Ready',
                  body:
                      'Select the filing period you need, then export this category as CSV or PDF for IRS Free File or your accountant.',
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      _range == CategoryTimeRange.allTime
                          ? 'No receipts in this category yet'
                          : 'No receipts for this period',
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) =>
                        _receiptTile(filtered[index], cs),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _segmentedControl(ColorScheme cs, bool isDark) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151520) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _tabButton('Month', CategoryTimeRange.month, cs, isDark),
          _tabButton('Year', CategoryTimeRange.year, cs, isDark),
          _tabButton('All Time', CategoryTimeRange.allTime, cs, isDark),
        ],
      ),
    );
  }

  Widget _filterActionRow({
    required ColorScheme cs,
    required bool isDark,
    required List<CategoryPeriodOption> periods,
    required bool exportEnabled,
    required VoidCallback onExport,
  }) {
    final button = SizedBox(
      height: 48,
      child: FilledButton.tonalIcon(
        onPressed: _exporting || !exportEnabled ? null : onExport,
        icon: _exporting
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
              )
            : const Icon(Icons.ios_share_rounded, size: 18),
        label: Text(_exporting ? 'Preparing...' : 'Export'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor: cs.primary.withValues(alpha: isDark ? 0.2 : 0.12),
          foregroundColor: cs.primary,
        ),
      ),
    );

    if (_range == CategoryTimeRange.allTime || periods.isEmpty) {
      return Align(alignment: Alignment.centerRight, child: button);
    }

    return Row(
      children: [
        Expanded(
          child: _PeriodNavigator(
            periods: periods,
            selectedKey: _selectedPeriod,
            onChanged: (key) => setState(() => _selectedPeriod = key),
          ),
        ),
        const SizedBox(width: 10),
        button,
      ],
    );
  }

  Widget _tabButton(
    String label,
    CategoryTimeRange range,
    ColorScheme cs,
    bool isDark,
  ) {
    final selected = _range == range;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _range = range;
          _selectedPeriod = null;
        }),
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? const Color(0xFF252538) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected && !isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? cs.onSurface
                    : cs.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showExportOptions({
    required ExpenseCategory category,
    required List<Receipt> receipts,
  }) async {
    if (receipts.isEmpty || _exporting) {
      if (receipts.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No receipts available to export for this period.'),
          ),
        );
      }
      return;
    }

    final format = await showModalBottomSheet<_CategoryExportFormat>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A2A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _exportOptionTile(
                    context: context,
                    label: 'PDF',
                    icon: Icons.picture_as_pdf_outlined,
                    onTap: () =>
                        Navigator.of(context).pop(_CategoryExportFormat.pdf),
                  ),
                  const SizedBox(height: 8),
                  _exportOptionTile(
                    context: context,
                    label: 'CSV',
                    icon: Icons.table_chart_outlined,
                    onTap: () =>
                        Navigator.of(context).pop(_CategoryExportFormat.csv),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (format == null) return;
    await _exportCategory(
      category: category,
      receipts: receipts,
      format: format,
    );
  }

  Widget _exportOptionTile({
    required BuildContext context,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: cs.onSurface.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportCategory({
    required ExpenseCategory category,
    required List<Receipt> receipts,
    required _CategoryExportFormat format,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final exportService = ref.read(categoryExportServiceProvider);
      switch (format) {
        case _CategoryExportFormat.csv:
          await exportService.exportCsv(
            category: category,
            range: _range,
            selectedPeriodKey: _selectedPeriod,
            receipts: receipts,
          );
          break;
        case _CategoryExportFormat.pdf:
          await exportService.exportPdf(
            category: category,
            range: _range,
            selectedPeriodKey: _selectedPeriod,
            receipts: receipts,
          );
          break;
      }
    } on CategoryExportException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('We could not export this category right now.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Widget _receiptTile(Receipt receipt, ColorScheme cs) {
    final merchant =
        receipt.merchant?.canonicalName ??
        receipt.merchant?.rawName ??
        receipt.file.originalName;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/app/receipt/${receipt.id}'),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      _initials(merchant),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        merchant,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          letterSpacing: -0.2,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        formatDate(receipt.effectiveDate, pattern: 'MMM d, y'),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w400,
                          color: cs.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  formatCurrency(receipt.effectiveTotalAmount),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.length >= 2
        ? name.substring(0, 2).toUpperCase()
        : name.toUpperCase();
  }
}

class _PeriodNavigator extends StatelessWidget {
  const _PeriodNavigator({
    required this.periods,
    required this.selectedKey,
    required this.onChanged,
  });

  final List<CategoryPeriodOption> periods;
  final String? selectedKey;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final index = periods.indexWhere((period) => period.key == selectedKey);
    final hasPrev = index < periods.length - 1;
    final hasNext = index > 0;
    final label = index >= 0
        ? periods[index].label
        : (periods.isNotEmpty ? periods.first.label : '');

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E30) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          _arrowButton(
            icon: Icons.chevron_left_rounded,
            enabled: hasPrev,
            onTap: () => onChanged(periods[index + 1].key),
            cs: cs,
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _showPicker(context, cs, isDark),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.15),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        label,
                        key: ValueKey(label),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.unfold_more_rounded,
                      size: 18,
                      color: cs.onSurface.withValues(alpha: 0.35),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _arrowButton(
            icon: Icons.chevron_right_rounded,
            enabled: hasNext,
            onTap: () => onChanged(periods[index - 1].key),
            cs: cs,
          ),
        ],
      ),
    );
  }

  Widget _arrowButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    required ColorScheme cs,
  }) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: Icon(
              icon,
              size: 24,
              color: enabled
                  ? cs.onSurface.withValues(alpha: 0.7)
                  : cs.onSurface.withValues(alpha: 0.12),
            ),
          ),
        ),
      ),
    );
  }

  void _showPicker(BuildContext context, ColorScheme cs, bool isDark) {
    final selectedIndex = periods.indexWhere(
      (period) => period.key == selectedKey,
    );

    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A2A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select period',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  shrinkWrap: true,
                  itemCount: periods.length,
                  itemBuilder: (_, index) {
                    final period = periods[index];
                    final selected = index == selectedIndex;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Material(
                        color: selected
                            ? cs.primary.withValues(alpha: 0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () =>
                              Navigator.of(sheetContext).pop(period.key),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    period.label,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: selected
                                          ? cs.primary
                                          : cs.onSurface,
                                    ),
                                  ),
                                ),
                                if (selected)
                                  Icon(
                                    Icons.check_rounded,
                                    size: 20,
                                    color: cs.primary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ).then((value) {
      if (value != null) {
        onChanged(value);
      }
    });
  }
}
