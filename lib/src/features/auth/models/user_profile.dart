import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_utils.dart';

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
    this.telegramChatId,
    this.receiptForwardingAddress,
    this.receiptForwardingFallbackAddresses = const [],
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
  final int? telegramChatId;
  final String? receiptForwardingAddress;
  final List<String> receiptForwardingFallbackAddresses;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isEmpty ? email : full;
  }

  bool get isAdmin => role == 'admin';
  bool get isPro => subscriptionPlan == 'pro';

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
      subscriptionCurrentPeriodEnd: asDateTime(data['subscriptionCurrentPeriodEnd']),
      subscriptionCancelAtPeriodEnd: data['subscriptionCancelAtPeriodEnd'] as bool?,
      telegramChatId: data['telegramChatId'] as int?,
      receiptForwardingAddress: data['receiptForwardingAddress'] as String?,
      receiptForwardingFallbackAddresses:
          (data['receiptForwardingFallbackAddresses'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(),
      createdAt: asDateTime(data['createdAt']),
      updatedAt: asDateTime(data['updatedAt']),
    );
  }
}
