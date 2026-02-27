import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../auth/data/auth_repository.dart';

class PricingScreen extends ConsumerStatefulWidget {
  const PricingScreen({super.key});

  @override
  ConsumerState<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends ConsumerState<PricingScreen> {
  String _interval = 'monthly';
  bool _processingCheckout = false;
  bool _processingPortal = false;
  String? _error;

  Future<void> _startCheckout() async {
    setState(() {
      _processingCheckout = true;
      _error = null;
    });

    try {
      final callable = ref
          .read(functionsProvider)
          .httpsCallable('createCheckoutSession');
      final response = await callable.call({'interval': _interval});
      final result = response.data;
      final url = result is Map ? result['url']?.toString() : null;
      if (url == null || url.isEmpty) {
        throw Exception('Missing checkout URL from server.');
      }
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      setState(
        () => _error = 'Unable to start checkout right now. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _processingCheckout = false);
      }
    }
  }

  Future<void> _openPortal() async {
    setState(() {
      _processingPortal = true;
      _error = null;
    });

    try {
      final callable = ref
          .read(functionsProvider)
          .httpsCallable('createPortalSession');
      final response = await callable.call(<String, dynamic>{});
      final result = response.data;
      final url = result is Map ? result['url']?.toString() : null;
      if (url == null || url.isEmpty) {
        throw Exception('Missing billing portal URL from server.');
      }
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      setState(() => _error = 'Unable to open billing portal right now.');
    } finally {
      if (mounted) {
        setState(() => _processingPortal = false);
      }
    }
  }

  String _renewalLabel(DateTime? periodEnd) {
    if (periodEnd == null) return '';
    return DateFormat('MMM d, y').format(periodEnd.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;

    final plan = (profile?.subscriptionPlan ?? 'free').toLowerCase();
    final status = (profile?.subscriptionStatus ?? 'inactive').toLowerCase();
    final isPro = plan == 'pro';
    final renewalLabel = _renewalLabel(profile?.subscriptionCurrentPeriodEnd);
    final monthlyPrice = '\$9';
    final annualPrice = '\$100';

    return Scaffold(
      appBar: AppBar(title: const Text('Pricing')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── Current plan banner ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF00C805).withValues(alpha: isDark ? 0.12 : 0.10),
                  isDark
                      ? const Color(0xFF16161F)
                      : cs.surface,
                ],
              ),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.grey.shade200,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C805).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isPro ? Icons.diamond_rounded : Icons.diamond_outlined,
                        color: const Color(0xFF00C805),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Plan & Pricing',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'You are on the ${isPro ? 'Pro' : 'Free'} plan.',
                            style: TextStyle(
                              fontSize: 14,
                              color: cs.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatusChip(
                      label: 'Status: $status',
                      color: isPro ? const Color(0xFF00C805) : cs.outline,
                    ),
                    if (renewalLabel.isNotEmpty)
                      _StatusChip(
                        label: 'Renews: $renewalLabel',
                        color: cs.secondary,
                      ),
                    if (profile?.subscriptionCancelAtPeriodEnd == true)
                      _StatusChip(
                        label: 'Cancels at period end',
                        color: Colors.orange,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Interval toggle ──
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'monthly', label: Text('Monthly')),
              ButtonSegment(value: 'annual', label: Text('Annual')),
            ],
            selected: {_interval},
            onSelectionChanged: (value) {
              setState(() => _interval = value.first);
            },
            style: SegmentedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Free plan ──
          _PlanCard(
            title: 'Free',
            subtitle: 'Get started',
            price: '\$0',
            cadence: '/month',
            active: !isPro,
            accentColor: cs.outline,
            features: const [
              'Up to 200 receipts total',
              'Smart auto-tagging and summaries',
              'Email and PDF uploads',
              'Single user workspace',
            ],
            actionLabel: !isPro
                ? 'Active plan'
                : 'Downgrade from billing portal',
            onAction: isPro ? _openPortal : null,
          ),
          const SizedBox(height: 12),

          // ── Pro plan ──
          _PlanCard(
            title: 'Pro',
            subtitle: 'Best value',
            price: _interval == 'annual' ? annualPrice : monthlyPrice,
            cadence: _interval == 'annual' ? '/year' : '/month',
            active: isPro,
            accentColor: const Color(0xFF00C805),
            features: const [
              'Unlimited receipts',
              'Advanced search and filters',
              'CSV and PDF exports',
              'Priority support and early access',
            ],
            actionLabel: isPro
                ? 'You are on Pro'
                : (_processingCheckout ? 'Redirecting...' : 'Switch to Pro'),
            onAction: isPro || _processingCheckout ? null : _startCheckout,
            isProcessing: _processingCheckout,
          ),
          const SizedBox(height: 16),

          // ── Manage billing ──
          OutlinedButton.icon(
            onPressed: _processingPortal ? null : _openPortal,
            icon: _processingPortal
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                : const Icon(Icons.manage_accounts_outlined, size: 20),
            label: Text(
              _processingPortal ? 'Opening portal...' : 'Manage billing',
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, size: 18, color: cs.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: cs.error, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.cadence,
    required this.active,
    required this.accentColor,
    required this.features,
    required this.actionLabel,
    required this.onAction,
    this.isProcessing = false,
  });

  final String title;
  final String subtitle;
  final String price;
  final String cadence;
  final bool active;
  final Color accentColor;
  final List<String> features;
  final String actionLabel;
  final VoidCallback? onAction;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? accentColor.withValues(alpha: 0.50)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.grey.shade200),
          width: active ? 1.5 : 1,
        ),
        color: isDark ? const Color(0xFF16161F) : Colors.white,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                if (active)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: accentColor.withValues(alpha: 0.12),
                    ),
                    child: Text(
                      'Active',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                  ),
                const Spacer(),
                if (!active && title == 'Pro')
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: accentColor.withValues(alpha: 0.12),
                    ),
                    child: Text(
                      'Recommended',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  price,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                ),
                const SizedBox(width: 2),
                Text(
                  cadence,
                  style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 12,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        feature,
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: active
                      ? cs.surfaceContainerHighest
                      : accentColor,
                  foregroundColor: active ? cs.onSurface : Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
