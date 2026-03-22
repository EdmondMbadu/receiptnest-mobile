import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/models/user_profile.dart' as profile_models;

final firebaseMessagingProvider = Provider<FirebaseMessaging>(
  (ref) => FirebaseMessaging.instance,
);

final pushNotificationRepositoryProvider = Provider<PushNotificationRepository>(
  (ref) {
    return PushNotificationRepository(
      db: ref.watch(firestoreProvider),
      messaging: ref.watch(firebaseMessagingProvider),
    );
  },
);

const _deviceInfoChannel = MethodChannel('com.receiptnest.mobile/device');
const _storedTokenKey = 'push_notification.current_token';
const _storedUserKey = 'push_notification.current_user';
const _defaultTimeZone = 'America/Los_Angeles';

class PushNotificationRepository {
  PushNotificationRepository({
    required FirebaseFirestore db,
    required FirebaseMessaging messaging,
  }) : _db = db,
       _messaging = messaging;

  final FirebaseFirestore _db;
  final FirebaseMessaging _messaging;

  Stream<String> get tokenRefreshStream => _supportsPushNotifications
      ? _messaging.onTokenRefresh
      : const Stream.empty();

  Future<void> syncForUser({
    required String userId,
    required profile_models.NotificationSettings settings,
  }) async {
    if (!_supportsPushNotifications) {
      return;
    }

    final userRef = _db.collection('users').doc(userId);
    final timeZone = await _getTimeZone();

    if (!_shouldRegisterForSummaryPush(settings)) {
      await _removeStoredTokenFromUser(userId);
      await userRef.set({
        'notificationTimeZone': timeZone,
        'notificationPermissionStatus': 'disabled',
        'notificationTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final permission = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: true,
    );
    final authorizationStatus = permission.authorizationStatus.name;

    if (permission.authorizationStatus == AuthorizationStatus.denied ||
        permission.authorizationStatus == AuthorizationStatus.notDetermined) {
      await _removeStoredTokenFromUser(userId);
      await userRef.set({
        'notificationTimeZone': timeZone,
        'notificationPermissionStatus': authorizationStatus,
        'notificationTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) {
      await userRef.set({
        'notificationTimeZone': timeZone,
        'notificationPermissionStatus': authorizationStatus,
        'notificationTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final previousToken = prefs.getString(_storedTokenKey);
    final previousUserId = prefs.getString(_storedUserKey);

    if (previousToken != null && previousToken.isNotEmpty) {
      final tokenChanged = previousToken != token;
      final userChanged =
          previousUserId != null &&
          previousUserId.isNotEmpty &&
          previousUserId != userId;
      if (tokenChanged || userChanged) {
        final previousRef = _db
            .collection('users')
            .doc(
              (previousUserId ?? userId).trim().isEmpty
                  ? userId
                  : previousUserId,
            );
        await previousRef.set({
          'notificationTokens': FieldValue.arrayRemove([previousToken]),
          'notificationTokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    await userRef.set({
      'notificationTokens': FieldValue.arrayUnion([token]),
      'notificationTimeZone': timeZone,
      'notificationPermissionStatus': authorizationStatus,
      'notificationTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await prefs.setString(_storedTokenKey, token);
    await prefs.setString(_storedUserKey, userId);
  }

  Future<void> unlinkCurrentDevice(String userId) async {
    if (!_supportsPushNotifications) {
      return;
    }

    await _removeStoredTokenFromUser(userId);
  }

  Future<void> _removeStoredTokenFromUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final storedUserId = prefs.getString(_storedUserKey);
    final storedToken = prefs.getString(_storedTokenKey);
    final token = storedToken ?? await _messaging.getToken();

    if (token != null && token.isNotEmpty) {
      await _db.collection('users').doc(userId).set({
        'notificationTokens': FieldValue.arrayRemove([token]),
        'notificationTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (storedUserId == userId) {
      await prefs.remove(_storedUserKey);
      await prefs.remove(_storedTokenKey);
    }
  }

  Future<String> _getTimeZone() async {
    try {
      final value = await _deviceInfoChannel.invokeMethod<String>(
        'getTimeZone',
      );
      final normalized = value?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        return normalized;
      }
    } catch (_) {
      // Fall back to the server default if the platform channel is unavailable.
    }
    return _defaultTimeZone;
  }

  bool _shouldRegisterForSummaryPush(
    profile_models.NotificationSettings settings,
  ) {
    return settings.weeklySummaryPush || settings.monthlySummaryPush;
  }

  bool get _supportsPushNotifications {
    if (kIsWeb) {
      return false;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return true;
      default:
        return false;
    }
  }
}
