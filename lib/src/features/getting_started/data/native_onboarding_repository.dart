import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../auth/data/auth_repository.dart';
import '../../receipts/models/receipt.dart';
import 'onboarding_analytics.dart';

const nativeOnboardingVersion = 2;

bool isUsableReceipt(Receipt receipt) =>
    receipt.status == ReceiptStatuses.finalStatus ||
    (receipt.status == ReceiptStatuses.needsReview &&
        receipt.effectiveTotalAmount != null &&
        receipt.effectiveTotalAmount!.isFinite);

class NativeOnboardingProgress {
  const NativeOnboardingProgress({
    this.status = 'new',
    this.receiptId,
    this.firstOpenedAt,
    this.baselineReceiptCount,
    this.viewedAt,
    this.completedAt,
    this.updatedAt = 0,
    this.cohort = 'unknown_account',
  });

  final String status;
  final String? receiptId;
  final int? firstOpenedAt;
  final int? baselineReceiptCount;
  final int? viewedAt;
  final int? completedAt;
  final int updatedAt;
  final String cohort;

  bool get completed => status == 'completed';
  bool get shouldResume => status == 'in_progress';

  factory NativeOnboardingProgress.fromMap(Map<String, dynamic>? data) {
    if (data == null || data['version'] != nativeOnboardingVersion) {
      return const NativeOnboardingProgress();
    }
    return NativeOnboardingProgress(
      status: data['status'] as String? ?? 'new',
      receiptId: data['receiptId'] as String?,
      firstOpenedAt: (data['firstOpenedAt'] as num?)?.toInt(),
      baselineReceiptCount: (data['baselineReceiptCount'] as num?)?.toInt(),
      viewedAt: (data['viewedAt'] as num?)?.toInt(),
      completedAt: (data['completedAt'] as num?)?.toInt(),
      updatedAt: (data['updatedAt'] as num?)?.toInt() ?? 0,
      cohort: data['cohort'] as String? ?? 'unknown_account',
    );
  }

  Map<String, dynamic> toMap() => {
    'version': nativeOnboardingVersion,
    'status': status,
    'receiptId': receiptId,
    'firstOpenedAt': firstOpenedAt,
    'baselineReceiptCount': baselineReceiptCount,
    'viewedAt': viewedAt,
    'completedAt': completedAt,
    'updatedAt': updatedAt,
    'cohort': cohort,
  };

  NativeOnboardingProgress change(String action, {String? receiptId}) {
    if (completed || action == 'observe') return this;
    final clock = DateTime.now().millisecondsSinceEpoch;
    final now = clock > updatedAt ? clock : updatedAt + 1;
    return NativeOnboardingProgress(
      status: completed
          ? 'completed'
          : switch (action) {
              'pause' => 'paused',
              'complete' => 'completed',
              _ => 'in_progress',
            },
      receiptId: action == 'restart' ? null : receiptId ?? this.receiptId,
      firstOpenedAt: firstOpenedAt,
      baselineReceiptCount: baselineReceiptCount,
      viewedAt:
          action == 'restart' ||
              (receiptId != null && receiptId != this.receiptId)
          ? (action == 'view' ? now : null)
          : action == 'view'
          ? viewedAt ?? now
          : viewedAt,
      completedAt: action == 'complete' ? completedAt ?? now : completedAt,
      updatedAt: now,
      cohort: cohort,
    );
  }
}

class NativeOnboardingState {
  const NativeOnboardingState({
    required this.receiptCount,
    required this.progress,
  });
  final int receiptCount;
  final NativeOnboardingProgress progress;

  bool get introduce => receiptCount < 5 && progress.status == 'new';
  bool get enterGuide =>
      receiptCount < 5 &&
      (introduce || (!progress.completed && progress.shouldResume));
}

typedef NativeOnboardingCall =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, dynamic> data,
    );

final nativeOnboardingRepositoryProvider = Provider<NativeOnboardingRepository>(
  (ref) {
    final functions = ref.watch(functionsProvider);
    return NativeOnboardingRepository((name, data) async {
      final result = await functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 12)),
          )
          .call(data);
      return Map<String, dynamic>.from(result.data as Map);
    });
  },
);

