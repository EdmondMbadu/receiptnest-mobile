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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF00C805).withValues(alpha: 0.18),
                  cs.surfaceContainerHighest.withValues(alpha: 0.55),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plan & Pricing',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'You are on the ${isPro ? 'Pro' : 'Free'} plan.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.75),
                  ),
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
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'monthly', label: Text('Monthly')),
              ButtonSegment(value: 'annual', label: Text('Annual')),
            ],
            selected: {_interval},
            onSelectionChanged: (value) {
              setState(() => _interval = value.first);
            },
          ),
          const SizedBox(height: 14),
          _PlanCard(
            title: 'Free',
            subtitle: 'Current plan',
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
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _processingPortal ? null : _openPortal,
            icon: const Icon(Icons.manage_accounts_outlined),
            label: Text(
              _processingPortal ? 'Opening portal...' : 'Manage billing',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!, style: TextStyle(color: cs.error)),
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: active ? 1 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: active
              ? accentColor.withValues(alpha: 0.55)
              : cs.outlineVariant,
          width: active ? 1.8 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                if (active)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: accentColor.withValues(alpha: 0.15),
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
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 10),
            RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: price,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                  TextSpan(
                    text: ' $cadence',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ...features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_rounded, size: 18, color: accentColor),
                    const SizedBox(width: 8),
                    Expanded(child: Text(feature)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: active
                      ? cs.surfaceContainerHighest
                      : accentColor,
                  foregroundColor: active ? cs.onSurface : Colors.white,
                ),
                child: Text(actionLabel),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
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
