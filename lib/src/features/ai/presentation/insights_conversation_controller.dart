import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../receipts/data/receipt_repository.dart';
import '../data/ai_repository.dart';
import '../models/chat_models.dart';

enum ConversationStatus { idle, sending, opening }

class InsightsConversation {
  const InsightsConversation({
    this.messages = const [],
    this.chatId,
    this.draft = '',
    this.pending,
    this.status = ConversationStatus.idle,
    this.error,
    this.scrollOffset = 0,
  });

  final List<AiChatMessage> messages;
  final String? chatId;
  final String draft;
  final AiChatMessage? pending;
  final ConversationStatus status;
  final String? error;
  final double scrollOffset;
  bool get busy => status != ConversationStatus.idle;

  InsightsConversation copyWith({
    List<AiChatMessage>? messages,
    String? chatId,
    String? draft,
    AiChatMessage? pending,
    bool clearPending = false,
    ConversationStatus? status,
    String? error,
    bool clearError = false,
    double? scrollOffset,
  }) => InsightsConversation(
    messages: messages ?? this.messages,
    chatId: chatId ?? this.chatId,
    draft: draft ?? this.draft,
    pending: clearPending ? null : pending ?? this.pending,
    status: status ?? this.status,
    error: clearError ? null : error ?? this.error,
    scrollOffset: scrollOffset ?? this.scrollOffset,
  );
}

// Keep only the current app session in memory. Returning from another tab does
// not lose a draft or an in-flight answer; opening the app starts a fresh chat.
// Watching the account also disposes pending work on sign-out/account changes.
final insightsConversationProvider =
    StateNotifierProvider.family<
      InsightsConversationController,
      InsightsConversation,
      String
    >((ref, uid) {
      final active = ref.watch(currentUserIdProvider) == uid;
      final ai = ref.watch(aiRepositoryProvider);
      return InsightsConversationController(
        uid: uid,
        ai: ai,
        active: active,
        insightData: () async {
          final receipts =
              ref.read(receiptsStreamProvider).valueOrNull ?? const [];
          final month = ref.read(selectedMonthProvider);
          final year = ref.read(selectedYearProvider);
          final label = ref.read(selectedMonthLabelProvider);
          final repository = ref.read(receiptRepositoryProvider);
          final summaries = await repository.getMonthlySummaries(uid);
          return ai.buildInsightData(
            receipts: receipts,
            monthlySummaries: summaries,
            month: month,
            year: year,
            monthLabel: label,
          );
        },
      );
    });

class InsightsConversationController
    extends StateNotifier<InsightsConversation> {
  InsightsConversationController({
    required this.uid,
    required this.ai,
    required this.insightData,
    this.active = true,
  }) : super(const InsightsConversation());

  final String uid;
  final AiRepository ai;
  final Future<Map<String, dynamic>> Function() insightData;
  final bool active;
  int _request = 0;
  bool _current(int request) => mounted && active && request == _request;

  void updateDraft(String text) {
    if (mounted && active && text != state.draft) {
      state = state.copyWith(draft: text);
    }
  }

  void rememberScroll(double offset) {
    if (mounted && active && state.scrollOffset != offset) {
      state = state.copyWith(scrollOffset: offset);
    }
  }

  void startNew() {
    if (!mounted || !active) return;
    ++_request;
    state = const InsightsConversation();
  }

  Future<void> open(String chatId) async {
    if (!mounted || !active) return;
    final request = ++_request;
    final previous = state;
    state = state.copyWith(
      status: ConversationStatus.opening,
      draft: '',
      clearPending: true,
      clearError: true,
    );
    try {
      final messages = await ai.loadChat(uid, chatId);
      if (!_current(request)) return;
      state = state.copyWith(
        messages: List.unmodifiable(messages),
        chatId: chatId,
        status: ConversationStatus.idle,
      );
    } catch (_) {
      if (!_current(request)) return;
      state = state.copyWith(
        draft: state.draft.isEmpty ? previous.draft : state.draft,
        status: ConversationStatus.idle,
        error: 'We couldn’t open this conversation. Please try again.',
      );
    }
  }

  Future<void> send([String? question]) async {
    if (!mounted || !active || state.busy) return;
    final message = (question ?? state.draft).trim();
    if (message.isEmpty) return;
    final request = ++_request;
    final previous = state;
    state = state.copyWith(
      draft: question == null ? '' : state.draft,
      pending: AiChatMessage(
        id: 'pending-$request',
        role: 'user',
        content: message,
        timestamp: DateTime.now(),
      ),
      status: ConversationStatus.sending,
      clearError: true,
    );
    try {
      final chatId = await ai.ensureChat(uid, preferredId: previous.chatId);
      if (!_current(request)) return;
      state = state.copyWith(chatId: chatId);
      final data = await insightData();
      if (!_current(request)) return;
      final messages = await ai.sendMessage(
        userId: uid,
        chatId: chatId,
        message: message,
        currentMessages: previous.messages,
        insightData: data,
      );
      if (!_current(request)) return;
      state = state.copyWith(
        messages: List.unmodifiable(messages),
        clearPending: true,
        status: ConversationStatus.idle,
      );
    } catch (_) {
      if (!_current(request)) return;
      state = state.copyWith(
        draft: question == null && state.draft.isEmpty ? message : state.draft,
        clearPending: true,
        status: ConversationStatus.idle,
        error:
            'We couldn’t send your question. Check your connection and try again.',
      );
    }
  }
}
