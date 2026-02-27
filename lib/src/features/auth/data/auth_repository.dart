import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user_profile.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);
final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);
final functionsProvider = Provider<FirebaseFunctions>((ref) => FirebaseFunctions.instance);

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
  })  : _auth = auth,
        _db = db,
        _functions = functions;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Stream<UserProfile?> userProfileStream(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
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

    await _db.collection('users').doc(cred.user!.uid).set({
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'email': email.trim(),
      'role': 'user',
      'subscriptionPlan': 'free',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await sendVerificationEmail();
    await _auth.signOut();
  }

  Future<void> loginWithEmail(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    if (!(cred.user?.emailVerified ?? false)) {
      await sendVerificationEmail();
      await _auth.signOut();
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

    final userRef = _db.collection('users').doc(user.uid);
    final snap = await userRef.get();
    if (!snap.exists) {
      final splitName = (user.displayName ?? '').trim().split(' ');
      final firstName = splitName.isNotEmpty ? splitName.first : '';
      final lastName = splitName.length > 1 ? splitName.sublist(1).join(' ') : '';

      await userRef.set({
        'firstName': firstName,
        'lastName': lastName,
        'email': user.email ?? '',
        'role': 'user',
        'subscriptionPlan': 'free',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
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
      throw const AppAuthException('auth/invalid-email', 'Enter a valid email address.');
    }
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> logout() => _auth.signOut();
}
