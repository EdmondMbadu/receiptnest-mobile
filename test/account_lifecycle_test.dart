import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:recieptnest_ai/src/features/auth/data/auth_repository.dart';
import 'package:recieptnest_ai/src/features/auth/models/user_profile.dart';
import 'package:recieptnest_ai/src/features/getting_started/data/native_onboarding_repository.dart';
import 'package:recieptnest_ai/src/features/home/presentation/home_screen.dart';
import 'package:recieptnest_ai/src/features/receipts/data/receipt_repository.dart';
import 'package:recieptnest_ai/src/features/receipts/models/receipt.dart';
import 'support/onboarding_fakes.dart';

class TestUser extends Fake implements User {
  TestUser(this.uid);
  @override
  final String uid;
  Future<void> Function()? onReload;
  int reloads = 0;
  @override
  bool get emailVerified => true;
  @override
  String get email => '$uid@example.test';
  @override
  String get displayName => 'Test User';
  @override
  List<UserInfo> get providerData => [];
  @override
  Future<void> reload() async {
    reloads++;
    await onReload?.call();
  }
}

class TestAuth extends Fake implements FirebaseAuth {
  TestAuth(this.currentUser);
  @override
  User? currentUser;
  int signOuts = 0;
  @override
  Future<void> signOut() async {
    signOuts++;
    currentUser = null;
  }
}

// Firestore documents are faked only at the SDK boundary in these unit tests.
// ignore: subtype_of_sealed_class
class TestProfileSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  TestProfileSnapshot(this.id, this.value);
  @override
  final String id;
  final Map<String, dynamic>? value;
  @override
  bool get exists => value != null;
  @override
  Map<String, dynamic>? data() => value;
}

// ignore: subtype_of_sealed_class
class TestDocument extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  TestDocument(this.id, this.db);
  @override
  final String id;
  final TestFirestore db;
  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => db.snapshots.stream;
}

// ignore: subtype_of_sealed_class
class TestCollection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  TestCollection(this.db);
  final TestFirestore db;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      TestDocument(path!, db);
}

class TestTransaction extends Fake implements Transaction {
  TestTransaction(this.db);
  final TestFirestore db;
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> reference,
  ) async {
    await db.beforeRead?.call();
    return TestProfileSnapshot(reference.id, db.profiles[reference.id])
        as DocumentSnapshot<T>;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> reference,
    T data, [
    SetOptions? options,
  ]) {
    db.writes++;
    db.profiles[reference.id] = {
      if (options?.merge == true) ...?db.profiles[reference.id],
      ...data as Map<String, dynamic>,
    };
    return this;
  }
}

class TestFirestore extends Fake implements FirebaseFirestore {
  final profiles = <String, Map<String, dynamic>>{};
  final snapshots =
      StreamController<DocumentSnapshot<Map<String, dynamic>>>.broadcast();
  Future<void> Function()? beforeRead;
  int writes = 0;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      TestCollection(this);
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) => transactionHandler(TestTransaction(this));
}

class TestCallableResult<T> extends Fake implements HttpsCallableResult<T> {
  TestCallableResult(this.data);
  @override
  final T data;
}

class TestCallable extends Fake implements HttpsCallable {
  TestCallable(this.callFunction);
  final Future<Map<String, dynamic>> Function(dynamic data) callFunction;
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async =>
      TestCallableResult(await callFunction(parameters) as T);
}

class TestFunctions extends Fake implements FirebaseFunctions {
  late Future<Map<String, dynamic>> Function(String name, dynamic data) onCall;
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      TestCallable((data) => onCall(name, data));
}

