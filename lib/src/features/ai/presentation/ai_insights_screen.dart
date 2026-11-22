import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth/data/auth_repository.dart';
import '../../receipts/data/receipt_repository.dart';
import '../../receipts/models/receipt.dart';
import '../../receipts/presentation/upload_receipt_sheet.dart';
import '../../share/data/share_repository.dart';
import '../../share/models/share_models.dart';
import '../data/ai_repository.dart';
import '../models/chat_models.dart';
import 'insights_widgets.dart';

class AiInsightsScreen extends ConsumerStatefulWidget {
  const AiInsightsScreen({super.key});
  @override
  ConsumerState<AiInsightsScreen> createState() => _AiInsightsScreenState();
}

class _AiInsightsScreenState extends ConsumerState<AiInsightsScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<AiChatMessage> _messages = const [];
  List<String> _insights = const [];
  bool _loading = false;
  bool _insightsLoading = false;
  bool _uploadOpen = false;
  bool _historyInitialized = false;
  int _chatRequest = 0;
  String? _error;

  bool _current(String uid, [int? request]) =>
      mounted &&
      ref.read(currentUserIdProvider) == uid &&
      (request == null || request == _chatRequest);

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openChat(String chatId) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final request = ++_chatRequest;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final messages = await ref
          .read(aiRepositoryProvider)
          .loadChat(uid, chatId);
      if (!_current(uid, request)) return;
      setState(() => _messages = messages);
      ref.read(aiActiveChatIdProvider.notifier).state = chatId;
      _scrollToBottom();
    } catch (_) {
      if (_current(uid, request)) {
        setState(
          () => _error =
              'We couldn’t open this conversation. Check your connection and try again.',
        );
      }
    } finally {
      if (_current(uid, request)) setState(() => _loading = false);
    }
  }

  Future<void> _generateInsights() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null || _insightsLoading) return;
    setState(() {
      _insightsLoading = true;
      _error = null;
    });
    try {
      final month = ref.read(selectedMonthProvider);
      final year = ref.read(selectedYearProvider);
      final label = ref.read(selectedMonthLabelProvider);
      final receipts = ref.read(receiptsStreamProvider).valueOrNull ?? const [];
      final summaries = await ref
          .read(receiptRepositoryProvider)
          .getMonthlySummaries(uid);
      if (!_current(uid)) return;
      final payload = ref
          .read(aiRepositoryProvider)
          .buildInsightData(
            receipts: receipts,
            monthlySummaries: summaries,
            month: month,
            year: year,
            monthLabel: label,
          );
      final insights = await ref
          .read(aiRepositoryProvider)
          .generateInitialInsights(insightData: payload);
      if (_current(uid)) setState(() => _insights = insights);
    } catch (_) {
      if (_current(uid)) {
        setState(
          () => _error =
              'We couldn’t load your insights. Please try again when you’re connected.',
        );
      }
    } finally {
      if (_current(uid)) setState(() => _insightsLoading = false);
    }
  }

  Future<void> _sendMessage([String? seededMessage]) async {
    final uid = ref.read(currentUserIdProvider);
    final message = (seededMessage ?? _messageController.text).trim();
    if (uid == null || message.isEmpty || _loading) return;
    final request = ++_chatRequest;
    final previousMessages = List<AiChatMessage>.of(_messages);
    final previousChatId = ref.read(aiActiveChatIdProvider);
    final month = ref.read(selectedMonthProvider);
    final year = ref.read(selectedYearProvider);
    final label = ref.read(selectedMonthLabelProvider);
    final receipts = ref.read(receiptsStreamProvider).valueOrNull ?? const [];
    if (seededMessage == null) _messageController.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _historyInitialized = true;
    });
    try {
      final repository = ref.read(aiRepositoryProvider);
      final chatId = await repository.ensureChat(
        uid,
        preferredId: previousChatId,
      );
      if (!_current(uid, request)) return;
      ref.read(aiActiveChatIdProvider.notifier).state = chatId;
      final summaries = await ref
          .read(receiptRepositoryProvider)
          .getMonthlySummaries(uid);
      if (!_current(uid, request)) return;
      final payload = repository.buildInsightData(
        receipts: receipts,
        monthlySummaries: summaries,
        month: month,
        year: year,
        monthLabel: label,
      );
      final next = await repository.sendMessage(
        userId: uid,
        chatId: chatId,
        message: message,
        currentMessages: previousMessages,
        insightData: payload,
      );
      if (!_current(uid, request)) return;
      setState(() => _messages = next);
      _scrollToBottom();
    } catch (_) {
      if (_current(uid, request)) {
        if (seededMessage == null && _messageController.text.isEmpty) {
          _messageController.text = message;
        }
        setState(
          () => _error =
              'We couldn’t send your question. Please check your connection and try again.',
        );
      }
    } finally {
      if (_current(uid, request)) setState(() => _loading = false);
    }
  }

  void _newChat() {
    ++_chatRequest;
    ref.read(aiActiveChatIdProvider.notifier).state = null;
    setState(() {
      _messages = const [];
      _error = null;
      _loading = false;
      _historyInitialized = true;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _shareChat() async {
    final uid = ref.read(currentUserIdProvider);
    final chatId = ref.read(aiActiveChatIdProvider);
    if (uid == null || chatId == null || _messages.isEmpty) return;
    try {
      final share = await ref
          .read(shareRepositoryProvider)
          .createChatShare(
            userId: uid,
            chatId: chatId,
            title: _messages.first.content,
            messages: _messages
                .map(
                  (message) => ChatShareMessage(
                    id: message.id,
                    role: message.role,
                    content: message.content,
                    timestamp: message.timestamp,
                  ),
                )
                .toList(),
          );
      if (!_current(uid)) return;
      await SharePlus.instance.share(
        ShareParams(text: 'https://receiptnest.web.app/share/${share.id}'),
      );
    } catch (_) {
      if (!mounted || !_current(uid)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'We couldn’t share this conversation. Please try again.',
          ),
        ),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openUploadInChat() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null || _uploadOpen || _loading) return;
    setState(() => _uploadOpen = true);
    Receipt? uploaded;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      constraints: const BoxConstraints(maxWidth: 540),
      builder: (_) => UploadReceiptSheet(
        userId: uid,
        repository: ref.read(receiptRepositoryProvider),
        onUploaded: (receipt) => uploaded = receipt,
      ),
    );
    if (!_current(uid)) return;
    setState(() => _uploadOpen = false);
    if (uploaded == null) return;
    final next = [
      ..._messages,
      AiChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        role: 'assistant',
        content:
            'Receipt uploaded: ${uploaded!.file.originalName}. It is now processing.',
        timestamp: DateTime.now(),
      ),
    ];
    setState(() => _messages = next);
    _scrollToBottom();
    try {
      final repository = ref.read(aiRepositoryProvider);
      final chatId = await repository.ensureChat(
        uid,
        preferredId: ref.read(aiActiveChatIdProvider),
      );
      if (!_current(uid)) return;
      ref.read(aiActiveChatIdProvider.notifier).state = chatId;
      await repository.persistChat(uid, chatId, next);
    } catch (_) {
      if (_current(uid)) {
        setState(
          () => _error =
              'Your receipt was uploaded, but we couldn’t save the chat note. Your receipt is still available in Home.',
        );
      }
    }
  }

  Widget _content(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(currentUserProfileProvider);
    final profile = profileState.valueOrNull;
    if (profile == null && profileState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (profileState.hasError && profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const InsightsNotice(
                message: 'We couldn’t check your account. Please try again.',
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => ref.invalidate(currentUserProfileProvider),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    final hasAccess = profile?.isAdmin == true || profile?.isPro == true;
    if (!hasAccess) {
      return InsightsUpgradeView(onUpgrade: () => context.push('/app/pricing'));
    }

    final historyState = ref.watch(aiChatHistoryProvider);
    final history = historyState.valueOrNull ?? const [];
    final activeChatId = ref.watch(aiActiveChatIdProvider);
    final questions = ref.watch(aiSuggestedQuestionsProvider);
    final monthLabel = ref.watch(selectedMonthLabelProvider);
    final hasReceipts =
        (ref.watch(receiptsStreamProvider).valueOrNull ?? const []).isNotEmpty;
    if (!_historyInitialized && historyState.hasValue) {
      _historyInitialized = true;
      if (history.isNotEmpty &&
          _messages.isEmpty &&
          _messageController.text.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openChat(history.first.id);
        });
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        Widget historyPanel({bool drawer = false}) => InsightsHistoryPanel(
          history: history,
          activeChatId: activeChatId,
          loading: historyState.isLoading && !historyState.hasValue,
          error: historyState.hasError,
          onNewChat: () {
            if (drawer) Navigator.of(context).pop();
            _newChat();
          },
          onOpen: (id) {
            if (drawer) Navigator.of(context).pop();
            _openChat(id);
          },
        );
        return Scaffold(
          key: _scaffoldKey,
          // The app shell already resizes its body above the keyboard. Resizing a
          // second Scaffold here would subtract the keyboard inset twice.
          resizeToAvoidBottomInset: false,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          drawer: compact
              ? Drawer(
                  width: math.min(340, constraints.maxWidth - 24),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: historyPanel(drawer: true),
                    ),
                  ),
                )
              : null,
          body: Row(
            children: [
              if (!compact)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 0, 20),
                  child: SizedBox(width: 260, child: historyPanel()),
                ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Scrollbar(
                        controller: _scrollController,
                        child: ListView(
                          key: const ValueKey('insights-content'),
                          controller: _scrollController,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          children: [
                            _content(
                              InsightsHeader(
                                monthLabel: monthLabel,
                                compact: compact,
                                onHistory: () =>
                                    _scaffoldKey.currentState?.openDrawer(),
                                onNewChat: _newChat,
                                onShare: _messages.isEmpty ? null : _shareChat,
                                onPricing: () => context.push('/app/pricing'),
                              ),
                            ),
                            const SizedBox(height: 20),
                            _content(
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  OutlinedButton.icon(
                                    key: const ValueKey('insights-generate'),
                                    onPressed: _insightsLoading
                                        ? null
                                        : _generateInsights,
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 44),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                    ),
                                    icon: Icon(
                                      _insightsLoading
                                          ? Icons.hourglass_top_rounded
                                          : Icons.lightbulb_outline_rounded,
                                      size: 19,
                                    ),
                                    label: Text(
                                      _insightsLoading
                                          ? 'Generating…'
                                          : 'Generate insights',
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _uploadOpen || _loading
                                        ? null
                                        : _openUploadInChat,
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 44),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.add_photo_alternate_outlined,
                                      size: 19,
                                    ),
                                    label: const Text('Add receipt'),
                                  ),
                                ],
                              ),
                            ),
                            if (_insightsLoading) ...[
                              const SizedBox(height: 18),
                              _content(
                                Semantics(
                                  label: 'Generating spending insights',
                                  liveRegion: true,
                                  child: LinearProgressIndicator(minHeight: 3),
                                ),
                              ),
                            ],
                            if (_insights.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              _content(
                                InsightsSummaryCard(
                                  key: const ValueKey('generated-insights'),
                                  insights: _insights,
                                ),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              _content(InsightsNotice(message: _error!)),
                            ],
                            if (_messages.isEmpty && !_loading)
                              _content(
                                InsightsEmptyConversation(
                                  questions: questions,
                                  onQuestion: _sendMessage,
                                  hasReceipts: hasReceipts,
                                ),
                              ),
                            for (final message in _messages)
                              _content(
                                InsightsMessage(
                                  key: ValueKey(message.id),
                                  message: message,
                                ),
                              ),
                            if (_loading)
                              Padding(
                                padding: const EdgeInsets.only(top: 20),
                                child: _content(
                                  const InsightsSurface(
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'Working on your answer…',
                                            style: TextStyle(
                                              fontSize: 13,
                                              height: 1.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    InsightsComposer(
                      controller: _messageController,
                      onSend: _sendMessage,
                      busy: _loading,
                      compactHeight: constraints.maxHeight < 360,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
