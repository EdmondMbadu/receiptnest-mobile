import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/chat_models.dart';

class InsightsSurface extends StatelessWidget {
  const InsightsSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.tinted = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool tinted;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF17231F) : Colors.white,
        gradient: tinted
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0xFF18362D), Color(0xFF17231F)]
                    : const [Color(0xFFEAF5EE), Color(0xFFFAFCF8)],
              )
            : null,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: dark ? 0.3 : 0.55),
        ),
      ),
      child: child,
    );
  }
}

class InsightsUpgradeView extends StatelessWidget {
  const InsightsUpgradeView({super.key, required this.onUpgrade});
  final VoidCallback onUpgrade;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey('insights-upgrade-scroll'),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_outlined,
                          color: cs.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'AI Insights',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'PRO',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 1,
                              fontWeight: FontWeight.w800,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    InsightsSurface(
                      tinted: true,
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'A clearer view of your spending.',
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(
                                  fontSize: 28,
                                  height: 1.2,
                                  letterSpacing: -0.8,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Turn your saved receipts into answers, patterns, and useful insights.',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Padding(
                      padding: EdgeInsets.only(left: 2, bottom: 12),
                      child: Text(
                        'Included with Pro',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    InsightsSurface(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 4,
                      ),
                      child: Column(
                        children: [
                          const _FeatureRow(
                            icon: Icons.pie_chart_outline_rounded,
                            title: 'Monthly insights',
                            subtitle: 'See where your money went.',
                          ),
                          Divider(
                            height: 1,
                            color: cs.outlineVariant.withValues(alpha: 0.5),
                          ),
                          const _FeatureRow(
                            icon: Icons.chat_bubble_outline_rounded,
                            title: 'Ask about your receipts',
                            subtitle: 'Get answers from your saved receipts.',
                          ),
                          Divider(
                            height: 1,
                            color: cs.outlineVariant.withValues(alpha: 0.5),
                          ),
                          const _FeatureRow(
                            icon: Icons.trending_up_rounded,
                            title: 'Spending trends',
                            subtitle: 'Explore categories and spot changes.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Keep the action outside the scroll area, including with large text
        // or when the shell's receipt upload activity bar is visible.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('insights-upgrade'),
                  onPressed: onUpgrade,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                  ),
                  icon: const Icon(Icons.diamond_outlined, size: 20),
                  label: const Text('Upgrade to Pro'),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: cs.primary, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class InsightsHeader extends StatelessWidget {
  const InsightsHeader({
    super.key,
    required this.monthLabel,
    required this.onHistory,
    required this.onNewChat,
    required this.onShare,
    this.compact = false,
  });
  final String monthLabel;
  final VoidCallback onHistory;
  final VoidCallback? onNewChat;
  final VoidCallback? onShare;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Insights',
                key: ValueKey('insights-heading'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 3),
                Text(
                  monthLabel,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        IconButton(
          onPressed: onHistory,
          tooltip: 'Conversation history',
          icon: const Icon(Icons.history_rounded, size: 22),
        ),
        if (onNewChat != null)
          IconButton(
            onPressed: onNewChat,
            tooltip: 'New question',
            icon: const Icon(Icons.edit_square, size: 22),
          ),
        if (onShare != null)
          PopupMenuButton<String>(
            tooltip: 'Conversation options',
            onSelected: (_) => onShare!(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'share', child: Text('Share conversation')),
            ],
          ),
      ],
    );
  }
}

class InsightsEmptyConversation extends StatelessWidget {
  const InsightsEmptyConversation({
    super.key,
    required this.questions,
    required this.onQuestion,
    required this.hasReceipts,
  });
  final List<String> questions;
  final ValueChanged<String> onQuestion;
  final bool hasReceipts;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.auto_awesome_outlined,
              size: 24,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Ask about your spending',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hasReceipts
                ? 'Ask a question about your saved receipts. We’ll help you make sense of them.'
                : 'Add your first receipt from Home, then ask about your spending here.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: cs.onSurfaceVariant,
            ),
          ),
          if (hasReceipts && questions.isNotEmpty) ...[
            const SizedBox(height: 24),
            for (final question in questions.take(2))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OutlinedButton(
                  onPressed: () => onQuestion(question),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    side: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          question,
                          style: const TextStyle(fontSize: 13, height: 1.5),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.arrow_forward_rounded, size: 17),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class InsightsNotice extends StatelessWidget {
  const InsightsNotice({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.error.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 20, color: cs.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 13, height: 1.5, color: cs.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InsightsMessage extends StatelessWidget {
  const InsightsMessage({super.key, required this.message});
  final AiChatMessage message;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = message.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: user ? 0.88 : 1,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: user ? cs.primary : cs.surfaceContainerLow,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(user ? 20 : 5),
                bottomRight: Radius.circular(user ? 5 : 20),
              ),
              border: user
                  ? null
                  : Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.45),
                    ),
            ),
            child: user
                ? SelectableText(
                    message.content,
                    style: TextStyle(
                      color: cs.onPrimary,
                      fontSize: 14,
                      height: 1.55,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_outlined,
                            size: 15,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            'ReceiptNest',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      MarkdownBody(
                        data: message.content,
                        selectable: true,
                        styleSheet:
                            MarkdownStyleSheet.fromTheme(
                              Theme.of(context),
                            ).copyWith(
                              p: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 14,
                                height: 1.65,
                                color: cs.onSurface,
                              ),
                              listBullet: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 14,
                                height: 1.65,
                                color: cs.onSurface,
                              ),
                              blockSpacing: 14,
                              tableColumnWidth: const FlexColumnWidth(),
                              tableCellsPadding: const EdgeInsets.all(8),
                            ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class InsightsComposer extends StatelessWidget {
  const InsightsComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.busy,
    required this.compactHeight,
    this.singleLine = false,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final bool busy;
  final bool compactHeight;
  final bool singleLine;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('insights-composer'),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('insights-message-input'),
                  controller: controller,
                  focusNode: focusNode,
                  onTapOutside: (_) => focusNode.unfocus(),
                  minLines: 1,
                  maxLines: singleLine
                      ? 1
                      : compactHeight
                      ? 2
                      : 3,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: 'Ask about your spending…',
                    hintStyle: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 14,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: cs.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, child) => IconButton.filled(
                  key: const ValueKey('insights-send'),
                  tooltip: 'Send message',
                  onPressed: busy || value.text.trim().isEmpty ? null : onSend,
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  icon: const Icon(Icons.arrow_upward_rounded, size: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class InsightsHistoryPanel extends StatelessWidget {
  const InsightsHistoryPanel({
    super.key,
    required this.history,
    required this.activeChatId,
    required this.onOpen,
    required this.onNewChat,
    this.loading = false,
    this.error = false,
    required this.onRetry,
  });
  final List<AiChatHistoryItem> history;
  final String? activeChatId;
  final ValueChanged<String> onOpen;
  final VoidCallback onNewChat;
  final bool loading;
  final bool error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Conversations',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: onNewChat,
                tooltip: 'New question',
                icon: Icon(
                  Icons.add_comment_outlined,
                  color: cs.primary,
                  size: 21,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : history.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(22),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          error
                              ? 'Your conversations couldn’t load. Please try again when you’re connected.'
                              : 'Your conversations will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            height: 1.6,
                          ),
                        ),
                        if (error)
                          TextButton(
                            onPressed: onRetry,
                            child: const Text('Try again'),
                          ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: history.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final chat = history[index];
                    return Material(
                      color: chat.id == activeChatId
                          ? cs.primary.withValues(alpha: 0.09)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        leading: Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 19,
                          color: cs.primary,
                        ),
                        title: Text(
                          chat.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            MaterialLocalizations.of(
                              context,
                            ).formatShortDate(chat.updatedAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        onTap: () => onOpen(chat.id),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