Map<String, dynamic> profile(String uid) => {
  'id': uid,
  'firstName': 'Test',
  'lastName': 'User',
  'email': '$uid@example.test',
  'role': 'user',
  'receiptCount': 0,
  'notificationSettings': NotificationSettings.defaults.toMap(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestUser user;
  late TestAuth auth;
  late TestFirestore db;
  late TestFunctions functions;
  late AuthRepository repository;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    user = TestUser('old-account');
    auth = TestAuth(user);
    db = TestFirestore();
    functions = TestFunctions();
    repository = AuthRepository(auth: auth, db: db, functions: functions);
  });
  tearDown(() => db.snapshots.close());

  test(
    'onboarding waits for the server profile before its first callable',
    () async {
      final read = Completer<void>();
      db.beforeRead = () => read.future;
      var calls = 0;
      functions.onCall = (name, data) async {
        calls++;
        expect(db.profiles[user.uid], isNotNull);
        return {
          'receiptCount': 0,
          'progress': const NativeOnboardingProgress().toMap(),
        };
      };
      final container = ProviderContainer(
        overrides: [
          functionsProvider.overrideWithValue(functions),
          authRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final loading = container
          .read(nativeOnboardingRepositoryProvider)
          .load(user.uid);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
      read.complete();
      final state = await loading;
      expect(calls, 1);
      expect(state.receiptCount, 0);
      expect(state.enterGuide, isTrue);
    },
  );

  test(
    'concurrent preparation is coalesced and preserves server-owned fields',
    () async {
      db.profiles[user.uid] = {
        ...profile(user.uid),
        'nativeOnboarding': {'status': 'completed'},
        'subscriptionPlan': 'pro',
        'receiptCount': 7,
      };
      await Future.wait([
        repository.ensureAccountReady(user.uid),
        repository.ensureAccountReady(user.uid),
        repository.ensureAccountReady(user.uid),
      ]);
      expect(user.reloads, 1);
      expect(db.profiles[user.uid]!['receiptCount'], 7);
      expect(db.profiles[user.uid]!['subscriptionPlan'], 'pro');
      expect(db.profiles[user.uid]!['nativeOnboarding'], {
        'status': 'completed',
      });
      expect(db.writes, 0);
    },
  );

  test(
    'deletion blocks profile repair and rejoining starts with a fresh guide',
    () async {
      SharedPreferences.setMockInitialValues({
        'native_onboarding_v2:old-account': 'old progress',
        'native_onboarding_v2:old-account:pending': ['old task'],
        'native_onboarding_v2:old-account:count': 3,
        'receipt_upload_activity_v1:old-account': 'old upload',
        'getting_started_prompt_v1:old-account': true,
        'native_onboarding_v2:another-account': 'keep',
        'theme_mode': 'dark',
      });
      db.profiles[user.uid] = profile(user.uid);
      final subscription = repository
          .userProfileStream(user.uid)
          .listen((_) {});
      addTearDown(subscription.cancel);
      functions.onCall = (name, data) async {
        expect(name, 'deleteUserAccount');
        db.profiles.remove(user.uid);
        db.snapshots.add(TestProfileSnapshot(user.uid, null));
        await Future<void>.delayed(Duration.zero);
        expect(db.profiles, isEmpty);
        return {'ok': true};
      };
      await repository.deleteAccount();
      expect(auth.currentUser, isNull);
      expect(db.writes, 0);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getKeys().where((key) => key.contains('old-account')),
        isEmpty,
      );
      expect(
        preferences.getString('native_onboarding_v2:another-account'),
        'keep',
      );
      expect(preferences.getString('theme_mode'), 'dark');

      final returning = TestUser('new-account');
      auth.currentUser = returning;
      functions.onCall = (name, data) async {
        expect(data['expectedUserId'], returning.uid);
        expect(db.profiles[returning.uid], isNotNull);
        return {
          'receiptCount': 0,
          'progress': const NativeOnboardingProgress().toMap(),
        };
      };
      final container = ProviderContainer(
        overrides: [
          functionsProvider.overrideWithValue(functions),
          authRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final state = await container
          .read(nativeOnboardingRepositoryProvider)
          .load(returning.uid);
      expect(state.enterGuide, isTrue);
      expect(state.progress.receiptId, isNull);
      expect(state.receiptCount, 0);
      expect(db.profiles.containsKey(user.uid), isFalse);
    },
  );

  test(
    'failed deletion preserves the session and its resumable work',
    () async {
      SharedPreferences.setMockInitialValues({
        'native_onboarding_v2:old-account': 'keep',
      });
      functions.onCall = (_, data) async => throw FirebaseFunctionsException(
        code: 'unavailable',
        message: 'offline',
      );
      await expectLater(
        repository.deleteAccount(),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      expect(auth.currentUser, user);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'native_onboarding_v2:old-account',
        ),
        'keep',
      );
      await repository.ensureAccountReady(user.uid);
      expect(db.profiles[user.uid], isNotNull);
    },
  );

  test(
    'deletion drains an already-started repair before removing the profile',
    () async {
      final read = Completer<void>();
      final beganRead = Completer<void>();
      db.beforeRead = () {
        if (!beganRead.isCompleted) beganRead.complete();
        return read.future;
      };
      final subscription = repository
          .userProfileStream(user.uid)
          .listen((_) {});
      addTearDown(subscription.cancel);
      db.snapshots.add(TestProfileSnapshot(user.uid, null));
      await beganRead.future;
      var called = false;
      functions.onCall = (_, data) async {
        called = true;
        expect(db.writes, 0);
        return {'ok': true};
      };
      final deletion = repository.deleteAccount();
      await Future<void>.delayed(Duration.zero);
      expect(called, isFalse);
      read.complete();
      await deletion;
      expect(called, isTrue);
      expect(db.writes, 0);
      expect(auth.currentUser, isNull);
    },
  );

  test(
    'a missing profile for a remotely deleted user is never recreated',
    () async {
      final reloaded = Completer<void>();
      user.onReload = () async {
        reloaded.complete();
        throw FirebaseAuthException(code: 'user-not-found');
      };
      final subscription = repository
          .userProfileStream(user.uid)
          .listen((_) {});
      addTearDown(subscription.cancel);
      db.snapshots.add(TestProfileSnapshot(user.uid, null));
      await reloaded.future;
      await Future<void>.delayed(Duration.zero);
      expect(auth.currentUser, isNull);
      expect(db.writes, 0);
    },
  );

  for (final code in [
    'user-not-found',
    'user-disabled',
    'invalid-user-token',
    'user-token-expired',
  ]) {
    test('a remotely invalidated session ($code) returns to sign-in', () async {
      user.onReload = () async => throw FirebaseAuthException(code: code);
      expect(await repository.refreshCurrentUser(), isFalse);
      expect(auth.currentUser, isNull);
      expect(auth.signOuts, 1);
      expect(db.writes, 0);
    });
  }

  test(
    'network errors keep the signed-in account and allow preparation to retry',
    () async {
      user.onReload = () async =>
          throw FirebaseAuthException(code: 'network-request-failed');
      await expectLater(
        repository.ensureAccountReady(user.uid),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(auth.currentUser, user);
      user.onReload = null;
      await repository.ensureAccountReady(user.uid);
      expect(db.profiles[user.uid], isNotNull);
    },
  );

  test(
    'a re-enabled account can sign in again in the same app session',
    () async {
      user.onReload = () async =>
          throw FirebaseAuthException(code: 'user-disabled');
      await repository.refreshCurrentUser();
      user.onReload = null;
      auth.currentUser = user;
      await repository.ensureAccountReady(user.uid);
      expect(db.profiles[user.uid], isNotNull);
      expect(auth.currentUser, user);
    },
  );

  test('a late onboarding failure cannot replace a successful retry', () async {
    final first = Completer<Map<String, dynamic>>();
    final second = Completer<Map<String, dynamic>>();
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    var calls = 0;
    final onboarding = NativeOnboardingRepository((_, data) {
      if (++calls == 1) {
        firstStarted.complete();
        return first.future;
      }
      secondStarted.complete();
      return second.future;
    });
    final controller = NativeOnboardingController(
      user.uid,
      onboarding,
      SilentAnalytics(),
    );
    addTearDown(controller.dispose);
    await firstStarted.future;
    final retry = controller.load();
    await secondStarted.future;
    second.complete({
      'receiptCount': 0,
      'progress': const NativeOnboardingProgress().toMap(),
    });
    await retry;
    expect(controller.state.value!.enterGuide, isTrue);
    first.completeError(
      FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Account is not ready yet.',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.hasError, isFalse);
    expect(controller.state.value!.enterGuide, isTrue);
  });

  test(
    'an old session completion cannot initialize or sign out a new account',
    () async {
      final reload = Completer<void>();
      user.onReload = () => reload.future;
      final loading = repository.ensureAccountReady(user.uid);
      final assertion = expectLater(loading, throwsA(isA<AppAuthException>()));
      auth.currentUser = TestUser('new-account');
      reload.completeError(FirebaseAuthException(code: 'user-not-found'));
      await assertion;
      expect(auth.currentUser!.uid, 'new-account');
      expect(auth.signOuts, 0);
      expect(db.writes, 0);
    },
  );

  test(
    'a profile transaction finishing after sign-out cannot recreate the account',
    () async {
      final read = Completer<void>();
      db.beforeRead = () => read.future;
      final loading = repository.ensureAccountReady(user.uid);
      final assertion = expectLater(loading, throwsA(isA<AppAuthException>()));
      await Future<void>.delayed(Duration.zero);
      await repository.logout();
      read.complete();
      await assertion;
      expect(db.writes, 0);
    },
  );

  testWidgets('Home retries a failed receipt subscription without raw errors', (
    tester,
  ) async {
    var subscriptions = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue(user.uid),
          currentUserProfileProvider.overrideWith(
            (ref) => Stream.value(
              UserProfile(
                id: user.uid,
                firstName: 'Test',
                lastName: '',
                email: user.email,
              ),
            ),
          ),
          authRepositoryProvider.overrideWithValue(repository),
          receiptRepositoryProvider.overrideWithValue(
            MemoryReceiptRepository(),
          ),
          receiptsStreamProvider.overrideWith(
            (ref) => ++subscriptions == 1
                ? Stream<List<Receipt>>.error(
                    FirebaseException(
                      plugin: 'cloud_firestore',
                      code: 'unavailable',
                    ),
                  )
                : Stream.value(const <Receipt>[]),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('We couldn’t load your receipts.'), findsOneWidget);
    expect(find.textContaining('cloud_firestore'), findsNothing);
    expect(find.text('Add my first receipt'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(subscriptions, 2);
    expect(find.text('Add my first receipt'), findsOneWidget);
    expect(find.text('We couldn’t load your receipts.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
