import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/data/auth_repository.dart';
import '../models/receipt.dart';
import 'receipt_repository.dart';
import 'receipt_upload_activity.dart';

bool isReceiptForwardingAddress(String? value) =>
    value != null &&
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());

// The server owns address allocation. Never construct an alias from a name or
// email on the device, or require a receipt before allocating one.
final receiptForwardingAddressProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  final repository = ref.watch(receiptRepositoryProvider);
  final profileFuture = ref.watch(currentUserProfileProvider.future);
  var cancelled = false;
  ref.onDispose(() => cancelled = true);
  final profile = await profileFuture;
  if (cancelled) return null;
  if (profile?.id != uid) throw StateError('Account is not ready');
  final stored = profile?.receiptForwardingAddress?.trim();
  if (isReceiptForwardingAddress(stored)) return stored;
  final result = await repository.generateForwardingAddress().timeout(
    const Duration(seconds: 20),
  );
  final address = result['emailAddress']?.toString().trim();
  if (!isReceiptForwardingAddress(address)) {
    throw StateError('Missing receipt forwarding address');
  }
  return address;
});

// Observe arrivals throughout the signed-in session, including while the user
// is looking at another tab. The first snapshot is a baseline, never a batch of
// "new" receipts. Account changes discard that baseline and any pending result.
final emailReceiptArrivalProvider =
    StateNotifierProvider<EmailReceiptArrivalController, Receipt?>((ref) {
      final controller = EmailReceiptArrivalController(
        ref.watch(currentUserIdProvider),
        ref.watch(receiptUploadActivityProvider.notifier),
      );
      ref.listen(receiptsStreamProvider, (_, next) {
        if (next is AsyncData<List<Receipt>>) controller.observe(next.value);
      }, fireImmediately: true);
      return controller;
    });

class EmailReceiptArrivalController extends StateNotifier<Receipt?> {
  EmailReceiptArrivalController(this.uid, this.activity) : super(null) {
    restored = uid == null ? Future.value() : _restore();
  }
  final String? uid;
  final ReceiptUploadActivityController activity;
  final _seen = <String>{};
  final _announced = <String>{};
  bool _initialized = false;
  List<Receipt> _latest = const [];
  DateTime? _expectedSince;
  Set<String> _expectedIds = const {};
  bool _localExpectation = false;
  late final Future<void> restored;
  Future<void> _writes = Future.value();
  Future<void> get settled => _writes;
  String get _key => 'receipt_email_pending_v1:$uid';

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (!mounted || _localExpectation || raw == null) return;
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final since = DateTime.tryParse(data['since']?.toString() ?? '');
      if (since == null ||
          DateTime.now().difference(since) > const Duration(days: 7)) {
        return;
      }
      _expectedSince = since;
      _expectedIds = (data['ids'] as List?)?.whereType<String>().toSet() ?? {};
      _checkExpected();
    } catch (_) {
      // A local checkpoint must never block forwarding a receipt.
    }
  }

  void expectReceipt() {
    if (!mounted || uid == null) return;
    _localExpectation = true;
    _expectedSince = DateTime.now();
    _expectedIds = Set.of(_seen);
    _persistExpectation();
  }

  void _persistExpectation() {
    final value = _expectedSince == null
        ? null
        : jsonEncode({
            'since': _expectedSince!.toIso8601String(),
            'ids': _expectedIds.toList(),
          });
    _writes = _writes
        .then((_) async {
          await restored;
          final prefs = await SharedPreferences.getInstance();
          if (value == null) {
            await prefs.remove(_key);
          } else {
            await prefs.setString(_key, value);
          }
        })
        .catchError((Object _) {});
  }

  void _checkExpected() {
    final since = _expectedSince;
    final expectedIds = _expectedIds;
    if (since == null || !mounted) return;
    for (final receipt in _latest) {
      final created = receipt.createdAt ?? receipt.file.uploadedAt;
      if (receipt.source != 'email' ||
          expectedIds.contains(receipt.id) ||
          created == null ||
          created.isBefore(since.subtract(const Duration(minutes: 5)))) {
        continue;
      }
      _arrived(receipt);
    }
  }

  void _arrived(Receipt receipt) {
    if (!_announced.add(receipt.id)) return;
    activity.track(receipt, first: _latest.length == 1);
    state = receipt;
    if (_expectedSince != null) {
      _expectedSince = null;
      _expectedIds = const {};
      _persistExpectation();
    }
  }

  void observe(List<Receipt> receipts) {
    if (!mounted || uid == null) return;
    final own = receipts.where((receipt) => receipt.userId == uid).toList();
    _latest = own;
    if (!_initialized) {
      _initialized = true;
      _seen.addAll(own.map((receipt) => receipt.id));
      _checkExpected();
      return;
    }
    final incoming =
        own.where((receipt) => !_seen.contains(receipt.id)).toList()..sort(
          (a, b) => (a.createdAt ?? DateTime(1970)).compareTo(
            b.createdAt ?? DateTime(1970),
          ),
        );
    _seen.addAll(own.map((receipt) => receipt.id));
    for (final receipt in incoming.where(
      (receipt) => receipt.source == 'email',
    )) {
      _arrived(receipt);
    }
    _checkExpected();
  }
}
