import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/widgets/keyboard_inset_scope.dart';

import '../../auth/data/auth_repository.dart';
import '../../receipts/data/receipt_repository.dart';
import '../../share/data/share_repository.dart';
import '../../share/models/share_models.dart';
import '../data/ai_repository.dart';
import 'insights_conversation_controller.dart';
import 'insights_widgets.dart';

class AiInsightsScreen extends ConsumerWidget {
  const AiInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(currentUserProfileProvider);
    final uid = ref.watch(currentUserIdProvider);
    final candidate = profileState.valueOrNull;
    final profile = candidate?.id == uid ? candidate : null;
    if (uid == null || (profile == null && profileState.isLoading)) {
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
    if (profile?.isAdmin != true && profile?.isPro != true) {
      return InsightsUpgradeView(onUpgrade: () => context.push('/app/pricing'));
    }
    return _ConversationView(key: ValueKey(uid), userId: uid);
  }
}

class _ConversationView extends ConsumerStatefulWidget {
  const _ConversationView({super.key, required this.userId});
  final String userId;
  @override
  ConsumerState<_ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends ConsumerState<_ConversationView> {
  late final TextEditingController _messageController;
  final _inputFocus = FocusNode();
  late final ScrollController _scrollController;
  InsightsConversationController get _conversation =>
      ref.read(insightsConversationProvider(widget.userId).notifier);

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController(
      text: ref.read(insightsConversationProvider(widget.userId)).draft,
    )..addListener(_saveDraft);
    _scrollController = ScrollController(
      initialScrollOffset: ref
          .read(insightsConversationProvider(widget.userId))
          .scrollOffset,
    )..addListener(_saveScroll);
  }

  void _saveDraft() => _conversation.updateDraft(_messageController.text);
  void _saveScroll() => _conversation.rememberScroll(_scrollController.offset);

  @override
  void dispose() {
    _messageController
      ..removeListener(_saveDraft)
      ..dispose();
    _inputFocus.dispose();
    _scrollController
      ..removeListener(_saveScroll)
      ..dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _send([String? question]) {
    FocusScope.of(context).unfocus();
    _conversation.send(question);
  }

  void _newQuestion() {
    _conversation.startNew();
    // The empty view attaches a different scroll position on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) _scrollController.jumpTo(0);
    });
    _inputFocus.requestFocus();
  }

  Future<void> _history() async {
    FocusScope.of(context).unfocus();
    String? selected;
    var startNew = false;
    await showModalBottomSheet<void>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 540),
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.7,
        child: Consumer(
          builder: (context, ref, _) {
            final history = ref.watch(aiChatHistoryProvider);
            return InsightsHistoryPanel(
              history: history.valueOrNull ?? const [],
              activeChatId: ref
                  .watch(insightsConversationProvider(widget.userId))
                  .chatId,
              loading: history.isLoading && !history.hasValue,
              error: history.hasError,
              onRetry: () => ref.invalidate(aiChatHistoryProvider),
              onNewChat: () {
                startNew = true;
                Navigator.of(sheetContext).pop();
              },
              onOpen: (id) {
                selected = id;
                Navigator.of(sheetContext).pop();
              },
            );
          },
        ),
      ),
    );
    if (!mounted || ref.read(currentUserIdProvider) != widget.userId) return;
    if (startNew) {
      _newQuestion();
    } else if (selected != null) {
      await _conversation.open(selected!);
      if (mounted) _scrollToBottom();
    }
  }

  Future<void> _share() async {
    final conversation = ref.read(insightsConversationProvider(widget.userId));
    if (conversation.chatId == null || conversation.messages.isEmpty) return;
    try {
      final share = await ref
          .read(shareRepositoryProvider)
          .createChatShare(
            userId: widget.userId,
            chatId: conversation.chatId!,
            title: conversation.messages.first.content,
            messages: conversation.messages
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
      if (!mounted || ref.read(currentUserIdProvider) != widget.userId) return;
      await SharePlus.instance.share(
        ShareParams(text: 'https://receiptnest.web.app/share/${share.id}'),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'We couldn’t share this conversation. Please try again.',
          ),
        ),
      );
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
    final provider = insightsConversationProvider(widget.userId);
    // Typing updates the saved draft without rebuilding the Markdown transcript.
    final conversation = ref.watch(
      provider.select(
        (state) => (
          messages: state.messages,
          chatId: state.chatId,
          pending: state.pending,
          status: state.status,
          error: state.error,
        ),
      ),
    );
    ref.listen(provider.select((state) => state.draft), (_, text) {
      if (_messageController.text != text) {
        _messageController.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    });
    ref.listen(provider, (previous, next) {
      if (next.pending != null && previous?.pending?.id != next.pending?.id) {
        _scrollToBottom();
      }
      if (next.error != null && next.error != previous?.error) {
        _scrollToBottom();
      }
      // Keep the reader at the start of a new answer instead of jumping past it.
    });
    final busy = conversation.status != ConversationStatus.idle;
    final empty = conversation.messages.isEmpty && !busy;
    final questions = ref.watch(aiSuggestedQuestionsProvider);
    final hasReceipts =
        (ref.watch(receiptsStreamProvider).valueOrNull ?? const []).isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxHeight < 240;
        final compact =
            KeyboardInsetScope.isVisibleOf(context) ||
            constraints.maxHeight < 400;
        final messages = [
          ...conversation.messages,
          if (conversation.pending != null) conversation.pending!,
        ];
        final extraCount =
            (busy ? 1 : 0) + (conversation.error != null ? 1 : 0);
        return Column(
          children: [
            if (!tight)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                child: _content(
                  InsightsHeader(
                    compact: compact,
                    monthLabel: ref.watch(selectedMonthLabelProvider),
                    onHistory: _history,
                    onNewChat: messages.isEmpty && !busy ? null : _newQuestion,
                    onShare: conversation.messages.isEmpty || busy
                        ? null
                        : _share,
                  ),
                ),
              ),
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                child: empty && conversation.error == null
                    ? SingleChildScrollView(
                        key: const ValueKey('insights-content'),
                        controller: _scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                        child: _content(
                          compact
                              ? const SizedBox.shrink()
                              : InsightsEmptyConversation(
                                  questions: questions,
                                  onQuestion: _send,
                                  hasReceipts: hasReceipts,
                                ),
                        ),
                      )
                    : ListView.builder(
                        key: const ValueKey('insights-content'),
                        controller: _scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        itemCount: messages.length + extraCount,
                        itemBuilder: (context, index) {
                          if (index < messages.length) {
                            final message = messages[index];
                            return _content(
                              InsightsMessage(
                                key: ValueKey(message.id),
                                message: message,
                              ),
                            );
                          }
                          if (busy && index == messages.length) {
                            return _content(
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 20,
                                ),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Row(
                                    children: [
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          conversation.status ==
                                                  ConversationStatus.opening
                                              ? 'Opening conversation…'
                                              : 'Thinking…',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                          return _content(
                            InsightsNotice(message: conversation.error!),
                          );
                        },
                      ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * (tight ? 1 : 0.45),
              ),
              child: SingleChildScrollView(
                child: InsightsComposer(
                  controller: _messageController,
                  focusNode: _inputFocus,
                  onSend: _send,
                  busy: busy,
                  compactHeight: compact,
                  singleLine: constraints.maxHeight < 130,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
