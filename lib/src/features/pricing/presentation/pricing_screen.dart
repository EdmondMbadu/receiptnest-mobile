import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../core/config/public_app_config.dart';
import '../../../core/config/public_billing_config.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/models/user_profile.dart';
import '../data/revenuecat_repository.dart';

class PricingScreen extends ConsumerStatefulWidget {
  const PricingScreen({super.key});

  @override
  ConsumerState<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends ConsumerState<PricingScreen> {
  bool _isAnnual = true;
  bool _processingCheckout = false;
  bool _processingPortal = false;
  bool _loadingAppleBilling = false;
  bool _appleEntitlementActive = false;
  String? _error;
  String? _lastSyncedBillingIntervalKey;
  String? _lastLoadedAppleBillingUserId;
  RevenueCatPlanOptions? _applePlanOptions;

  bool get _usesAppleBilling {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool _shouldShowBillingToggle({
    required bool appleHasMonthly,
    required bool appleHasAnnual,
  }) {
    if (!_usesAppleBilling) return true;
    if (_applePlanOptions == null) return true;
    return appleHasMonthly && appleHasAnnual;
  }

  String _replaceFreePlanLimit(String value, int freePlanReceiptLimit) {
    return value.replaceAll('{freePlanReceiptLimit}', '$freePlanReceiptLimit');
  }

  List<_Feature> _buildFeatures(
    List<String> labels,
    List<IconData> icons, {
    required int freePlanReceiptLimit,
  }) {
    return labels
        .map((label) => _replaceFreePlanLimit(label, freePlanReceiptLimit))
        .toList(growable: false)
        .asMap()
        .entries
        .map(
          (entry) => _Feature(
            entry.value,
            entry.key < icons.length ? icons[entry.key] : Icons.check_rounded,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _startCheckout() async {
    setState(() {
      _processingCheckout = true;
      _error = null;
    });

    try {
      if (_usesAppleBilling) {
        final uid = ref.read(currentUserIdProvider);
        if (uid == null) {
          throw const RevenueCatException('Sign in before subscribing.');
        }
        final repo = ref.read(revenueCatRepositoryProvider);
        final plans = _applePlanOptions ?? await repo.fetchPlanOptions(uid);
        final desiredInterval = _isAnnual
            ? BillingInterval.annual
            : BillingInterval.monthly;
        final option =
            plans.forInterval(desiredInterval) ??
            plans.forInterval(
              desiredInterval == BillingInterval.annual
                  ? BillingInterval.monthly
                  : BillingInterval.annual,
            );
        if (option == null) {
          throw const RevenueCatException(
            'No App Store subscription is available right now.',
          );
        }
        final customerInfo = await repo.purchasePackage(
          userId: uid,
          package: option.package,
          interval: option.interval,
        );
        final hasPro = repo.hasActivePro(customerInfo);
        if (!hasPro) {
          throw const RevenueCatException(
            'The App Store purchase finished, but Pro access is still syncing.',
          );
        }
        setState(() {
          _applePlanOptions = plans;
          _appleEntitlementActive = true;
        });
        return;
      }

      final callable = ref
          .read(functionsProvider)
          .httpsCallable('createCheckoutSession');
      final response = await callable.call({
        'interval': _isAnnual ? 'annual' : 'monthly',
        'platform': 'mobile',
      });
      final result = response.data;
      final url = result is Map ? result['url']?.toString() : null;
      if (url == null || url.isEmpty) {
        throw Exception('Missing checkout URL from server.');
      }
      final launched = await launchUrlString(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('Unable to launch checkout URL.');
      }
    } catch (e) {
      setState(
        () => _error = _usesAppleBilling
            ? e.toString()
            : 'Unable to start checkout right now. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _processingCheckout = false);
      }
    }
  }

  Future<void> _openPortal() async {
    if (_usesAppleBilling) {
      setState(() {
        _processingPortal = true;
        _error = null;
      });
      try {
        final launched = await launchUrlString(
          'https://apps.apple.com/account/subscriptions',
          mode: LaunchMode.externalApplication,
        );
        if (!launched) {
          throw Exception('Unable to open App Store subscriptions.');
        }
      } catch (_) {
        setState(() => _error = 'Unable to open App Store subscriptions.');
      } finally {
        if (mounted) {
          setState(() => _processingPortal = false);
        }
      }
      return;
    }

    final profile = ref.read(currentUserProfileProvider).valueOrNull;
    if (!(profile?.hasBillingPortalAccess ?? false)) {
      setState(
        () => _error =
            'Billing portal becomes available after a billing profile is created.',
      );
      return;
    }

    setState(() {
      _processingPortal = true;
      _error = null;
    });

    try {
      final callable = ref
          .read(functionsProvider)
          .httpsCallable('createPortalSession');
      final response = await callable.call(<String, dynamic>{
        'platform': 'mobile',
      });
      final result = response.data;
      final url = result is Map ? result['url']?.toString() : null;
      if (url == null || url.isEmpty) {
        throw Exception('Missing billing portal URL from server.');
      }
      final launched = await launchUrlString(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('Unable to launch billing portal URL.');
      }
    } catch (e) {
      setState(() => _error = 'Unable to open billing portal right now.');
    } finally {
      if (mounted) {
        setState(() => _processingPortal = false);
      }
    }
  }

  Future<void> _restoreApplePurchases() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) {
      setState(() => _error = 'Sign in before restoring purchases.');
      return;
    }

    setState(() {
      _processingPortal = true;
      _error = null;
    });

    try {
      final repo = ref.read(revenueCatRepositoryProvider);
      final customerInfo = await repo.restorePurchases(uid);
      final hasPro = repo.hasActivePro(customerInfo);
      setState(() {
        _appleEntitlementActive = hasPro;
        _error = hasPro ? null : 'No active App Store subscription was found.';
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _processingPortal = false);
      }
    }
  }

  Future<void> _loadAppleBilling(String uid) async {
    if (_loadingAppleBilling || _lastLoadedAppleBillingUserId == uid) return;
    setState(() {
      _loadingAppleBilling = true;
      _lastLoadedAppleBillingUserId = uid;
    });

    try {
      final repo = ref.read(revenueCatRepositoryProvider);
      final plans = await repo.fetchPlanOptions(uid);
      final customerInfo = await repo.fetchCustomerInfo(uid);
      if (!mounted) return;
      setState(() {
        _applePlanOptions = plans;
        _appleEntitlementActive = repo.hasActivePro(customerInfo);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loadingAppleBilling = false);
      }
    }
  }

  void _syncBillingIntervalSelection(UserProfile? profile) {
    final paidInterval = profile?.subscriptionInterval?.toLowerCase();
    final nextKey = profile?.isPro == true
        ? 'pro:${paidInterval == 'annual' ? 'annual' : 'monthly'}'
        : 'free:annual';

    if (_lastSyncedBillingIntervalKey == nextKey) {
      return;
    }

    _lastSyncedBillingIntervalKey = nextKey;
    final nextIsAnnual = profile?.isPro == true
        ? paidInterval == 'annual'
        : true;

    if (_isAnnual == nextIsAnnual) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() => _isAnnual = nextIsAnnual);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final uid = ref.watch(currentUserIdProvider);
    final billingConfig = ref.watch(publicBillingConfigProvider).valueOrNull;
    final appConfig =
        ref.watch(publicAppConfigProvider).valueOrNull ??
        const PublicAppConfig();
    final pricingHeadline = _usesAppleBilling
        ? 'ReceiptNest Pro'
        : appConfig.pricingHeadline;
    final pricingSubheadline = _usesAppleBilling
        ? 'Pro access billed through your Apple ID'
        : appConfig.pricingSubheadline;
    final proPlanName = _usesAppleBilling
        ? defaultPricingProPlanName
        : appConfig.pricingProPlanName;
    final freePlanName = _usesAppleBilling
        ? defaultPricingFreePlanName
        : appConfig.pricingFreePlanName;
    final proTagline = _usesAppleBilling
        ? 'Unlimited receipts, deeper insights, and richer exports with an App Store subscription.'
        : appConfig.pricingProTagline;
    final freeTagline = _usesAppleBilling
        ? defaultPricingFreeTagline
        : appConfig.pricingFreeTagline;
    final proFeatures = _usesAppleBilling
        ? defaultPricingProFeatures
        : appConfig.pricingProFeatures;
    final freeFeatures = _usesAppleBilling
        ? defaultPricingFreeFeatures
        : appConfig.pricingFreeFeatures;
    final freePlanReceiptLimit =
        billingConfig?.freePlanReceiptLimit ?? defaultFreePlanReceiptLimit;

    final isPro = (profile?.isPro ?? false) || _appleEntitlementActive;
    final status = (profile?.subscriptionStatus ?? 'inactive').toLowerCase();
    final hasBillingPortalAccess =
        _usesAppleBilling || (profile?.hasBillingPortalAccess ?? false);
    final renewDate = profile?.subscriptionCurrentPeriodEnd;
    final cancelling = profile?.subscriptionCancelAtPeriodEnd == true;

    _syncBillingIntervalSelection(profile);
    if (_usesAppleBilling && uid != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadAppleBilling(uid));
      });
    }

