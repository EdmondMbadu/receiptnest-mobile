import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_utils.dart';

class NotificationSettings {
  const NotificationSettings({
    required this.receiptProcessing,
    required this.productUpdates,
    required this.securityAlerts,
    required this.weeklySummaryEmails,
    required this.monthlySummaryEmails,
    required this.weeklySummaryPush,
    required this.monthlySummaryPush,
  });

  final bool receiptProcessing;
  final bool productUpdates;
  final bool securityAlerts;
  final bool weeklySummaryEmails;
  final bool monthlySummaryEmails;
  final bool weeklySummaryPush;
  final bool monthlySummaryPush;

  static const defaults = NotificationSettings(
    receiptProcessing: true,
    productUpdates: false,
    securityAlerts: true,
    weeklySummaryEmails: true,
    monthlySummaryEmails: true,
    weeklySummaryPush: false,
    monthlySummaryPush: false,
  );

  NotificationSettings copyWith({
    bool? receiptProcessing,
    bool? productUpdates,
    bool? securityAlerts,
    bool? weeklySummaryEmails,
    bool? monthlySummaryEmails,
    bool? weeklySummaryPush,
    bool? monthlySummaryPush,
  }) {
    return NotificationSettings(
      receiptProcessing: receiptProcessing ?? this.receiptProcessing,
      productUpdates: productUpdates ?? this.productUpdates,
      securityAlerts: securityAlerts ?? this.securityAlerts,
      weeklySummaryEmails: weeklySummaryEmails ?? this.weeklySummaryEmails,
      monthlySummaryEmails: monthlySummaryEmails ?? this.monthlySummaryEmails,
      weeklySummaryPush: weeklySummaryPush ?? this.weeklySummaryPush,
      monthlySummaryPush: monthlySummaryPush ?? this.monthlySummaryPush,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'receiptProcessing': receiptProcessing,
      'productUpdates': productUpdates,
      'securityAlerts': securityAlerts,
      'weeklySummaryEmails': weeklySummaryEmails,
      'monthlySummaryEmails': monthlySummaryEmails,
      'weeklySummaryPush': weeklySummaryPush,
      'monthlySummaryPush': monthlySummaryPush,
    };
  }

  static NotificationSettings fromMap(dynamic input) {
    if (input is! Map<String, dynamic>) {
      return defaults;
    }
    final weeklySummaryEmails =
        input['weeklySummaryEmails'] as bool? ?? defaults.weeklySummaryEmails;
    final monthlySummaryEmails =
        input['monthlySummaryEmails'] as bool? ?? defaults.monthlySummaryEmails;
    return NotificationSettings(
      receiptProcessing:
          input['receiptProcessing'] as bool? ?? defaults.receiptProcessing,
      productUpdates:
          input['productUpdates'] as bool? ?? defaults.productUpdates,
      securityAlerts:
          input['securityAlerts'] as bool? ?? defaults.securityAlerts,
      weeklySummaryEmails: weeklySummaryEmails,
      monthlySummaryEmails: monthlySummaryEmails,
      weeklySummaryPush: input['weeklySummaryPush'] as bool? ?? false,
      monthlySummaryPush: input['monthlySummaryPush'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is NotificationSettings &&
            receiptProcessing == other.receiptProcessing &&
            productUpdates == other.productUpdates &&
            securityAlerts == other.securityAlerts &&
            weeklySummaryEmails == other.weeklySummaryEmails &&
            monthlySummaryEmails == other.monthlySummaryEmails &&
            weeklySummaryPush == other.weeklySummaryPush &&
            monthlySummaryPush == other.monthlySummaryPush;
  }

  @override
  int get hashCode => Object.hash(
    receiptProcessing,
    productUpdates,
    securityAlerts,
    weeklySummaryEmails,
    monthlySummaryEmails,
    weeklySummaryPush,
    monthlySummaryPush,
  );
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.role = 'user',
    this.subscriptionPlan = 'free',
    this.subscriptionStatus,
    this.subscriptionInterval,
    this.subscriptionCurrentPeriodEnd,
    this.subscriptionCancelAtPeriodEnd,
    this.adminSubscriptionPlanOverride,
    this.stripeCustomerId,
    this.telegramChatId,
    this.receiptForwardingAddress,
    this.receiptForwardingFallbackAddresses = const [],
    this.notificationSettings = NotificationSettings.defaults,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String role;
  final String subscriptionPlan;
  final String? subscriptionStatus;
  final String? subscriptionInterval;
  final DateTime? subscriptionCurrentPeriodEnd;
  final bool? subscriptionCancelAtPeriodEnd;
  final String? adminSubscriptionPlanOverride;
  final String? stripeCustomerId;
  final int? telegramChatId;
  final String? receiptForwardingAddress;
  final List<String> receiptForwardingFallbackAddresses;
  final NotificationSettings notificationSettings;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isEmpty ? email : full;
  }

  bool get isAdmin => role == 'admin';
  bool get hasManualProOverride => adminSubscriptionPlanOverride == 'pro';
  bool get isPro => hasManualProOverride || subscriptionPlan == 'pro';
  bool get hasBillingPortalAccess =>
      (stripeCustomerId ?? '').trim().isNotEmpty;

  static UserProfile fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return UserProfile(
      id: doc.id,
      firstName: (data['firstName'] as String?) ?? '',
      lastName: (data['lastName'] as String?) ?? '',
      email: (data['email'] as String?) ?? '',
      role: (data['role'] as String?) ?? 'user',
      subscriptionPlan: (data['subscriptionPlan'] as String?) ?? 'free',
      subscriptionStatus: data['subscriptionStatus'] as String?,
      subscriptionInterval: data['subscriptionInterval'] as String?,
      subscriptionCurrentPeriodEnd: asDateTime(
        data['subscriptionCurrentPeriodEnd'],
      ),
      subscriptionCancelAtPeriodEnd:
          data['subscriptionCancelAtPeriodEnd'] as bool?,
      adminSubscriptionPlanOverride:
          data['adminSubscriptionPlanOverride'] as String?,
      stripeCustomerId: data['stripeCustomerId'] as String?,
      telegramChatId: data['telegramChatId'] as int?,
      receiptForwardingAddress: data['receiptForwardingAddress'] as String?,
      receiptForwardingFallbackAddresses:
          (data['receiptForwardingFallbackAddresses'] as List<dynamic>? ??
                  const [])
              .whereType<String>()
              .toList(),
      notificationSettings: NotificationSettings.fromMap(
        data['notificationSettings'],
      ),
      createdAt: asDateTime(data['createdAt']),
      updatedAt: asDateTime(data['updatedAt']),
    );
  }
}
