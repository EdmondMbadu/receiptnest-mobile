import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
          unawaited(_upsertUserProfileDocument(currentUser!));
        }
        return null;
      }

      final data = snapshot.data() ?? const <String, dynamic>{};
      if (_userProfileNeedsRepair(data)) {
        final currentUser = _auth.currentUser;
        if (currentUser?.uid == uid) {
          unawaited(_upsertUserProfileDocument(currentUser!));
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
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    await _upsertUserProfileDocument(
      cred.user!,
      firstName: firstName,
      lastName: lastName,
      email: email,
    );

    await sendVerificationEmail();
  }

  Future<void> loginWithEmail(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    if (cred.user != null) {
      await _upsertUserProfileDocument(cred.user!, email: email);
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

    await _upsertUserProfileDocument(user);
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
    if (email.trim().isEmpty) {
      throw const AppAuthException(
        'auth/invalid-email',
        'Enter a valid email address.',
      );
    }
    await _auth.sendPasswordResetEmail(email: email.trim());
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

    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (resolvedFirstName.isNotEmpty) {
      updates['firstName'] = resolvedFirstName;
    }
    if (resolvedLastName.isNotEmpty) {
      updates['lastName'] = resolvedLastName;
    }
    if (resolvedEmail.isNotEmpty) {
      updates['email'] = resolvedEmail;
    }
    if ((data['role'] as String?)?.trim().isNotEmpty != true) {
      updates['role'] = 'user';
    }
    if ((data['subscriptionPlan'] as String?)?.trim().isNotEmpty != true) {
      updates['subscriptionPlan'] = 'free';
    }
    if (data['notificationSettings'] == null) {
      updates['notificationSettings'] = NotificationSettings.defaults.toMap();
    }
    if (data['createdAt'] == null) {
      updates['createdAt'] = FieldValue.serverTimestamp();
    }

    await userRef.set(updates, SetOptions(merge: true));
  }

  bool _userProfileNeedsRepair(Map<String, dynamic> data) {
    final email = (data['email'] as String?)?.trim() ?? '';
    final role = (data['role'] as String?)?.trim() ?? '';
    final subscriptionPlan =
        (data['subscriptionPlan'] as String?)?.trim() ?? '';
    return email.isEmpty ||
        role.isEmpty ||
        subscriptionPlan.isEmpty ||
        data['notificationSettings'] == null ||
        data['createdAt'] == null;
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
}
