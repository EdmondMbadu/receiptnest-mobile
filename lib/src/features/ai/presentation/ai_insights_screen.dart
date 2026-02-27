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
    final history = ref.watch(aiChatHistoryProvider).valueOrNull ?? const [];
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final hasAccess = profile?.isAdmin == true || profile?.isPro == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Insights'),
        actions: [
          IconButton(
            onPressed: _newChat,
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New chat',
          ),
          IconButton(
            onPressed: _shareChat,
            icon: const Icon(Icons.share_outlined),
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
              width: 300,
              child: Card(
                margin: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Chat history'),
                      trailing: IconButton(
                        onPressed: _newChat,
                        icon: const Icon(Icons.add),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: history.length,
                        itemBuilder: (context, index) {
                          final chat = history[index];
                          return ListTile(
                            title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${chat.messageCount} messages'),
                            onTap: () => _openChat(chat.id),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Column(
              children: [
                if (!hasAccess)
                  MaterialBanner(
                    content: const Text('AI Insights is available for Pro users and admins.'),
                    actions: [
                      TextButton(
                        onPressed: () => context.push('/app/pricing'),
                        child: const Text('Upgrade'),
                      ),
                    ],
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: hasAccess ? _generateInsights : null,
                        icon: const Icon(Icons.lightbulb_outline),
                        label: Text(_insightsLoading ? 'Generating...' : 'Generate insights'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: hasAccess ? _openUploadInChat : null,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Upload in chat'),
                      ),
                    ],
                  ),
                ),
                if (_insights.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Insights', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            ..._insights.map((item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text('• $item'),
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final userMessage = message.role == 'user';

                      return Align(
                        alignment: userMessage ? Alignment.centerRight : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: Card(
                            color: userMessage ? Theme.of(context).colorScheme.primaryContainer : null,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: userMessage
                                  ? Text(message.content)
                                  : MarkdownBody(data: message.content),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ref
                            .watch(aiSuggestedQuestionsProvider)
                            .take(3)
                            .map(
                              (question) => ActionChip(
                                label: Text(question),
                                onPressed: hasAccess ? () => _sendMessage(question) : null,
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              enabled: !_loading && hasAccess,
                              minLines: 1,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                hintText: 'Ask about your spending...',
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _loading || !hasAccess ? null : _sendMessage,
                            child: Text(_loading ? 'Sending...' : 'Send'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      drawer: MediaQuery.of(context).size.width < 860
          ? Drawer(
              child: SafeArea(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Chat history'),
                      trailing: IconButton(
                        onPressed: _newChat,
                        icon: const Icon(Icons.add),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: history.length,
                        itemBuilder: (context, index) {
                          final chat = history[index];
                          return ListTile(
                            title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${chat.messageCount} messages'),
                            onTap: () {
                              Navigator.of(context).pop();
                              _openChat(chat.id);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
