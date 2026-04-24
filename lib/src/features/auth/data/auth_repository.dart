import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../models/user_profile.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);
final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);
final functionsProvider = Provider<FirebaseFunctions>(
  (ref) => FirebaseFunctions.instance,
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    auth: ref.watch(firebaseAuthProvider),
    db: ref.watch(firestoreProvider),
    functions: ref.watch(functionsProvider),
  );
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider)?.uid;
});

final currentUserProfileProvider = StreamProvider<UserProfile?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream.value(null);
  }

  final repo = ref.watch(authRepositoryProvider);
  return repo.userProfileStream(uid);
});

class AppAuthException implements Exception {
  const AppAuthException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class AuthRepository {
  AuthRepository({
    required FirebaseAuth auth,
    required FirebaseFirestore db,
    required FirebaseFunctions functions,
  }) : _auth = auth,
       _db = db,
       _functions = functions;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  NotificationSettings getDefaultNotificationSettings(UserProfile? profile) {
    return _normalizedNotificationSettings(profile?.notificationSettings);
  }

  Stream<UserProfile?> userProfileStream(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        final currentUser = _auth.currentUser;
        if (currentUser?.uid == uid) {
          _queueProfileRepair(currentUser!);
        }
        return null;
      }

      final data = snapshot.data() ?? const <String, dynamic>{};
      if (_userProfileNeedsRepair(data)) {
        final currentUser = _auth.currentUser;
        if (currentUser?.uid == uid) {
          _queueProfileRepair(currentUser!);
        }
      }
      return UserProfile.fromSnapshot(snapshot);
    });
  }

  Future<void> registerWithEmail({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    final trimmedFirstName = firstName.trim();
    final trimmedLastName = lastName.trim();
    final trimmedEmail = email.trim();
    final cred = await _auth.createUserWithEmailAndPassword(
      email: trimmedEmail,
      password: password,
    );
    final user = cred.user!;

    final displayName = '$trimmedFirstName $trimmedLastName'.trim();
    if (displayName.isNotEmpty) {
      await user.updateDisplayName(displayName);
    }

    await _upsertUserProfileDocument(
      user,
      firstName: trimmedFirstName,
      lastName: trimmedLastName,
      email: trimmedEmail,
      includeLastLoginAt: true,
    );

    await sendVerificationEmail();
  }

  Future<void> loginWithEmail(String email, String password) async {
    final trimmedEmail = email.trim();
    final cred = await _auth.signInWithEmailAndPassword(
      email: trimmedEmail,
      password: password,
    );

    if (cred.user != null) {
      await _upsertUserProfileDocument(
        cred.user!,
        email: trimmedEmail,
        includeLastLoginAt: true,
      );
    }

    if (!(cred.user?.emailVerified ?? false)) {
      await sendVerificationEmail();
      throw const AppAuthException(
        'auth/email-not-verified',
        'Please verify your email before signing in.',
      );
    }
  }

  Future<void> loginWithGoogle() async {
    final google = GoogleSignIn.instance;
    await google.initialize();
    final googleUser = await google.authenticate();

    final authentication = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: authentication.idToken,
    );

    final userCred = await _auth.signInWithCredential(credential);
    final user = userCred.user;
    if (user == null) return;

    await _upsertUserProfileDocument(user, includeLastLoginAt: true);
  }

  Future<void> loginWithApple() async {
    final rawNonce = _generateNonce();
    final hashedNonce = _sha256ofString(rawNonce);
    final AuthorizationCredentialAppleID appleCredential;
    try {
      appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw const AppAuthException(
          'auth/apple-cancelled',
          'Apple sign-in was cancelled.',
        );
      }
      if (error.code == AuthorizationErrorCode.unknown) {
        throw const AppAuthException(
          'auth/apple-not-configured',
          'Apple sign-in is not available for this build yet. Confirm the iOS App ID has Sign in with Apple enabled, then regenerate the provisioning profile and reinstall the app.',
        );
      }
      throw const AppAuthException(
        'auth/apple-authorization-failed',
        'Apple sign-in could not be completed. Please try again.',
      );
    } on SignInWithAppleNotSupportedException {
      throw const AppAuthException(
        'auth/apple-not-supported',
        'Apple sign-in is not supported on this device.',
      );
    }

    final identityToken = appleCredential.identityToken;
    if (identityToken == null || identityToken.isEmpty) {
      throw const AppAuthException(
        'auth/missing-apple-token',
        'Apple did not return a sign-in token. Please try again.',
      );
    }

    if (kDebugMode) {
      _debugLogAppleToken(identityToken, hashedNonce: hashedNonce);
    }

    final oauthCredential = OAuthProvider(
      'apple.com',
    ).credential(idToken: identityToken, rawNonce: rawNonce);
    final userCred = await _auth.signInWithCredential(oauthCredential);
    final user = userCred.user;
    if (user == null) return;

    final firstName = appleCredential.givenName?.trim();
    final lastName = appleCredential.familyName?.trim();
    final displayName = [
      firstName,
      lastName,
    ].where((part) => part != null && part.isNotEmpty).join(' ');
    if (displayName.isNotEmpty && (user.displayName ?? '').trim().isEmpty) {
      await user.updateDisplayName(displayName);
    }

    await _upsertUserProfileDocument(
      user,
      firstName: firstName,
      lastName: lastName,
      email: appleCredential.email,
      includeLastLoginAt: true,
    );
  }

  Future<void> sendVerificationEmail() async {
    final callable = _functions.httpsCallable('sendVerificationEmail');
    try {
      await callable.call(<String, dynamic>{});
    } catch (_) {
      await _auth.currentUser?.sendEmailVerification();
    }
  }

  Future<void> sendWelcomeEmailIfNeeded() async {
    final callable = _functions.httpsCallable('sendWelcomeEmail');
    try {
      await callable.call(<String, dynamic>{});
    } catch (_) {
      // no-op
    }
  }

  Future<void> sendPasswordReset(String email) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) {
      throw const AppAuthException(
        'auth/invalid-email',
        'Enter a valid email address.',
      );
    }

    final callable = _functions.httpsCallable('sendPasswordResetEmail');
    try {
      await callable.call(<String, dynamic>{'email': trimmedEmail});
    } on FirebaseFunctionsException catch (error) {
      throw AppAuthException(
        error.code,
        'Unable to send the reset email right now. Please try again in a moment.',
      );
    }
  }

  bool isCurrentUserPasswordAuth() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return false;
    return currentUser.providerData.any(
      (provider) => provider.providerId == 'password',
    );
  }

  Future<void> updateProfileInfo({
    required String firstName,
    required String lastName,
  }) async {
    final user = _requireCurrentUser();
    final displayName = '${firstName.trim()} ${lastName.trim()}'.trim();
    if (displayName.isNotEmpty &&
        displayName != (user.displayName ?? '').trim()) {
      await user.updateDisplayName(displayName);
    }
    await _upsertUserProfileDocument(
      user,
      firstName: firstName,
      lastName: lastName,
    );
  }

  Future<void> updateNotificationSettings(NotificationSettings settings) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const AppAuthException(
        'auth/no-current-user',
        'User not authenticated.',
      );
    }

    final normalized = _normalizedNotificationSettings(settings);
    await _db.collection('users').doc(uid).set({
      'notificationSettings': normalized.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (!isCurrentUserPasswordAuth()) {
      throw const AppAuthException(
        'auth/operation-not-allowed',
        'Password changes are only available for email/password accounts.',
      );
    }

    final trimmedCurrent = currentPassword.trim();
    final trimmedNext = newPassword.trim();
    if (trimmedCurrent.isEmpty) {
      throw const AppAuthException(
        'auth/missing-password',
        'Current password is required.',
      );
    }
    if (trimmedNext.length < 6) {
      throw const AppAuthException(
        'auth/weak-password',
        'New password must be at least 6 characters.',
      );
    }

    final currentUser = _requireCurrentUser();
    final email = currentUser.email;
    if (email == null || email.isEmpty) {
      throw const AppAuthException(
        'auth/invalid-user-token',
        'Current account is missing an email address.',
      );
    }

    final credential = EmailAuthProvider.credential(
      email: email,
      password: trimmedCurrent,
    );
    await currentUser.reauthenticateWithCredential(credential);
    await currentUser.updatePassword(trimmedNext);
  }

  Future<void> deleteAccount({String? currentPassword}) async {
    if (isCurrentUserPasswordAuth()) {
      final trimmedCurrent = currentPassword?.trim() ?? '';
      if (trimmedCurrent.isEmpty) {
        throw const AppAuthException(
          'auth/missing-password',
          'Current password is required to delete this account.',
        );
      }

      final currentUser = _requireCurrentUser();
      final email = currentUser.email;
      if (email == null || email.isEmpty) {
        throw const AppAuthException(
          'auth/invalid-user-token',
          'Current account is missing an email address.',
        );
      }

      final credential = EmailAuthProvider.credential(
        email: email,
        password: trimmedCurrent,
      );
      await currentUser.reauthenticateWithCredential(credential);
    }

    final callable = _functions.httpsCallable('deleteUserAccount');
    await callable.call(<String, dynamic>{});
    await logout();
  }

  Future<void> logout() => _auth.signOut();

  Future<void> _upsertUserProfileDocument(
    User user, {
    String? firstName,
    String? lastName,
    String? email,
    bool includeLastLoginAt = false,
  }) async {
    final userRef = _db.collection('users').doc(user.uid);
    final snapshot = await userRef.get();
    final data = snapshot.data() ?? const <String, dynamic>{};
    final splitName = _splitDisplayName(user.displayName);

    final resolvedFirstName = _pickPreferredValue(
      firstName,
      data['firstName'] as String?,
      splitName.$1,
    );
    final resolvedLastName = _pickPreferredValue(
      lastName,
      data['lastName'] as String?,
      splitName.$2,
    );
    final resolvedEmail = _pickPreferredValue(
      email,
      user.email,
      data['email'] as String?,
    );

    if (!snapshot.exists) {
      final createData = <String, dynamic>{
        'id': user.uid,
        'firstName': resolvedFirstName,
        'lastName': resolvedLastName,
        'email': resolvedEmail,
        'receiptCount': 0,
        'role': 'user',
        'notificationSettings': NotificationSettings.defaults.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (includeLastLoginAt) {
        createData['lastLoginAt'] = FieldValue.serverTimestamp();
      }
      await userRef.set(createData);
      return;
    }

    final updates = <String, dynamic>{};

    if (resolvedFirstName.isNotEmpty &&
        resolvedFirstName != (data['firstName'] as String? ?? '')) {
      updates['firstName'] = resolvedFirstName;
    }
    if (resolvedLastName.isNotEmpty &&
        resolvedLastName != (data['lastName'] as String? ?? '')) {
      updates['lastName'] = resolvedLastName;
    }
    if (resolvedEmail.isNotEmpty &&
        resolvedEmail != (data['email'] as String? ?? '')) {
      updates['email'] = resolvedEmail;
    }
    if (data['notificationSettings'] == null) {
      updates['notificationSettings'] = NotificationSettings.defaults.toMap();
    }
    if (includeLastLoginAt) {
      updates['lastLoginAt'] = FieldValue.serverTimestamp();
    }
    if (updates.isEmpty) return;

    updates['updatedAt'] = FieldValue.serverTimestamp();
    await userRef.set(updates, SetOptions(merge: true));
  }

  bool _userProfileNeedsRepair(Map<String, dynamic> data) {
    final email = (data['email'] as String?)?.trim() ?? '';
    final firstName = (data['firstName'] as String?)?.trim();
    final lastName = (data['lastName'] as String?)?.trim();
    return email.isEmpty ||
        firstName == null ||
        lastName == null ||
        data['notificationSettings'] == null;
  }

  void _queueProfileRepair(User user) {
    unawaited(_repairUserProfile(user));
  }

  Future<void> _repairUserProfile(User user) async {
    try {
      await _upsertUserProfileDocument(user);
    } catch (error, stackTrace) {
      debugPrint('Profile repair skipped for ${user.uid}: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  (String, String) _splitDisplayName(String? displayName) {
    final parts = (displayName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return ('', '');
    }

    final firstName = parts.first.trim();
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';
    return (firstName, lastName);
  }

  String _pickPreferredValue(
    String? primary,
    String? secondary,
    String? tertiary,
  ) {
    for (final candidate in [primary, secondary, tertiary]) {
      final value = candidate?.trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }

    return '';
  }

  NotificationSettings _normalizedNotificationSettings(
    NotificationSettings? settings,
  ) {
    final value = settings ?? NotificationSettings.defaults;
    return NotificationSettings(
      receiptProcessing: value.receiptProcessing,
      productUpdates: value.productUpdates,
      securityAlerts: value.securityAlerts,
      weeklySummaryEmails: value.weeklySummaryEmails,
      monthlySummaryEmails: value.monthlySummaryEmails,
      weeklySummaryPush: false,
      monthlySummaryPush: false,
    );
  }

  User _requireCurrentUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AppAuthException(
        'auth/no-current-user',
        'No signed-in user.',
      );
    }
    return user;
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  void _debugLogAppleToken(
    String identityToken, {
    required String hashedNonce,
  }) {
    try {
      final parts = identityToken.split('.');
      if (parts.length < 2) {
        debugPrint('[AppleSignIn] Token is not a valid JWT');
        return;
      }
      String segment = parts[1];
      switch (segment.length % 4) {
        case 2:
          segment += '==';
          break;
        case 3:
          segment += '=';
          break;
      }
      final normalized = segment.replaceAll('-', '+').replaceAll('_', '/');
      final payload = utf8.decode(base64.decode(normalized));
      final claims = jsonDecode(payload) as Map<String, dynamic>;
      debugPrint('[AppleSignIn] Token claims:');
      debugPrint('  iss (issuer): ${claims['iss']}');
      debugPrint('  aud (audience / bundle id): ${claims['aud']}');
      debugPrint('  sub: ${claims['sub']}');
      debugPrint('  email: ${claims['email']}');
      debugPrint('  nonce_supported: ${claims['nonce_supported']}');
      debugPrint('  nonce (hashed) in token: ${claims['nonce']}');
      debugPrint('  hashedNonce we sent:     $hashedNonce');
      debugPrint(
        '  nonce match: ${claims['nonce'] == hashedNonce}',
      );
      final exp = claims['exp'];
      if (exp is int) {
        final expires = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
        debugPrint('  exp: $expires (now: ${DateTime.now()})');
      }
    } catch (e) {
      debugPrint('[AppleSignIn] Failed to decode token: $e');
    }
  }
}
