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
  String? _selectedPeriod;

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

    final allTimeTotal = receipts.fold<double>(
      0,
      (sum, r) => sum + (r.effectiveTotalAmount ?? 0),
    );

    final periods = _buildPeriods(receipts);

    if (_selectedPeriod == null && periods.isNotEmpty) {
      _selectedPeriod = periods.first.key;
    }
    if (_selectedPeriod != null &&
        _range != _TimeRange.allTime &&
        !periods.any((p) => p.key == _selectedPeriod)) {
      _selectedPeriod = periods.isNotEmpty ? periods.first.key : null;
    }

    final filtered = _range == _TimeRange.allTime
        ? receipts
        : receipts.where((r) {
            final date = r.effectiveDate;
            if (date == null) return false;
            return _periodKey(date) == _selectedPeriod;
          }).toList();

    final filteredTotal = filtered.fold<double>(
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
      body: Column(
        children: [
          // ── Fixed header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              children: [
                // Summary card
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
                            if (_range != _TimeRange.allTime) ...[
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

                // Time range selector
                _segmentedControl(cs, isDark),

                // Period dropdown
                if (_range != _TimeRange.allTime && periods.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E1E30)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedPeriod,
                        isExpanded: true,
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                        dropdownColor: isDark
                            ? const Color(0xFF1E1E30)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                        items: periods
                            .map((p) => DropdownMenuItem(
                                  value: p.key,
                                  child: Text(p.label),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _selectedPeriod = v);
                          }
                        },
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
              ],
            ),
          ),

          // ── Scrollable receipt list ──
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No receipts for this period',
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) =>
                        _receiptTile(filtered[i], cs),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──

  Widget _segmentedControl(ColorScheme cs, bool isDark) {
    return Container(
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
    );
  }

  Widget _tabButton(
      String label, _TimeRange range, ColorScheme cs, bool isDark) {
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

  String _periodKey(DateTime date) {
    switch (_range) {
      case _TimeRange.month:
        return '${date.year}-${date.month.toString().padLeft(2, '0')}';
      case _TimeRange.year:
        return '${date.year}';
      case _TimeRange.allTime:
        return 'all';
    }
  }

  List<_Period> _buildPeriods(List<Receipt> receipts) {
    final seen = <String, _Period>{};
    for (final r in receipts) {
      final d = r.effectiveDate;
      if (d == null) continue;
      final key = _periodKey(d);
      if (!seen.containsKey(key)) {
        String label;
        switch (_range) {
          case _TimeRange.month:
            label = DateFormat('MMM yyyy').format(d);
            break;
          case _TimeRange.year:
            label = '${d.year}';
            break;
          case _TimeRange.allTime:
            label = 'All Time';
            break;
        }
        seen[key] = _Period(key: key, label: label);
      }
    }
    final list = seen.values.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return list;
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

class _Period {
  const _Period({required this.key, required this.label});
  final String key;
  final String label;
}
