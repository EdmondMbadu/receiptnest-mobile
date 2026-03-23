import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/public_app_config.dart';
import '../../auth/data/auth_repository.dart';
import '../../receipts/models/monthly_summary.dart';
import '../../receipts/models/receipt.dart';
import '../models/chat_models.dart';

final aiRepositoryProvider = Provider<AiRepository>((ref) {
  return AiRepository(
    db: ref.watch(firestoreProvider),
    functions: ref.watch(functionsProvider),
  );
});

final aiActiveChatIdProvider = StateProvider<String?>((ref) => null);

final aiChatHistoryProvider = StreamProvider<List<AiChatHistoryItem>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream.value(const []);
  }
  return ref.watch(aiRepositoryProvider).watchHistory(uid);
});

final aiSuggestedQuestionsProvider = Provider<List<String>>((ref) {
  final appConfig = ref.watch(publicAppConfigProvider).valueOrNull;
  return appConfig?.aiSuggestedQuestions ??
      const PublicAppConfig().aiSuggestedQuestions;
});

class AiRepository {
  AiRepository({
    required FirebaseFirestore db,
    required FirebaseFunctions functions,
  }) : _db = db,
       _functions = functions;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final _uuid = const Uuid();

  Stream<List<AiChatHistoryItem>> watchHistory(
    String userId, {
    int limit = 20,
  }) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('aiChats')
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(AiChatHistoryItem.fromSnapshot).toList(),
        );
  }

  Future<List<AiChatMessage>> loadChat(String userId, String chatId) async {
    final doc = await _db
        .collection('users')
        .doc(userId)
        .collection('aiChats')
        .doc(chatId)
        .get();
    if (!doc.exists) return const [];

    final data = doc.data() ?? const <String, dynamic>{};
    final raw = (data['messages'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AiChatMessage.fromMap)
        .toList();

    return raw;
  }

  Future<String> ensureChat(String userId, {String? preferredId}) async {
    if (preferredId != null && preferredId.isNotEmpty) {
      final existing = await _db
          .collection('users')
          .doc(userId)
          .collection('aiChats')
          .doc(preferredId)
          .get();
      if (existing.exists) {
        return preferredId;
      }
    }

    final ref = await _db
        .collection('users')
        .doc(userId)
        .collection('aiChats')
        .add({
          'title': 'New chat',
          'messages': const [],
          'messageCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastMessageAt': FieldValue.serverTimestamp(),
        });

    return ref.id;
  }

  Future<void> deleteChat(String userId, String chatId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('aiChats')
        .doc(chatId)
        .delete();
  }

  Future<List<AiChatMessage>> sendMessage({
    required String userId,
    required String chatId,
    required String message,
    required List<AiChatMessage> currentMessages,
    required Map<String, dynamic> insightData,
  }) async {
    final userMessage = AiChatMessage(
      id: _uuid.v4(),
      role: 'user',
      content: message.trim(),
      timestamp: DateTime.now(),
    );

    final history = [...currentMessages, userMessage];

    final callable = _functions.httpsCallable('generateAiInsights');
    final response = await callable.call({
      'type': 'chat',
      'message': message.trim(),
      'history': history
          .take(10)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList(),
      'data': insightData,
    });

    final result = response.data;
    final answer = result is Map
        ? (result['response']?.toString() ?? 'No response received.')
        : 'No response received.';

    final assistantMessage = AiChatMessage(
      id: _uuid.v4(),
      role: 'assistant',
      content: answer,
      timestamp: DateTime.now(),
    );

    final next = [...history, assistantMessage];
    await persistChat(userId, chatId, next);
    return next;
  }

  Future<List<String>> generateInitialInsights({
    required Map<String, dynamic> insightData,
  }) async {
    try {
      final callable = _functions.httpsCallable('generateAiInsights');
      final response = await callable.call({
        'type': 'initial_insights',
        'data': insightData,
      });

      final result = response.data;
      if (result is Map && result['insights'] is List) {
        final insights = (result['insights'] as List)
            .map((e) => e.toString())
            .toList();
        if (insights.isNotEmpty) {
          return insights;
        }
      }
    } on FirebaseFunctionsException {
      return _generateFallbackInsights(insightData);
    } catch (_) {
      return _generateFallbackInsights(insightData);
    }
    return _generateFallbackInsights(insightData);
  }

  Future<void> persistChat(
    String userId,
    String chatId,
    List<AiChatMessage> messages,
  ) async {
    final title = _buildTitle(messages);
    await _db
        .collection('users')
        .doc(userId)
        .collection('aiChats')
        .doc(chatId)
        .set({
          'title': title,
          'messages': messages.map((m) => m.toMap()).toList(),
          'messageCount': messages.length,
          'updatedAt': FieldValue.serverTimestamp(),
          'lastMessageAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<String?> generateTelegramLinkToken() async {
    final callable = _functions.httpsCallable('generateTelegramLinkToken');
    final response = await callable.call(<String, dynamic>{});

    final result = response.data;
    if (result is Map) {
      return result['deepLink']?.toString();
    }
    return null;
  }

  Future<void> unlinkTelegram(String userId) async {
    await _db.collection('users').doc(userId).update({
      'telegramChatId': null,
      'telegramLinkedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Map<String, dynamic> buildInsightData({
    required List<Receipt> receipts,
    required List<MonthlySummary> monthlySummaries,
    required int month,
    required int year,
    required String monthLabel,
  }) {
    final selectedReceipts = receipts.where((receipt) {
      final date = receipt.effectiveDate;
      if (date == null) return false;
      return date.month == month && date.year == year;
    }).toList();

    final totalSpend = selectedReceipts.fold<double>(
      0,
      (runningTotal, r) => runningTotal + (r.effectiveTotalAmount ?? 0),
    );

    final byCategory = <String, double>{};
    for (final receipt in selectedReceipts) {
      final key = receipt.category?.name ?? 'Other';
      byCategory[key] =
          (byCategory[key] ?? 0) + (receipt.effectiveTotalAmount ?? 0);
    }

    final topCategories =
        byCategory.entries
            .map(
              (entry) => {
                'name': entry.key,
                'total': entry.value,
                'percentage': totalSpend > 0
                    ? ((entry.value / totalSpend) * 100).round()
                    : 0,
              },
            )
            .toList()
          ..sort(
            (a, b) => (b['total'] as double).compareTo(a['total'] as double),
          );

    final daysInMonth = DateTime(year, month + 1, 0).day;
    final dailyTotals = List<double>.filled(daysInMonth, 0);
    for (final receipt in selectedReceipts) {
      final date = receipt.effectiveDate;
      final amount = receipt.effectiveTotalAmount;
      if (date == null || amount == null) continue;
      dailyTotals[date.day - 1] += amount;
    }

    final daysWithSpending = dailyTotals.where((x) => x > 0).length;
    final dailyAverage = daysWithSpending == 0
        ? 0
        : totalSpend / daysWithSpending;

    int highestDay = 0;
    double highestAmount = 0;
    for (var i = 0; i < dailyTotals.length; i++) {
      if (dailyTotals[i] > highestAmount) {
        highestAmount = dailyTotals[i];
        highestDay = i + 1;
      }
    }

    final previous = DateTime(year, month - 1, 1);
    final prevSpend = receipts
        .where((receipt) {
          final date = receipt.effectiveDate;
          if (date == null) return false;
          return date.month == previous.month && date.year == previous.year;
        })
        .fold<double>(
          0,
          (runningTotal, r) => runningTotal + (r.effectiveTotalAmount ?? 0),
        );

    Map<String, dynamic>? monthChange;
    if (prevSpend > 0) {
      final delta = ((totalSpend - prevSpend) / prevSpend) * 100;
      monthChange = {'percent': delta.abs().round(), 'isIncrease': delta > 0};
    }

    final allByCategory = <String, double>{};
    final allByMerchant = <String, double>{};
    var allSpend = 0.0;
    for (final receipt in receipts) {
      final amount = receipt.effectiveTotalAmount ?? 0;
      allSpend += amount;
      final cat = receipt.category?.name ?? 'Other';
      final merchant =
          receipt.merchant?.canonicalName ??
          receipt.merchant?.rawName ??
          'Unknown';
      allByCategory[cat] = (allByCategory[cat] ?? 0) + amount;
      allByMerchant[merchant] = (allByMerchant[merchant] ?? 0) + amount;
    }

    final allTopCategories =
        allByCategory.entries
            .map(
              (entry) => {
                'name': entry.key,
                'total': entry.value,
                'percentage': allSpend > 0
                    ? ((entry.value / allSpend) * 100).round()
                    : 0,
              },
            )
            .toList()
          ..sort(
            (a, b) => (b['total'] as double).compareTo(a['total'] as double),
          );

    final allTopMerchants =
        allByMerchant.entries
            .map(
              (entry) => {
                'name': entry.key,
                'total': entry.value,
                'percentage': allSpend > 0
                    ? ((entry.value / allSpend) * 100).round()
                    : 0,
              },
            )
            .toList()
          ..sort(
            (a, b) => (b['total'] as double).compareTo(a['total'] as double),
          );

    final monthlySummariesData = monthlySummaries
        .map(
          (summary) => {
            'monthId': summary.id,
            'totalSpend': summary.totalSpend,
            'receiptCount': summary.receiptCount,
            'topCategories': const <Map<String, dynamic>>[],
            'topMerchants': const <Map<String, dynamic>>[],
          },
        )
        .toList();

    final receiptRows = selectedReceipts
        .map(
          (r) => {
            'merchant':
                r.merchant?.canonicalName ?? r.merchant?.rawName ?? 'Unknown',
            'amount': r.effectiveTotalAmount ?? 0,
            'date': r.date ?? '',
            'category': r.category?.name ?? 'Other',
          },
        )
        .toList();

    final recentReceipts = receipts.take(50).map((r) {
      return {
        'merchant':
            r.merchant?.canonicalName ?? r.merchant?.rawName ?? 'Unknown',
        'amount': r.effectiveTotalAmount ?? 0,
        'date': r.date ?? '',
        'category': r.category?.name ?? 'Other',
      };
    }).toList();

    return {
      'totalSpend': totalSpend,
      'receiptCount': selectedReceipts.length,
      'monthLabel': monthLabel,
      'topCategories': topCategories.take(5).toList(),
      'dailyAverage': dailyAverage,
      'highestSpendDay': highestDay == 0
          ? null
          : {'day': highestDay, 'amount': highestAmount},
      'monthOverMonthChange': monthChange,
      'receipts': receiptRows,
      'allTime': {
        'totalSpend': allSpend,
        'receiptCount': receipts.length,
        'topCategories': allTopCategories.take(10).toList(),
        'topMerchants': allTopMerchants.take(10).toList(),
        'firstMonth': monthlySummariesData.isEmpty
            ? null
            : monthlySummariesData.first['monthId'],
        'lastMonth': monthlySummariesData.isEmpty
            ? null
            : monthlySummariesData.last['monthId'],
        'monthsCount': monthlySummariesData.length,
      },
      'monthlySummaries': monthlySummariesData,
      'recentReceipts': recentReceipts,
    };
  }

  String _buildTitle(List<AiChatMessage> messages) {
    final firstUser = messages
        .where((m) => m.role == 'user' && m.content.trim().isNotEmpty)
        .firstOrNull;
    if (firstUser == null) return 'New chat';

    final normalized = firstUser.content.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.length <= 56
        ? normalized
        : '${normalized.substring(0, 56)}...';
  }

  List<String> _generateFallbackInsights(Map<String, dynamic> insightData) {
    final monthLabel = insightData['monthLabel']?.toString() ?? 'this month';
    final totalSpend = _asDouble(insightData['totalSpend']);
    final receiptCount = _asInt(insightData['receiptCount']);
    final dailyAverage = _asDouble(insightData['dailyAverage']);
    final topCategories = _asMapList(insightData['topCategories']);
    final allTime = _asMap(insightData['allTime']);
    final topMerchants = _asMapList(allTime['topMerchants']);
    final monthChange = _asMap(insightData['monthOverMonthChange']);
    final highestSpendDay = _asMap(insightData['highestSpendDay']);
    final monthsCount = _asInt(allTime['monthsCount']);
    final allTimeSpend = _asDouble(allTime['totalSpend']);
    final allTimeReceiptCount = _asInt(allTime['receiptCount']);

    if (receiptCount == 0) {
      if (allTimeReceiptCount == 0) {
        return [
          'No receipts were found for $monthLabel yet. Upload a few receipts first, then tap Insights again.',
          'Once receipts are available, this page will highlight your top categories, biggest spend days, and month-over-month changes.',
        ];
      }

      return [
        'No receipts were found for $monthLabel, but your account already has $allTimeReceiptCount receipts overall totaling ${_formatCurrency(allTimeSpend)}.',
        if (topMerchants.isNotEmpty)
          '${topMerchants.first['name']} is your top merchant overall at ${_formatCurrency(_asDouble(topMerchants.first['total']))}.',
        'Try switching to a month with activity or upload more receipts for $monthLabel to generate month-specific insights.',
      ];
    }

    final insights = <String>[
      'You spent ${_formatCurrency(totalSpend)} across $receiptCount receipts in $monthLabel${dailyAverage > 0 ? ', or about ${_formatCurrency(dailyAverage)} on each spending day.' : '.'}',
    ];

    if (topCategories.isNotEmpty) {
      final topCategory = topCategories.first;
      insights.add(
        '${topCategory['name']} was your biggest category at ${_formatCurrency(_asDouble(topCategory['total']))}, about ${_asInt(topCategory['percentage'])}% of your spending for $monthLabel.',
      );
    }

    if (monthChange.isNotEmpty) {
      final percent = _asInt(monthChange['percent']);
      if (percent > 0) {
        final direction = _asBool(monthChange['isIncrease']) ? 'up' : 'down';
        insights.add(
          'Your spending was $percent% $direction compared with last month, which is a useful signal for whether your current habits are accelerating or settling down.',
        );
      }
    } else if (highestSpendDay.isNotEmpty) {
      insights.add(
        'Your highest spending day was day ${_asInt(highestSpendDay['day'])}, when you spent ${_formatCurrency(_asDouble(highestSpendDay['amount']))}.',
      );
    }

    if (topMerchants.isNotEmpty) {
      final merchant = topMerchants.first;
      insights.add(
        '${merchant['name']} is your top merchant overall at ${_formatCurrency(_asDouble(merchant['total']))}, so repeated spend there is worth reviewing first.',
      );
    } else if (monthsCount > 1) {
      insights.add(
        'You now have $monthsCount months of receipt history and ${_formatCurrency(allTimeSpend)} in tracked spending overall, which is enough data to compare patterns over time.',
      );
    }

    return insights.take(4).toList();
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }
    return value.map(_asMap).toList();
  }

  double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _asInt(dynamic value) {
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _asBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    return value?.toString().toLowerCase() == 'true';
  }

  String _formatCurrency(double amount) {
    return NumberFormat.currency(symbol: '\$', decimalDigits: 2).format(amount);
  }
}
