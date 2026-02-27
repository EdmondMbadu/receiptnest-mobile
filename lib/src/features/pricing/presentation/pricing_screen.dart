import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      final callable = ref.read(functionsProvider).httpsCallable('createCheckoutSession');
      final response = await callable.call({'interval': _interval});
      final result = response.data;
      final url = result is Map ? result['url']?.toString() : null;
      if (url == null || url.isEmpty) {
        throw Exception('Missing checkout URL from server.');
      }
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      setState(() => _error = e.toString());
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
      final callable = ref.read(functionsProvider).httpsCallable('createPortalSession');
      final response = await callable.call(<String, dynamic>{});
      final result = response.data;
      final url = result is Map ? result['url']?.toString() : null;
      if (url == null || url.isEmpty) {
        throw Exception('Missing billing portal URL from server.');
      }
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _processingPortal = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Pricing')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current plan: ${profile?.subscriptionPlan ?? 'free'}',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('Status: ${profile?.subscriptionStatus ?? 'inactive'}'),
                  if (profile?.subscriptionCurrentPeriodEnd != null)
                    Text('Renews: ${profile!.subscriptionCurrentPeriodEnd!.toLocal()}'),
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _processingCheckout ? null : _startCheckout,
                    icon: const Icon(Icons.upgrade_outlined),
                    label: Text(_processingCheckout ? 'Starting checkout...' : 'Upgrade to Pro'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _processingPortal ? null : _openPortal,
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: Text(_processingPortal ? 'Opening portal...' : 'Manage billing'),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
        ],
      ),
    );
  }
}
