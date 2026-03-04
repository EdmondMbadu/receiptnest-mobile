import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../auth/data/auth_repository.dart';
import '../../receipts/data/receipt_repository.dart';
import '../../receipts/presentation/upload_receipt_sheet.dart';
import '../../share/data/share_repository.dart';
import '../../share/models/share_models.dart';
import '../data/ai_repository.dart';
import '../models/chat_models.dart';

class AiInsightsScreen extends ConsumerStatefulWidget {
  const AiInsightsScreen({super.key});

  @override
  ConsumerState<AiInsightsScreen> createState() => _AiInsightsScreenState();
}

class _AiInsightsScreenState extends ConsumerState<AiInsightsScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  List<AiChatMessage> _messages = const [];
  bool _loading = false;
  bool _insightsLoading = false;
  String? _error;
  List<String> _insights = const [];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
  }

  Future<void> _initialize() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    final history = ref.read(aiChatHistoryProvider).valueOrNull ?? const [];
    if (history.isNotEmpty) {
      final chatId = history.first.id;
      ref.read(aiActiveChatIdProvider.notifier).state = chatId;
      await _openChat(chatId);
    }
  }

  Future<void> _openChat(String chatId) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final messages =
          await ref.read(aiRepositoryProvider).loadChat(uid, chatId);
      setState(() {
        _messages = messages;
      });
      ref.read(aiActiveChatIdProvider.notifier).state = chatId;
      _scrollToBottom();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _generateInsights() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    setState(() {
      _insightsLoading = true;
      _error = null;
    });

    try {
      final month = ref.read(selectedMonthProvider);
      final year = ref.read(selectedYearProvider);
      final label = ref.read(selectedMonthLabelProvider);
      final receipts =
          ref.read(receiptsStreamProvider).valueOrNull ?? const [];
      final monthlySummaries = await ref
          .read(receiptRepositoryProvider)
          .getMonthlySummaries(uid);

      final payload = ref.read(aiRepositoryProvider).buildInsightData(
            receipts: receipts,
            monthlySummaries: monthlySummaries,
            month: month,
            year: year,
            monthLabel: label,
          );

      final insights = await ref
          .read(aiRepositoryProvider)
          .generateInitialInsights(insightData: payload);
      setState(() => _insights = insights);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _insightsLoading = false);
      }
    }
  }

  Future<void> _sendMessage([String? seededMessage]) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    final message = (seededMessage ?? _messageController.text).trim();
    if (message.isEmpty || _loading) return;

    if (seededMessage == null) {
      _messageController.clear();
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final currentChatId = ref.read(aiActiveChatIdProvider);
      final chatId = await ref
          .read(aiRepositoryProvider)
          .ensureChat(uid, preferredId: currentChatId);
      ref.read(aiActiveChatIdProvider.notifier).state = chatId;

      final month = ref.read(selectedMonthProvider);
      final year = ref.read(selectedYearProvider);
      final label = ref.read(selectedMonthLabelProvider);
      final receipts =
          ref.read(receiptsStreamProvider).valueOrNull ?? const [];
      final monthlySummaries = await ref
          .read(receiptRepositoryProvider)
          .getMonthlySummaries(uid);

      final payload = ref.read(aiRepositoryProvider).buildInsightData(
            receipts: receipts,
            monthlySummaries: monthlySummaries,
            month: month,
            year: year,
            monthLabel: label,
          );

      final next = await ref.read(aiRepositoryProvider).sendMessage(
            userId: uid,
            chatId: chatId,
            message: message,
            currentMessages: _messages,
            insightData: payload,
          );

      setState(() {
        _messages = next;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _newChat() async {
    ref.read(aiActiveChatIdProvider.notifier).state = null;
    setState(() {
      _messages = const [];
      _error = null;
    });
  }

  Future<void> _shareChat() async {
    final uid = ref.read(currentUserIdProvider);
    final chatId = ref.read(aiActiveChatIdProvider);
    if (uid == null || chatId == null || _messages.isEmpty) return;

    try {
      final share = await ref.read(shareRepositoryProvider).createChatShare(
            userId: uid,
            chatId: chatId,
            title: _messages.first.content,
            messages: _messages
                .map((message) => ChatShareMessage(
                      id: message.id,
                      role: message.role,
                      content: message.content,
                      timestamp: message.timestamp,
                    ))
                .toList(),
          );

      await SharePlus.instance.share(
        ShareParams(
            text: 'https://receiptnest.web.app/share/${share.id}'),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share chat: $e')),
      );
    }
  }

  Future<void> _connectTelegram() async {
    try {
      final deepLink =
          await ref.read(aiRepositoryProvider).generateTelegramLinkToken();
      if (deepLink == null || deepLink.isEmpty) {
        throw Exception('No Telegram link returned by server.');
      }
      await launchUrlString(deepLink, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect Telegram: $e')),
      );
    }
  }

  Future<void> _unlinkTelegram() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    try {
      await ref.read(aiRepositoryProvider).unlinkTelegram(uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telegram unlinked.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to unlink Telegram: $e')),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openUploadInChat() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return UploadReceiptSheet(
          userId: uid,
          repository: ref.read(receiptRepositoryProvider),
          onUploaded: (receipt) async {
            final message =
                'Receipt uploaded: ${receipt.file.originalName}. It is now processing.';
            final next = [
              ..._messages,
              AiChatMessage(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                role: 'assistant',
                content: message,
                timestamp: DateTime.now(),
              ),
            ];
            setState(() {
              _messages = next;
            });

            final chatId =
                await ref.read(aiRepositoryProvider).ensureChat(
                      uid,
                      preferredId: ref.read(aiActiveChatIdProvider),
                    );
            ref.read(aiActiveChatIdProvider.notifier).state = chatId;
            await ref
                .read(aiRepositoryProvider)
                .persistChat(uid, chatId, next);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final history =
        ref.watch(aiChatHistoryProvider).valueOrNull ?? const [];
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final hasAccess = profile?.isAdmin == true || profile?.isPro == true;

    Widget buildHistorySidebar() {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF151520) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.grey.shade200,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.history_rounded,
                        size: 16, color: cs.primary),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'History',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: IconButton(
                      onPressed: _newChat,
                      icon: Icon(Icons.add_rounded,
                          size: 18, color: cs.primary),
                      padding: EdgeInsets.zero,
                      tooltip: 'New chat',
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.grey.shade100,
            ),
            Expanded(
              child: ListView.builder(
                itemCount: history.length,
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                itemBuilder: (context, index) {
                  final chat = history[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openChat(chat.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 16,
                                color:
                                    cs.onSurface.withValues(alpha: 0.35),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      chat.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${chat.messageCount} messages',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurface
                                            .withValues(alpha: 0.35),
                                      ),
                                    ),
                                  ],
                                ),
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
    }

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D0D14) : const Color(0xFFF6F7F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('AI Insights'),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
        actions: [
          Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              onPressed: _newChat,
              icon: Icon(Icons.add_comment_outlined,
                  size: 18, color: cs.primary),
              padding: EdgeInsets.zero,
              tooltip: 'New chat',
            ),
          ),
          Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              onPressed: _shareChat,
              icon: Icon(Icons.share_outlined,
                  size: 18, color: cs.primary),
              padding: EdgeInsets.zero,
              tooltip: 'Share chat',
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded,
                size: 22, color: cs.onSurface.withValues(alpha: 0.6)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: (value) {
              switch (value) {
                case 'connect_telegram':
                  _connectTelegram();
                  break;
                case 'unlink_telegram':
                  _unlinkTelegram();
                  break;
                case 'pricing':
                  context.push('/app/pricing');
                  break;
              }
            },
            itemBuilder: (context) {
              return const [
                PopupMenuItem(
                    value: 'connect_telegram',
                    child: Text('Connect Telegram')),
                PopupMenuItem(
                    value: 'unlink_telegram',
                    child: Text('Unlink Telegram')),
                PopupMenuItem(
                    value: 'pricing', child: Text('Open Pricing')),
              ];
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          if (MediaQuery.of(context).size.width >= 860)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 0, 16),
              child: SizedBox(
                width: 280,
                child: buildHistorySidebar(),
              ),
            ),
          Expanded(
            child: Column(
              children: [
                // ── Pro upgrade banner ──
                if (!hasAccess)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          cs.primary.withValues(alpha: 0.08),
                          cs.primary.withValues(alpha: 0.03),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: cs.primary.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.diamond_outlined,
                              color: cs.primary, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'AI Insights is available for Pro users.',
                            style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurface,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                        FilledButton(
                          onPressed: () => context.push('/app/pricing'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            textStyle: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                          child: const Text('Upgrade'),
                        ),
                      ],
                    ),
                  ),

                // ── Action buttons ──
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: OutlinedButton.icon(
                            onPressed:
                                hasAccess ? _generateInsights : null,
                            icon: Icon(
                              _insightsLoading
                                  ? Icons.hourglass_top_rounded
                                  : Icons.lightbulb_outline,
                              size: 18,
                            ),
                            label: Text(
                              _insightsLoading
                                  ? 'Generating...'
                                  : 'Insights',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: BorderSide(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.grey.shade300,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: OutlinedButton.icon(
                            onPressed:
                                hasAccess ? _openUploadInChat : null,
                            icon: const Icon(
                                Icons.upload_file_outlined,
                                size: 18),
                            label: const Text(
                              'Upload',
                              style:
                                  TextStyle(fontWeight: FontWeight.w600),
                            ),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: BorderSide(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.grey.shade300,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Insights card ──
                if (_insights.isNotEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF151520)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.grey.shade200,
                        ),
                        boxShadow: isDark
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: 0.04),
                                  blurRadius: 20,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: Colors.amber
                                      .withValues(alpha: 0.15),
                                  borderRadius:
                                      BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.lightbulb_rounded,
                                    size: 16,
                                    color: Colors.amber.shade700),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Insights',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          ..._insights.map((item) => Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      margin:
                                          const EdgeInsets.only(top: 6),
                                      decoration: BoxDecoration(
                                        color: cs.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        item,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: cs.onSurface
                                              .withValues(alpha: 0.8),
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                  ),

                // ── Error banner ──
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: cs.error.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded,
                              size: 16, color: cs.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                  color: cs.error,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Chat messages ──
                Expanded(
                  child: _messages.isEmpty && !_loading
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      cs.primary
                                          .withValues(alpha: 0.12),
                                      cs.primary
                                          .withValues(alpha: 0.04),
                                    ],
                                  ),
                                  borderRadius:
                                      BorderRadius.circular(20),
                                ),
                                child: Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 32,
                                  color: cs.primary
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Ask about your spending',
                                style: TextStyle(
                                  color: cs.onSurface
                                      .withValues(alpha: 0.4),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Your AI assistant is ready to help',
                                style: TextStyle(
                                  color: cs.onSurface
                                      .withValues(alpha: 0.25),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(
                              16, 8, 16, 8),
                          itemCount: _messages.length +
                              (_loading ? 1 : 0),
                          itemBuilder: (context, index) {
                            // Typing indicator
                            if (index == _messages.length) {
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(
                                          vertical: 8),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF1A1A28)
                                          : Colors.grey.shade100,
                                      borderRadius:
                                          BorderRadius.circular(
                                              18),
                                    ),
                                    child: SizedBox(
                                      width: 40,
                                      height: 12,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment
                                                .spaceEvenly,
                                        children: List.generate(
                                            3, (i) {
                                          return Container(
                                            width: 7,
                                            height: 7,
                                            decoration:
                                                BoxDecoration(
                                              color: cs.primary
                                                  .withValues(
                                                      alpha: 0.4),
                                              shape:
                                                  BoxShape.circle,
                                            ),
                                          );
                                        }),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }

                            final message = _messages[index];
                            final userMessage =
                                message.role == 'user';

                            return Align(
                              alignment: userMessage
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context)
                                              .size
                                              .width *
                                          0.82,
                                ),
                                child: Container(
                                  margin:
                                      const EdgeInsets.symmetric(
                                          vertical: 5),
                                  padding:
                                      const EdgeInsets.all(15),
                                  decoration: BoxDecoration(
                                    color: userMessage
                                        ? cs.primary
                                        : (isDark
                                            ? const Color(
                                                0xFF1A1A28)
                                            : Colors
                                                .grey.shade100),
                                    borderRadius:
                                        BorderRadius.only(
                                      topLeft:
                                          const Radius.circular(
                                              20),
                                      topRight:
                                          const Radius.circular(
                                              20),
                                      bottomLeft:
                                          Radius.circular(
                                              userMessage
                                                  ? 20
                                                  : 4),
                                      bottomRight:
                                          Radius.circular(
                                              userMessage
                                                  ? 4
                                                  : 20),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(
                                                alpha: 0.04),
                                        blurRadius: 8,
                                        offset:
                                            const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: userMessage
                                      ? Text(
                                          message.content,
                                          style: TextStyle(
                                            color: cs.onPrimary,
                                            fontSize: 14.5,
                                            height: 1.4,
                                          ),
                                        )
                                      : MarkdownBody(
                                          data:
                                              message.content),
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // ── Input area ──
                Container(
                  padding:
                      const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0D0D14)
                        : const Color(0xFFF6F7F9),
                    border: Border(
                      top: BorderSide(
                        color: isDark
                            ? Colors.white
                                .withValues(alpha: 0.06)
                            : Colors.grey.shade200,
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      children: [
                        if (ref
                            .watch(aiSuggestedQuestionsProvider)
                            .isNotEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: 10),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: ref
                                    .watch(
                                        aiSuggestedQuestionsProvider)
                                    .take(3)
                                    .map(
                                      (question) => Padding(
                                        padding:
                                            const EdgeInsets.only(
                                                right: 8),
                                        child: ActionChip(
                                          label: Text(
                                            question,
                                            style:
                                                const TextStyle(
                                                    fontSize:
                                                        12.5),
                                          ),
                                          shape:
                                              RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius
                                                    .circular(
                                                        20),
                                          ),
                                          side: BorderSide(
                                            color: isDark
                                                ? Colors.white
                                                    .withValues(
                                                        alpha:
                                                            0.08)
                                                : Colors.grey
                                                    .shade300,
                                          ),
                                          onPressed: hasAccess
                                              ? () =>
                                                  _sendMessage(
                                                      question)
                                              : null,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                enabled:
                                    !_loading && hasAccess,
                                minLines: 1,
                                maxLines: 4,
                                decoration: InputDecoration(
                                  hintText:
                                      'Ask about your spending...',
                                  hintStyle: TextStyle(
                                    color: cs.onSurface
                                        .withValues(
                                            alpha: 0.3),
                                  ),
                                  filled: true,
                                  fillColor: isDark
                                      ? const Color(0xFF151520)
                                      : Colors.white,
                                  contentPadding:
                                      const EdgeInsets
                                          .symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(
                                            24),
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? Colors.white
                                              .withValues(
                                                  alpha: 0.08)
                                          : Colors
                                              .grey.shade200,
                                    ),
                                  ),
                                  enabledBorder:
                                      OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(
                                            24),
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? Colors.white
                                              .withValues(
                                                  alpha: 0.08)
                                          : Colors
                                              .grey.shade200,
                                    ),
                                  ),
                                  focusedBorder:
                                      OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(
                                            24),
                                    borderSide: BorderSide(
                                        color: cs.primary,
                                        width: 1.5),
                                  ),
                                ),
                                onSubmitted: (_) =>
                                    _sendMessage(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    cs.primary,
                                    cs.primary.withValues(
                                        alpha: 0.8),
                                  ],
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: cs.primary
                                        .withValues(
                                            alpha: 0.3),
                                    blurRadius: 12,
                                    offset:
                                        const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: IconButton(
                                onPressed:
                                    _loading || !hasAccess
                                        ? null
                                        : () =>
                                            _sendMessage(),
                                icon: Icon(
                                  Icons
                                      .arrow_upward_rounded,
                                  color: cs.onPrimary,
                                  size: 22,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      drawer: MediaQuery.of(context).size.width < 860
          ? Drawer(
              backgroundColor:
                  isDark ? const Color(0xFF0D0D14) : const Color(0xFFF6F7F9),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: buildHistorySidebar(),
                ),
              ),
            )
          : null,
    );
  }
}
