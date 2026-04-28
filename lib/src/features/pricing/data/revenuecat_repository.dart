import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../auth/data/auth_repository.dart';

const _revenueCatIosApiKey = String.fromEnvironment('REVENUECAT_IOS_API_KEY');
const _revenueCatProEntitlementId = String.fromEnvironment(
  'REVENUECAT_PRO_ENTITLEMENT_ID',
  defaultValue: 'pro',
);
const _revenueCatMonthlyPackageId = String.fromEnvironment(
  'REVENUECAT_IOS_MONTHLY_PACKAGE_ID',
);
const _revenueCatAnnualPackageId = String.fromEnvironment(
  'REVENUECAT_IOS_ANNUAL_PACKAGE_ID',
);
const _revenueCatOfferingId = String.fromEnvironment(
  'REVENUECAT_IOS_OFFERING_ID',
);

final revenueCatRepositoryProvider = Provider<RevenueCatRepository>((ref) {
  return RevenueCatRepository(db: ref.watch(firestoreProvider));
});

enum BillingInterval { monthly, annual }

class RevenueCatException implements Exception {
  const RevenueCatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RevenueCatPurchaseOption {
  const RevenueCatPurchaseOption({
    required this.price,
    required this.package,
    required this.interval,
  });

  final String price;
  final Package package;
  final BillingInterval interval;
}

class RevenueCatPlanOptions {
  const RevenueCatPlanOptions({this.monthly, this.annual});

  final RevenueCatPurchaseOption? monthly;
  final RevenueCatPurchaseOption? annual;

  RevenueCatPurchaseOption? forInterval(BillingInterval interval) {
    return interval == BillingInterval.annual ? annual : monthly;
  }

  bool get hasAny => monthly != null || annual != null;
}

class RevenueCatRepository {
  RevenueCatRepository({required FirebaseFirestore db}) : _db = db;

  final FirebaseFirestore _db;
  bool _configured = false;
  String? _loggedInUserId;

  bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<RevenueCatPlanOptions> fetchPlanOptions(String userId) async {
    await _ensureConfigured(userId);
    final offerings = await Purchases.getOfferings();
    final offering = _selectOffering(offerings);
    if (offering == null) {
      throw const RevenueCatException(
        'No App Store subscription offering is configured yet.',
      );
    }
    final monthly = _buildOption(
      _selectMonthlyPackage(offering),
      BillingInterval.monthly,
    );
    final annual = _buildOption(
      _selectAnnualPackage(offering),
      BillingInterval.annual,
    );
    if (monthly == null && annual == null) {
      throw const RevenueCatException(
        'No App Store subscription packages are available yet.',
      );
    }
    return RevenueCatPlanOptions(monthly: monthly, annual: annual);
  }

