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
const _revenueCatOfferingId = String.fromEnvironment(
  'REVENUECAT_IOS_OFFERING_ID',
);

final revenueCatRepositoryProvider = Provider<RevenueCatRepository>((ref) {
  return RevenueCatRepository(db: ref.watch(firestoreProvider));
});

class RevenueCatException implements Exception {
  const RevenueCatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RevenueCatPurchaseOption {
  const RevenueCatPurchaseOption({required this.price, required this.package});

  final String price;
  final Package package;
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

  Future<RevenueCatPurchaseOption> fetchMonthlyOption(String userId) async {
    await _ensureConfigured(userId);
    final offerings = await Purchases.getOfferings();
    final offering = _selectOffering(offerings);
    final package = _selectMonthlyPackage(offering);
    if (package == null) {
      throw const RevenueCatException(
        'The App Store monthly subscription is not available yet.',
      );
    }
    return RevenueCatPurchaseOption(
      price: package.storeProduct.priceString,
      package: package,
    );
  }

  Future<CustomerInfo> purchaseMonthly({
    required String userId,
    required Package package,
  }) async {
    await _ensureConfigured(userId);
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      await syncActiveEntitlement(
        userId: userId,
        customerInfo: result.customerInfo,
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
  }) async {
    final entitlement = _activeEntitlement(customerInfo);
    if (entitlement == null) return;

    final expirationDate = _parseRevenueCatDate(entitlement.expirationDate);
    await _db.collection('users').doc(userId).set({
      'subscriptionPlan': 'pro',
      'subscriptionStatus': 'active',
      'subscriptionInterval': 'monthly',
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

  Offering? _selectOffering(Offerings offerings) {
    if (_revenueCatOfferingId.trim().isNotEmpty) {
      return offerings.getOffering(_revenueCatOfferingId.trim());
    }
    final allOfferings = offerings.all.values;
    return offerings.current ??
        (allOfferings.isEmpty ? null : allOfferings.first);
  }

  Package? _selectMonthlyPackage(Offering? offering) {
    if (offering == null) return null;
    if (_revenueCatMonthlyPackageId.trim().isNotEmpty) {
      return offering.getPackage(_revenueCatMonthlyPackageId.trim());
    }
    return offering.monthly ??
        offering.availablePackages.firstWhereOrNull(
          (package) => package.packageType == PackageType.monthly,
        );
  }

  EntitlementInfo? _activeEntitlement(CustomerInfo customerInfo) {
    return customerInfo.entitlements.active[_revenueCatProEntitlementId];
  }

  DateTime? _parseRevenueCatDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}