/// An account-scoped durable outbox: local checkpoints finish before navigation.
/// Server writes are ordered, retried on entry/resume, and never touch web state.
class NativeOnboardingRepository {
  NativeOnboardingRepository(this.call);
  final NativeOnboardingCall call;
  final Map<String, Future<NativeOnboardingProgress?>> _flushes = {};
  final Set<String> _initialized = {};
  Future<void> _storage = Future.value();
  String _key(String uid) => 'native_onboarding_v2:$uid';
  String _outbox(String uid) => '${_key(uid)}:pending';

  Future<T> _local<T>(Future<T> Function(SharedPreferences prefs) work) {
    final result = Completer<T>();
    _storage = _storage.then((_) async {
      try {
        result.complete(await work(await SharedPreferences.getInstance()));
      } catch (e, st) {
        result.completeError(e, st);
      }
    });
    return result.future;
  }

  Future<NativeOnboardingState> load(String uid) async {
    final local = await _local(
      (prefs) async => _decode(prefs.getString(_key(uid))),
    );
    try {
      final data = await call('getNativeOnboardingState', {
        'expectedUserId': uid,
      });
      _initialized.add(uid);
      var progress = NativeOnboardingProgress.fromMap(
        Map<String, dynamic>.from(data['progress'] as Map),
      );
      final synced = await flush(uid);
      if (synced != null) progress = synced;
      final pending = await _local(
        (prefs) async => (prefs.getStringList(_outbox(uid)) ?? []).isNotEmpty,
      );
      if (pending && !progress.completed) progress = local;
      await _local((prefs) async {
        await prefs.setString(_key(uid), jsonEncode(progress.toMap()));
        await prefs.setInt('${_key(uid)}:count', data['receiptCount'] as int);
      });
      return NativeOnboardingState(
        receiptCount: data['receiptCount'] as int,
        progress: progress,
      );
    } on FirebaseFunctionsException catch (e) {
      if (['unavailable', 'deadline-exceeded', 'internal'].contains(e.code) &&
          local.status != 'new') {
        final cachedCount = await _local(
          (prefs) async => prefs.getInt('${_key(uid)}:count'),
        );
        if (cachedCount != null) {
          return NativeOnboardingState(
            receiptCount: cachedCount,
            progress: local,
          );
        }
      }
      if (e.code != 'not-found' && e.code != 'unimplemented') rethrow;
      // UI testing works before the additive backend is released. No web writes.
      final data = await call('getGettingStartedState', {
        'expectedUserId': uid,
      });
      await _local((prefs) async {
        await prefs.setInt('${_key(uid)}:count', data['receiptCount'] as int);
      });
      return NativeOnboardingState(
        receiptCount: data['receiptCount'] as int,
        progress: local,
      );
    }
  }

  NativeOnboardingProgress _decode(String? value) {
    try {
      return NativeOnboardingProgress.fromMap(
        value == null
            ? null
            : Map<String, dynamic>.from(jsonDecode(value) as Map),
      );
    } catch (_) {
      return const NativeOnboardingProgress();
    }
  }

  Future<void> checkpoint(
    String uid,
    NativeOnboardingProgress progress,
    String action, {
    String? receiptId,
  }) => _local((prefs) async {
    final pending = prefs.getStringList(_outbox(uid)) ?? [];
    pending.add(
      jsonEncode({
        'id': const Uuid().v4(),
        'action': action,
        'receiptId': ?receiptId,
      }),
    );
    // Save the action first: even a process kill between writes preserves intent.
    await prefs.setStringList(_outbox(uid), pending);
    await prefs.setString(_key(uid), jsonEncode(progress.toMap()));
  });

  Future<NativeOnboardingProgress?> flush(String uid) {
    final running = _flushes[uid];
    if (running != null) {
      // A new checkpoint can land just as the previous flush finishes. Check
      // the outbox again instead of attaching it to an already-finished flush.
      return running.then((last) async => await flush(uid) ?? last);
    }
    final future = _flush(uid).catchError((Object _) => null);
    _flushes[uid] = future;
    future.whenComplete(() => _flushes.remove(uid));
    return future;
  }

