import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../receipts/data/receipt_repository.dart';
import '../../receipts/models/category.dart';
import '../../receipts/models/receipt.dart';

class CategoryDetailScreen extends ConsumerWidget {
  const CategoryDetailScreen({super.key, required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allReceipts =
        ref.watch(receiptsStreamProvider).valueOrNull ?? const <Receipt>[];

    final category = categoryById(categoryId);
    final receipts = allReceipts.where((r) {
      final id = r.category?.id ?? 'other';
      return id == categoryId;
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
      backgroundColor: isDark ? const Color(0xFF0E0E18) : const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Text('${category.icon} ${category.name}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
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
          const SizedBox(height: 16),
          if (receipts.isEmpty)
            Container(
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
            )
          else
            ...receipts.map((receipt) {
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 11),
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
                                    color:
                                        cs.onSurface.withValues(alpha: 0.4),
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
            }),
        ],
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