    const accent = Color(0xFF00C805);
    final selectedAppleOption = _usesAppleBilling
        ? _applePlanOptions?.forInterval(
            _isAnnual ? BillingInterval.annual : BillingInterval.monthly,
          )
        : null;
    final appleHasAnnual = _applePlanOptions?.annual != null;
    final appleHasMonthly = _applePlanOptions?.monthly != null;
    final proPrice = _usesAppleBilling
        ? (selectedAppleOption?.price ??
              (_isAnnual
                  ? defaultPricingAnnualPrice
                  : defaultPricingMonthlyPrice))
        : (_isAnnual
              ? appConfig.pricingAnnualPrice
              : appConfig.pricingMonthlyPrice);
    final proCadence = _isAnnual ? '/year' : '/month';
    final trustLabel = _usesAppleBilling
        ? 'Billed by the App Store'
        : appConfig.pricingTrustLabel;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0D0D14)
          : const Color(0xFFF6F7F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Pricing'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 48),
        children: [
          // ── Hero section ──
          Center(
            child: Column(
              children: [
                // Glowing icon
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF00E508), Color(0xFF00A804)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.35),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.diamond_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  pricingHeadline,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  pricingSubheadline,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Billing toggle ──
                if (_shouldShowBillingToggle(
                  appleHasMonthly: appleHasMonthly,
                  appleHasAnnual: appleHasAnnual,
                ))
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TogglePill(
                          label: 'Monthly',
                          selected: !_isAnnual,
                          onTap: () => setState(() => _isAnnual = false),
                          isDark: isDark,
                        ),
                        _TogglePill(
                          label: 'Annual',
                          badge: appConfig.pricingAnnualSavingsBadge.isEmpty
                              ? null
                              : appConfig.pricingAnnualSavingsBadge,
                          selected: _isAnnual,
                          onTap: () => setState(() => _isAnnual = true),
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          if (profile?.hasManualProOverride == true) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: accent.withValues(alpha: isDark ? 0.08 : 0.06),
                border: Border.all(color: accent.withValues(alpha: 0.15)),
              ),
              child: Text(
                'This Pro plan was granted by an admin. If the override is removed later, the account returns to its normal billing state.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  color: cs.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Current plan status (Pro users) ──
          if (isPro) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: accent.withValues(alpha: isDark ? 0.08 : 0.06),
                border: Border.all(color: accent.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pro plan active',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        if (renewDate != null)
                          Text(
                            cancelling
                                ? 'Cancels ${DateFormat('MMM d, y').format(renewDate.toLocal())}'
                                : 'Renews ${DateFormat('MMM d, y').format(renewDate.toLocal())}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: cancelling
                                  ? Colors.orange.shade700
                                  : cs.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (hasBillingPortalAccess)
                    TextButton(
                      onPressed: !_processingPortal ? _openPortal : null,
                      child: _processingPortal
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Manage'),
                    )
                  else if (profile?.hasManualProOverride == true)
                    Text(
                      'Admin managed',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── Plan cards ──
          // Pro plan
          _PlanCard(
            planName: proPlanName,
            tagline: proTagline,
            price: proPrice,
            cadence: proCadence,
            isActive: isPro,
            isPrimary: true,
            isDark: isDark,
            featuresHeading: 'Everything in Free, plus:',
            features: _buildFeatures(proFeatures, const [
              Icons.all_inclusive_rounded,
              Icons.search_rounded,
              Icons.download_rounded,
              Icons.insights_rounded,
              Icons.support_agent_rounded,
              Icons.auto_awesome_rounded,
            ], freePlanReceiptLimit: freePlanReceiptLimit),
            buttonLabel: isPro
                ? 'Current plan'
                : (_processingCheckout
                      ? null
                      : (_usesAppleBilling
                            ? 'Subscribe with App Store'
                            : 'Upgrade to Pro')),
            isProcessing: _processingCheckout || _loadingAppleBilling,
            onButtonPressed:
                isPro || _processingCheckout || _loadingAppleBilling
                ? null
                : _startCheckout,
          ),
          const SizedBox(height: 16),

          // Free plan
          _PlanCard(
            planName: freePlanName,
            tagline: freeTagline,
            price: '\$0',
            cadence: 'forever',
            isActive: !isPro,
            isPrimary: false,
            isDark: isDark,
            features: _buildFeatures(freeFeatures, const [
              Icons.receipt_long_rounded,
              Icons.label_rounded,
              Icons.upload_file_rounded,
              Icons.person_rounded,
            ], freePlanReceiptLimit: freePlanReceiptLimit),
            buttonLabel: !isPro ? 'Current plan' : null,
            onButtonPressed: null,
          ),
          const SizedBox(height: 24),

          // ── Manage billing link ──
          if (!isPro && status != 'inactive' && hasBillingPortalAccess)
            Center(
              child: TextButton.icon(
                onPressed: _processingPortal ? null : _openPortal,
                icon: _processingPortal
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.receipt_long_outlined,
                        size: 18,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                label: Text(
                  'Manage billing',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          if (_usesAppleBilling && !isPro)
            Center(
              child: TextButton.icon(
                onPressed: _processingPortal ? null : _restoreApplePurchases,
                icon: _processingPortal
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.restore_rounded,
                        size: 18,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                label: Text(
                  'Restore App Store purchase',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

          // ── Error ──
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.error.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, size: 18, color: cs.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: cs.error,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Bottom trust strip ──
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: cs.onSurface.withValues(alpha: 0.25),
              ),
              const SizedBox(width: 6),
              Text(
                trustLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface.withValues(alpha: 0.25),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Feature model ──

class _Feature {
  const _Feature(this.label, this.icon);
  final String label;
  final IconData icon;
}

// ── Billing toggle pill ──

class _TogglePill extends StatelessWidget {
  const _TogglePill({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.isDark,
    this.badge,
  });

  final String label;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? Colors.white.withValues(alpha: 0.12) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? cs.onSurface
                    : cs.onSurface.withValues(alpha: 0.45),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C805).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF00C805),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Plan card ──

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.planName,
    required this.tagline,
    required this.price,
    required this.cadence,
    required this.isActive,
    required this.isPrimary,
    required this.isDark,
    required this.features,
    this.featuresHeading,
    this.buttonLabel,
    this.onButtonPressed,
    this.isProcessing = false,
  });

  final String planName;
  final String tagline;
  final String price;
  final String cadence;
  final bool isActive;
  final bool isPrimary;
  final bool isDark;
  final List<_Feature> features;
  final String? featuresHeading;
  final String? buttonLabel;
  final VoidCallback? onButtonPressed;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const accent = Color(0xFF00C805);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: isPrimary
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xFF0F2010), const Color(0xFF0D0D14)]
                    : [const Color(0xFFF0FDF0), Colors.white],
              )
            : null,
        color: isPrimary
            ? null
            : (isDark ? const Color(0xFF151520) : Colors.white),
        border: Border.all(
          color: isPrimary
              ? accent.withValues(alpha: isDark ? 0.3 : 0.25)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.grey.shade200),
          width: isPrimary ? 1.5 : 1,
        ),
        boxShadow: isPrimary
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: isDark ? 0.08 : 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      planName,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: accent.withValues(alpha: 0.12),
                        ),
                        child: const Text(
                          'Active',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ),
                    if (isPrimary && !isActive) ...[
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: accent.withValues(alpha: 0.12),
                        ),
                        child: const Text(
                          'Popular',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  tagline,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w400,
                    color: cs.onSurface.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 18),

                // Price
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      price,
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.5,
                        height: 1,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      cadence,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Divider ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              height: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.grey.shade100,
            ),
          ),
          const SizedBox(height: 18),

          // ── Features ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (featuresHeading != null) ...[
                  Text(
                    featuresHeading!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                ...features.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isPrimary
                                ? accent.withValues(alpha: isDark ? 0.15 : 0.08)
                                : cs.onSurface.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            f.icon,
                            size: 16,
                            color: isPrimary
                                ? accent
                                : cs.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            f.label,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              color: cs.onSurface.withValues(alpha: 0.8),
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // ── Action button ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: isPrimary && !isActive
                  ? FilledButton(
                      onPressed: onButtonPressed,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      child: isProcessing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(buttonLabel ?? ''),
                    )
                  : OutlinedButton(
                      onPressed: onButtonPressed,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.onSurface.withValues(alpha: 0.5),
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.grey.shade200,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(buttonLabel ?? 'Current plan'),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