  Future<CustomerInfo> purchasePackage({
    required String userId,
    required Package package,
    required BillingInterval interval,
  }) async {
    await _ensureConfigured(userId);
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      await syncActiveEntitlement(
        userId: userId,
        customerInfo: result.customerInfo,
        interval: interval,
      );
      return result.customerInfo;
    } on PlatformException catch (error) {
      final code = PurchasesErrorHelper.getErrorCode(error);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        throw const RevenueCatException('Purchase cancelled.');
      }
      throw const RevenueCatException(
        'Unable to complete the App Store purchase right now.',
      );
    }
  }

  Future<CustomerInfo> restorePurchases(String userId) async {
    await _ensureConfigured(userId);
    try {
      final customerInfo = await Purchases.restorePurchases();
      await syncActiveEntitlement(userId: userId, customerInfo: customerInfo);
      return customerInfo;
    } on PlatformException {
      throw const RevenueCatException(
        'Unable to restore App Store purchases right now.',
      );
    }
  }

  Future<CustomerInfo?> fetchCustomerInfo(String userId) async {
    await _ensureConfigured(userId);
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      await syncActiveEntitlement(userId: userId, customerInfo: customerInfo);
      return customerInfo;
    } on PlatformException {
      return null;
    }
  }

  Future<void> syncActiveEntitlement({
    required String userId,
    required CustomerInfo customerInfo,
    BillingInterval? interval,
  }) async {
    final entitlement = _activeEntitlement(customerInfo);
    if (entitlement == null) return;

    final expirationDate = _parseRevenueCatDate(entitlement.expirationDate);
    final resolvedInterval =
        interval ?? _intervalFromProductId(entitlement.productIdentifier);
    await _db.collection('users').doc(userId).set({
      'subscriptionPlan': 'pro',
      'subscriptionStatus': 'active',
      'subscriptionInterval': resolvedInterval == BillingInterval.annual
          ? 'annual'
          : 'monthly',
      'subscriptionSource': 'app_store',
      'subscriptionCurrentPeriodEnd': expirationDate == null
          ? FieldValue.delete()
          : Timestamp.fromDate(expirationDate),
      'subscriptionCancelAtPeriodEnd': !entitlement.willRenew,
      'revenueCatAppUserId': userId,
      'revenueCatEntitlementId': entitlement.identifier,
      'revenueCatProductIdentifier': entitlement.productIdentifier,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  bool hasActivePro(CustomerInfo? customerInfo) {
    if (customerInfo == null) return false;
    return _activeEntitlement(customerInfo) != null;
  }

  Future<void> _ensureConfigured(String userId) async {
    if (!isSupported) {
      throw const RevenueCatException(
        'App Store purchases are only available on iPhone.',
      );
    }
    if (_revenueCatIosApiKey.trim().isEmpty) {
      throw const RevenueCatException(
        'RevenueCat is missing REVENUECAT_IOS_API_KEY for this iOS build.',
      );
    }

    if (!_configured) {
      final configuration = PurchasesConfiguration(_revenueCatIosApiKey)
        ..appUserID = userId;
      await Purchases.configure(configuration);
      _configured = true;
      _loggedInUserId = userId;
      return;
    }

    if (_loggedInUserId != userId) {
      await Purchases.logIn(userId);
      _loggedInUserId = userId;
    }
  }

  RevenueCatPurchaseOption? _buildOption(
    Package? package,
    BillingInterval interval,
  ) {
    if (package == null) return null;
    return RevenueCatPurchaseOption(
      price: package.storeProduct.priceString,
      package: package,
      interval: interval,
    );
  }

  Offering? _selectOffering(Offerings offerings) {
    if (_revenueCatOfferingId.trim().isNotEmpty) {
      return offerings.getOffering(_revenueCatOfferingId.trim());
    }
    final allOfferings = offerings.all.values;
    return offerings.current ??
        (allOfferings.isEmpty ? null : allOfferings.first);
  }

  Package? _selectMonthlyPackage(Offering offering) {
    if (_revenueCatMonthlyPackageId.trim().isNotEmpty) {
      return offering.getPackage(_revenueCatMonthlyPackageId.trim());
    }
    if (offering.monthly != null) return offering.monthly;
    for (final package in offering.availablePackages) {
      if (package.packageType == PackageType.monthly) return package;
    }
    return null;
  }

  Package? _selectAnnualPackage(Offering offering) {
    if (_revenueCatAnnualPackageId.trim().isNotEmpty) {
      return offering.getPackage(_revenueCatAnnualPackageId.trim());
    }
    if (offering.annual != null) return offering.annual;
    for (final package in offering.availablePackages) {
      if (package.packageType == PackageType.annual) return package;
    }
    return null;
  }

  EntitlementInfo? _activeEntitlement(CustomerInfo customerInfo) {
    return customerInfo.entitlements.active[_revenueCatProEntitlementId];
  }

  BillingInterval _intervalFromProductId(String productId) {
    final lower = productId.toLowerCase();
    if (lower.contains('year') || lower.contains('annual')) {
      return BillingInterval.annual;
    }
    return BillingInterval.monthly;
  }

  DateTime? _parseRevenueCatDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}
