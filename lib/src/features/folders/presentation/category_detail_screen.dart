import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/formatters.dart';
import '../../receipts/data/receipt_repository.dart';
import '../../receipts/models/category.dart';
import '../../receipts/models/receipt.dart';

enum _TimeRange { month, year, allTime }

class CategoryDetailScreen extends ConsumerStatefulWidget {
  const CategoryDetailScreen({super.key, required this.categoryId});

  final String categoryId;

  @override
  ConsumerState<CategoryDetailScreen> createState() =>
      _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends ConsumerState<CategoryDetailScreen> {
  _TimeRange _range = _TimeRange.month;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allReceipts =
        ref.watch(receiptsStreamProvider).valueOrNull ?? const <Receipt>[];

    final category = categoryById(widget.categoryId);
    final receipts = allReceipts.where((r) {
      final id = r.category?.id ?? 'other';
      return id == widget.categoryId;
    }).toList()
      ..sort((a, b) {
        final da = a.effectiveDate;
        final db = b.effectiveDate;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

    final total = receipts.fold<double>(
      0,
      (sum, r) => sum + (r.effectiveTotalAmount ?? 0),
    );

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0E0E18) : const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Text('${category.icon} ${category.name}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        children: [
          // ── Summary card ──
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
                        '${receipts.length} receipts',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatCurrency(total),
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: cs.onSurface,
                        ),
                      ),
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

          // ── Time range selector ──
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF151520) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _tabButton('Month', _TimeRange.month, cs, isDark),
                _tabButton('Year', _TimeRange.year, cs, isDark),
                _tabButton('All Time', _TimeRange.allTime, cs, isDark),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Content ──
          if (receipts.isEmpty)
            _emptyState(cs, isDark)
          else
            ..._buildContent(receipts, cs, isDark),
        ],
      ),
    );
  }

  Widget _tabButton(
      String label, _TimeRange range, ColorScheme cs, bool isDark) {
    final selected = _range == range;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _range = range),
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

  List<Widget> _buildContent(
      List<Receipt> receipts, ColorScheme cs, bool isDark) {
    switch (_range) {
      case _TimeRange.month:
        return _buildGrouped(
          receipts,
          cs,
          isDark,
          keyFn: (d) => '${d.year}-${d.month.toString().padLeft(2, '0')}',
          labelFn: (d) => DateFormat('MMMM yyyy').format(d),
          sortDescending: true,
        );
      case _TimeRange.year:
        return _buildGrouped(
          receipts,
          cs,
          isDark,
          keyFn: (d) => '${d.year}',
          labelFn: (d) => '${d.year}',
          sortDescending: true,
        );
      case _TimeRange.allTime:
        return receipts.map((r) => _receiptTile(r, cs)).toList();
    }
  }

  List<Widget> _buildGrouped(
    List<Receipt> receipts,
    ColorScheme cs,
    bool isDark, {
    required String Function(DateTime) keyFn,
    required String Function(DateTime) labelFn,
    required bool sortDescending,
  }) {
    final groups = <String, _Group>{};

    for (final receipt in receipts) {
      final date = receipt.effectiveDate;
      if (date == null) continue;
      final key = keyFn(date);
      groups.putIfAbsent(key, () => _Group(key: key, label: labelFn(date)));
      groups[key]!.receipts.add(receipt);
      groups[key]!.total += receipt.effectiveTotalAmount ?? 0;
    }

    // Add receipts without dates to a special group
    final noDate =
        receipts.where((r) => r.effectiveDate == null).toList();
    if (noDate.isNotEmpty) {
      final g = _Group(key: 'no-date', label: 'No Date');
      g.receipts.addAll(noDate);
      g.total = noDate.fold<double>(
          0, (s, r) => s + (r.effectiveTotalAmount ?? 0));
      groups['no-date'] = g;
    }

    final sorted = groups.values.toList()
      ..sort((a, b) => sortDescending
          ? b.key.compareTo(a.key)
          : a.key.compareTo(b.key));

    final widgets = <Widget>[];
    for (final group in sorted) {
      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF151520) : Colors.white,
            borderRadius: BorderRadius.circular(16),
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
                      group.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${group.receipts.length} receipt${group.receipts.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                formatCurrency(group.total),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      );

      for (final receipt in group.receipts) {
        widgets.add(_receiptTile(receipt, cs));
      }

      widgets.add(const SizedBox(height: 12));
    }
    return widgets;
  }

  Widget _receiptTile(Receipt receipt, ColorScheme cs) {
    final merchant = receipt.merchant?.canonicalName ??
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
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
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
                        formatDate(receipt.effectiveDate,
                            pattern: 'MMM d, y'),
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

  Widget _emptyState(ColorScheme cs, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151520) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.grey.shade200,
        ),
      ),
      child: Center(
        child: Text(
          'No receipts in this category',
          style: TextStyle(
            fontSize: 14,
            color: cs.onSurface.withValues(alpha: 0.4),
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

class _Group {
  _Group({required this.key, required this.label});

  final String key;
  final String label;
  final List<Receipt> receipts = [];
  double total = 0;
}
