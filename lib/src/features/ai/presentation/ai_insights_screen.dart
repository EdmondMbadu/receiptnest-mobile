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
      final messages = await ref.read(aiRepositoryProvider).loadChat(uid, chatId);
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
      final receipts = ref.read(receiptsStreamProvider).valueOrNull ?? const [];
      final monthlySummaries = await ref.read(receiptRepositoryProvider).getMonthlySummaries(uid);

      final payload = ref.read(aiRepositoryProvider).buildInsightData(
            receipts: receipts,
            monthlySummaries: monthlySummaries,
            month: month,
            year: year,
            monthLabel: label,
          );

      final insights = await ref.read(aiRepositoryProvider).generateInitialInsights(insightData: payload);
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
      final chatId = await ref.read(aiRepositoryProvider).ensureChat(uid, preferredId: currentChatId);
      ref.read(aiActiveChatIdProvider.notifier).state = chatId;

      final month = ref.read(selectedMonthProvider);
      final year = ref.read(selectedYearProvider);
      final label = ref.read(selectedMonthLabelProvider);
      final receipts = ref.read(receiptsStreamProvider).valueOrNull ?? const [];
      final monthlySummaries = await ref.read(receiptRepositoryProvider).getMonthlySummaries(uid);

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
        ShareParams(text: 'https://receiptnest.web.app/share/${share.id}'),
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
      final deepLink = await ref.read(aiRepositoryProvider).generateTelegramLinkToken();
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
            final message = 'Receipt uploaded: ${receipt.file.originalName}. It is now processing.';
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

            final chatId = await ref.read(aiRepositoryProvider).ensureChat(
                  uid,
                  preferredId: ref.read(aiActiveChatIdProvider),
                );
            ref.read(aiActiveChatIdProvider.notifier).state = chatId;
            await ref.read(aiRepositoryProvider).persistChat(uid, chatId, next);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final history = ref.watch(aiChatHistoryProvider).valueOrNull ?? const [];
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final hasAccess = profile?.isAdmin == true || profile?.isPro == true;

    Widget buildHistorySidebar() {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Text(
                  'History',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  onPressed: _newChat,
                  icon: const Icon(Icons.add_rounded, size: 22),
                  tooltip: 'New chat',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: history.length,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemBuilder: (context, index) {
                final chat = history[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  child: ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 18,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                    title: Text(
                      chat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      '${chat.messageCount} messages',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                    onTap: () => _openChat(chat.id),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Insights'),
        actions: [
          IconButton(
            onPressed: _newChat,
            icon: const Icon(Icons.add_comment_outlined, size: 22),
            tooltip: 'New chat',
          ),
          IconButton(
            onPressed: _shareChat,
            icon: const Icon(Icons.share_outlined, size: 22),
            tooltip: 'Share chat',
          ),
          PopupMenuButton<String>(
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
                PopupMenuItem(value: 'connect_telegram', child: Text('Connect Telegram')),
                PopupMenuItem(value: 'unlink_telegram', child: Text('Unlink Telegram')),
                PopupMenuItem(value: 'pricing', child: Text('Open Pricing')),
              ];
            },
          ),
        ],
      ),
      body: Row(
        children: [
          if (MediaQuery.of(context).size.width >= 860)
            SizedBox(
              width: 280,
              child: Card(
                margin: const EdgeInsets.fromLTRB(12, 4, 0, 12),
                child: buildHistorySidebar(),
              ),
            ),
          Expanded(
            child: Column(
              children: [
                if (!hasAccess)
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.diamond_outlined, color: cs.primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'AI Insights is available for Pro users.',
                            style: TextStyle(fontSize: 13, color: cs.onSurface),
                          ),
                        ),
                        FilledButton(
                          onPressed: () => context.push('/app/pricing'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            textStyle: const TextStyle(fontSize: 13),
                          ),
                          child: const Text('Upgrade'),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: hasAccess ? _generateInsights : null,
                        icon: const Icon(Icons.lightbulb_outline, size: 18),
                        label: Text(_insightsLoading ? 'Generating...' : 'Insights'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: hasAccess ? _openUploadInChat : null,
                        icon: const Icon(Icons.upload_file_outlined, size: 18),
                        label: const Text('Upload'),
                      ),
                    ],
                  ),
                ),
                if (_insights.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.lightbulb_rounded, size: 18, color: Colors.amber.shade600),
                                const SizedBox(width: 8),
                                Text('Insights', style: Theme.of(context).textTheme.titleMedium),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ..._insights.map((item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '\u2022  ',
                                        style: TextStyle(
                                          color: cs.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Expanded(child: Text(item, style: const TextStyle(fontSize: 14))),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(color: cs.error, fontSize: 13),
                      ),
                    ),
                  ),
                Expanded(
                  child: _messages.isEmpty && !_loading
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 48,
                                color: cs.onSurface.withValues(alpha: 0.12),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Ask about your spending',
                                style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.35),
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          itemCount: _messages.length + (_loading ? 1 : 0),
                          itemBuilder: (context, index) {
                            // Typing indicator
                            if (index == _messages.length) {
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.05)
                                          : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: SizedBox(
                                      width: 40,
                                      height: 12,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                        children: List.generate(3, (i) {
                                          return Container(
                                            width: 7,
                                            height: 7,
                                            decoration: BoxDecoration(
                                              color: cs.primary.withValues(alpha: 0.4),
                                              shape: BoxShape.circle,
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
                            final userMessage = message.role == 'user';

                            return Align(
                              alignment: userMessage
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.82,
                                ),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: userMessage
                                        ? cs.primary
                                        : (isDark
                                            ? Colors.white.withValues(alpha: 0.05)
                                            : Colors.grey.shade100),
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(18),
                                      topRight: const Radius.circular(18),
                                      bottomLeft: Radius.circular(userMessage ? 18 : 4),
                                      bottomRight: Radius.circular(userMessage ? 4 : 18),
                                    ),
                                  ),
                                  child: userMessage
                                      ? Text(
                                          message.content,
                                          style: TextStyle(
                                            color: cs.onPrimary,
                                            fontSize: 14.5,
                                          ),
                                        )
                                      : MarkdownBody(data: message.content),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                // Input area
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.grey.shade200,
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      children: [
                        if (ref.watch(aiSuggestedQuestionsProvider).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: ref
                                    .watch(aiSuggestedQuestionsProvider)
                                    .take(3)
                                    .map(
                                      (question) => Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: ActionChip(
                                          label: Text(
                                            question,
                                            style: const TextStyle(fontSize: 12.5),
                                          ),
                                          onPressed: hasAccess
                                              ? () => _sendMessage(question)
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
                                enabled: !_loading && hasAccess,
                                minLines: 1,
                                maxLines: 4,
                                decoration: InputDecoration(
                                  hintText: 'Ask about your spending...',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.10)
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.10)
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide(color: cs.primary, width: 1.5),
                                  ),
                                ),
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: cs.primary,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                onPressed: _loading || !hasAccess ? null : () => _sendMessage(),
                                icon: Icon(
                                  Icons.arrow_upward_rounded,
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
          ? Drawer(child: SafeArea(child: buildHistorySidebar()))
          : null,
    );
  }
}