  Future<NativeOnboardingProgress?> _flush(String uid) async {
    NativeOnboardingProgress? saved;
    while (true) {
      final first = await _local((prefs) async {
        final pending = prefs.getStringList(_outbox(uid)) ?? [];
        return pending.isEmpty ? null : pending.first;
      });
      if (first == null) return saved;
      final change = Map<String, dynamic>.from(jsonDecode(first) as Map);
      try {
        if (!_initialized.contains(uid)) {
          await call('getNativeOnboardingState', {'expectedUserId': uid});
          _initialized.add(uid);
        }
        final data = await call('saveNativeOnboardingProgress', {
          'expectedUserId': uid,
          'action': change['action'],
          if (change['receiptId'] != null) 'receiptId': change['receiptId'],
        });
        saved = NativeOnboardingProgress.fromMap(
          Map<String, dynamic>.from(data['progress'] as Map),
        );
      } on FirebaseFunctionsException catch (e) {
        // Deleted/failed receipts cannot make an old task valid; a new receipt
        // can still be chosen. Connectivity/auth failures keep the outbox intact.
        if (e.code != 'failed-precondition' || change['receiptId'] == null) {
          return saved;
        }
      } catch (_) {
        return saved;
      }
      await _local((prefs) async {
        final pending = prefs.getStringList(_outbox(uid)) ?? [];
        pending.remove(first);
        await prefs.setStringList(_outbox(uid), pending);
        if (pending.isEmpty && saved != null) {
          await prefs.setString(_key(uid), jsonEncode(saved.toMap()));
        }
      });
    }
  }
}

final nativeOnboardingProvider = StateNotifierProvider.autoDispose
    .family<
      NativeOnboardingController,
      AsyncValue<NativeOnboardingState>,
      String
    >((ref, uid) {
      return NativeOnboardingController(
        uid,
        ref.watch(nativeOnboardingRepositoryProvider),
        ref.watch(onboardingAnalyticsProvider),
      );
    });

class NativeOnboardingController
    extends StateNotifier<AsyncValue<NativeOnboardingState>> {
  NativeOnboardingController(this.uid, this.repository, this.analytics)
    : super(const AsyncLoading()) {
    load();
  }
  final String uid;
  final NativeOnboardingRepository repository;
  final OnboardingAnalytics analytics;

  Future<void> load() async {
    state = const AsyncLoading();
    try {
      final value = await repository.load(uid);
      analytics.event('native_onboarding_exposure', {
        'cohort': value.progress.cohort,
        'baseline_receipts':
            value.progress.baselineReceiptCount ?? value.receiptCount,
      });
      if (mounted) state = AsyncData(value);
    } catch (e, st) {
      if (mounted) state = AsyncError(e, st);
    }
  }

  Future<void> act(String action, {String? receiptId}) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final progress = current.progress.change(action, receiptId: receiptId);
    state = AsyncData(
      NativeOnboardingState(
        receiptCount: current.receiptCount,
        progress: progress,
      ),
    );
    analytics.event('native_onboarding_$action', {
      'baseline_receipts':
          current.progress.baselineReceiptCount ?? current.receiptCount,
    });
    try {
      await repository.checkpoint(uid, progress, action, receiptId: receiptId);
    } catch (_) {
      // Storage failures must not prevent receipt collection.
    }
    unawaited(sync());
  }

  Future<void> sync() async {
    if (!mounted) return;
    final revision = state.valueOrNull?.progress.updatedAt;
    final saved = await repository.flush(uid);
    if (!mounted) return;
    final current = state.valueOrNull;
    if (mounted &&
        saved != null &&
        current != null &&
        current.progress.updatedAt == revision) {
      state = AsyncData(
        NativeOnboardingState(
          receiptCount: current.receiptCount,
          progress: saved,
        ),
      );
    }
  }
}
