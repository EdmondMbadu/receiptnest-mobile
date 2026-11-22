import 'dart:async';

import 'package:recieptnest_ai/src/features/ai/data/ai_repository.dart';
import 'package:recieptnest_ai/src/features/ai/models/chat_models.dart';
import 'package:recieptnest_ai/src/features/receipts/models/monthly_summary.dart';
import 'package:recieptnest_ai/src/features/receipts/models/receipt.dart';

import 'onboarding_fakes.dart';

class InsightsTestReceipts extends MemoryReceiptRepository {
  InsightsTestReceipts() : super([exampleReceipt()]);
  @override
  Future<List<MonthlySummary>> getMonthlySummaries(
    String userId, {
    int? limit,
  }) async => const [];
}

class InsightsTestAi implements AiRepository {
  List<AiChatMessage> historyMessages = const [];
  List<String> insights = List.generate(
    12,
    (index) =>
        'Insight ${index + 1}: Your receipts show a change in food, transport, and household spending. Compare the category totals with the previous month to understand what changed.',
  );
  final sent = <String>[];
  final loaded = <String>[];
  Completer<List<AiChatMessage>>? pendingResponse;
  bool failSend = false;
  @override
  Future<List<AiChatMessage>> loadChat(String uid, String id) async {
    loaded.add(id);
    return historyMessages;
  }

  @override
  Future<String> ensureChat(String uid, {String? preferredId}) async =>
      preferredId ?? 'new-chat';
  @override
  Map<String, dynamic> buildInsightData({
    required List<Receipt> receipts,
    required List<MonthlySummary> monthlySummaries,
    required int month,
    required int year,
    required String monthLabel,
  }) => {'month': month, 'year': year};
  @override
  Future<List<String>> generateInitialInsights({
    required Map<String, dynamic> insightData,
  }) async => insights;
  @override
  Future<List<AiChatMessage>> sendMessage({
    required String userId,
    required String chatId,
    required String message,
    required List<AiChatMessage> currentMessages,
    required Map<String, dynamic> insightData,
  }) async {
    sent.add(message);
    if (failSend) throw StateError('Simulated connection failure');
    if (pendingResponse != null) return pendingResponse!.future;
    return [
      ...currentMessages,
      AiChatMessage(
        id: 'user-${sent.length}',
        role: 'user',
        content: message,
        timestamp: DateTime(2026, 11, 22),
      ),
      AiChatMessage(
        id: 'assistant-${sent.length}',
        role: 'assistant',
        content: longInsightsAnswer,
        timestamp: DateTime(2026, 11, 22),
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected AI call: ${invocation.memberName}');
}

const longInsightsAnswer = '''## Your spending, at a glance

Your receipts show **three useful patterns** for this month. The totals reflect the receipts you have saved.

- Dining was your largest category, followed by transport and household purchases.
- Several small purchases together account for a noticeable share of your total.
- Compare a complete month of receipts before drawing conclusions about a trend.

| Category | What to check |
| --- | --- |
| Food & dining | Frequent café and restaurant purchases |
| Transport | Recurring travel and fuel receipts |
| Household | One-off purchases and subscriptions |

### A useful next step

Review the original receipts for your largest purchases. You can then ask me to compare categories or summarize a different month.
''';
