import '../../../core/utils/firestore_utils.dart';

class MonthlySummary {
  const MonthlySummary({
    required this.id,
    required this.userId,
    required this.totalSpend,
    required this.receiptCount,
    required this.byCategory,
    required this.byMerchant,
    required this.dailyTotals,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final double totalSpend;
  final int receiptCount;
  final Map<String, dynamic> byCategory;
  final Map<String, dynamic> byMerchant;
  final Map<int, double> dailyTotals;
  final DateTime? updatedAt;

  factory MonthlySummary.fromDoc(String id, Map<String, dynamic> data) {
    final rawDaily = (data['dailyTotals'] as Map<String, dynamic>? ?? const {});

    return MonthlySummary(
      id: id,
      userId: (data['userId'] as String?) ?? '',
      totalSpend: ((data['totalSpend'] as num?) ?? 0).toDouble(),
      receiptCount: (data['receiptCount'] as num?)?.toInt() ?? 0,
      byCategory: (data['byCategory'] as Map<String, dynamic>? ?? const {}),
      byMerchant: (data['byMerchant'] as Map<String, dynamic>? ?? const {}),
      dailyTotals: rawDaily.map((key, value) {
        return MapEntry(int.tryParse(key) ?? 0, ((value as num?) ?? 0).toDouble());
      }),
      updatedAt: asDateTime(data['updatedAt']),
    );
  }
}
