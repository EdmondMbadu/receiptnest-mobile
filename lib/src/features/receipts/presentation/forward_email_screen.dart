import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';
import '../data/receipt_email_forwarding.dart';
import '../data/receipt_repository.dart';
import '../models/receipt.dart';
import 'receipt_upload_outcome.dart';

class ForwardEmailScreen extends ConsumerWidget {
  const ForwardEmailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserIdProvider);
    return uid == null
        ? const Scaffold(body: SizedBox.shrink())
        : _ForwardEmailView(key: ValueKey(uid), userId: uid);
  }
}

class _ForwardEmailView extends ConsumerStatefulWidget {
  const _ForwardEmailView({super.key, required this.userId});
  final String userId;
  @override
  ConsumerState<_ForwardEmailView> createState() => _ForwardEmailViewState();
}

class _ForwardEmailViewState extends ConsumerState<_ForwardEmailView> {
  bool _copied = false;
  bool _copying = false;
  String? _copyError;
  Receipt? _received;
  bool _first = false;

  Future<void> _copy(String address) async {
    if (_copying || ref.read(currentUserIdProvider) != widget.userId) return;
    setState(() {
      _copying = true;
      _copyError = null;
    });
    try {
      await Clipboard.setData(ClipboardData(text: address));
      if (!mounted || ref.read(currentUserIdProvider) != widget.userId) return;
      ref.read(emailReceiptArrivalProvider.notifier).expectReceipt();
      setState(() => _copied = true);
    } catch (_) {
      if (!mounted || ref.read(currentUserIdProvider) != widget.userId) return;
      setState(
        () => _copyError =
            'Couldn’t copy the address. You can select it above, or try again.',
      );
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    ref.watch(emailReceiptArrivalProvider);
    ref.listen(emailReceiptArrivalProvider, (previous, next) {
      if (next == null ||
          next.id == previous?.id ||
          next.userId != widget.userId) {
        return;
      }
      // Keep the first arrival visible if several receipts arrive together.
      if (_received != null) return;
      setState(() {
        _received = next;
        _first =
            (ref.read(receiptsStreamProvider).valueOrNull?.length ?? 0) == 1;
      });
    });
    final address = ref.watch(receiptForwardingAddressProvider);
    void back() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/app/home');
      }
    }

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0D0D12) : Colors.white,
      appBar: AppBar(
        backgroundColor: dark ? const Color(0xFF0D0D12) : Colors.white,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: back,
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Forward a receipt',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            onPressed: () => context.go('/app/home'),
            tooltip: 'Back to Home',
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _received != null
                ? ReceiptUploadOutcome(
                    key: ValueKey(_received!.id),
                    userId: widget.userId,
                    receiptId: _received!.id,
                    seed: _received,
                    first: _first,
                    showCloseButton: false,
                    onAnother: () => setState(() => _received = null),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(
                              Icons.mail_outline_rounded,
                              color: cs.primary,
                              size: 30,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'A place for your\nemail receipts.',
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                fontSize: 30,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.7,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Send a receipt here. We’ll keep it with the rest.',
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.6,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'Your receipt address',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (address.isLoading && !address.hasValue)
                          const _AddressNotice(
                            message: 'Getting your address ready…',
                            loading: true,
                          )
                        else if (address.hasError ||
                            address.valueOrNull == null) ...[
                          const _AddressNotice(
                            message:
                                'We couldn’t get your address. Check your connection and try again.',
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => ref.invalidate(
                              receiptForwardingAddressProvider,
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Try again'),
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: dark
                                  ? const Color(0xFF16161F)
                                  : const Color(0xFFF6F7F8),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: cs.outlineVariant.withValues(alpha: 0.5),
                              ),
                            ),
                            child: SelectableText(
                              address.requireValue!,
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _copying
                                ? null
                                : () => _copy(address.requireValue!),
                            icon: Icon(
                              _copied
                                  ? Icons.check_rounded
                                  : Icons.copy_outlined,
                              size: 18,
                            ),
                            label: Text(
                              _copied ? 'Address copied' : 'Copy address',
                            ),
                          ),
                          if (_copyError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                _copyError!,
                                style: TextStyle(color: cs.error, height: 1.5),
                              ),
                            ),
                        ],
                        const SizedBox(height: 28),
                        const _ForwardStep(
                          number: '1',
                          text: 'Open a receipt in your mail app.',
                        ),
                        const _ForwardStep(
                          number: '2',
                          text: 'Tap Forward and paste this address.',
                        ),
                        const _ForwardStep(
                          number: '3',
                          text: 'Send it to ReceiptNest.',
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'You can return to Home. Your receipt will appear when it arrives.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.6,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: () => context.go('/app/home'),
                          icon: const Icon(Icons.home_outlined, size: 19),
                          label: const Text('Back to Home'),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _AddressNotice extends StatelessWidget {
  const _AddressNotice({required this.message, this.loading = false});
  final String message;
  final bool loading;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: 3, right: 12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ForwardStep extends StatelessWidget {
  const _ForwardStep({required this.number, required this.text});
  final String number;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 30,
          child: Text(
            number,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 14, height: 1.5)),
        ),
      ],
    ),
  );
}

/// A single quiet entry point, also available before the first receipt.
class ReceiptForwardingCard extends ConsumerWidget {
  const ReceiptForwardingCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final address = ref.watch(receiptForwardingAddressProvider).valueOrNull;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(Icons.mail_outline_rounded, color: cs.primary),
        title: const Text(
          'Forward an email',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          address ?? 'A place for your email receipts',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: cs.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: () => context.push('/app/forward-email'),
      ),
    );
  }
}
