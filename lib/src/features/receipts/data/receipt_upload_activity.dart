import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/data/auth_repository.dart';
import '../models/receipt.dart';

/// Only receipt references are persisted. Files and extracted content remain in
/// the receipt repository, and activity is isolated to the signed-in account.
class ReceiptUploadActivity {
  const ReceiptUploadActivity({
    required this.id,
    required this.startedAt,
    this.guided = false,
    this.first = false,
    this.seed,
  });
  final String id;
  final DateTime startedAt;
  final bool guided;
  final bool first;
  final Receipt? seed;
}

final receiptUploadActivityProvider =
    StateNotifierProvider<
      ReceiptUploadActivityController,
      List<ReceiptUploadActivity>
    >(
      (ref) =>
          ReceiptUploadActivityController(ref.watch(currentUserIdProvider)),
    );

class ReceiptUploadActivityController
    extends StateNotifier<List<ReceiptUploadActivity>> {
  ReceiptUploadActivityController(this.userId) : super(const []) {
    restored = userId == null ? Future.value() : _restore();
  }
  final String? userId;
  late final Future<void> restored;
  Future<void> get settled => _writes;
  List<ReceiptUploadActivity> _restoredItems = const [];
  final _dismissed = <String>{};
  Future<void> _writes = Future.value();
  String get _key => 'receipt_upload_activity_v1:$userId';

  Future<void> _restore() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_key);
      if (raw == null) return;
      final values = jsonDecode(raw);
      if (values is! List) return;
      final restored = <ReceiptUploadActivity>[];
      final seen = <String>{};
      for (final value in values) {
        if (value is! Map || value['id'] is! String) continue;
        final id = value['id'] as String;
        final startedAt = DateTime.tryParse(
          value['startedAt']?.toString() ?? '',
        );
        if (id.isEmpty ||
            id.contains('/') ||
            startedAt == null ||
            !seen.add(id)) {
          continue;
        }
        restored.add(
          ReceiptUploadActivity(
            id: id,
            startedAt: startedAt,
            guided: value['guided'] == true,
            first: value['first'] == true,
          ),
        );
      }
      _restoredItems = restored;
      if (mounted) {
        state = [
          ...restored.where(
            (item) =>
                !_dismissed.contains(item.id) &&
                !state.any((current) => current.id == item.id),
          ),
          ...state,
        ];
      }
    } catch (_) {
      // A local checkpoint failure must never prevent uploading a receipt.
    }
  }

  void track(Receipt receipt, {bool guided = false, bool first = false}) {
    if (!mounted || receipt.userId != userId) return;
    _dismissed.remove(receipt.id);
    state = [
      ...state.where((item) => item.id != receipt.id),
      ReceiptUploadActivity(
        id: receipt.id,
        startedAt:
            receipt.file.uploadedAt ?? receipt.createdAt ?? DateTime.now(),
        guided: guided,
        first: first,
        seed: receipt,
      ),
    ];
    _persist();
  }

  void acknowledge(String id) {
    if (!mounted) return;
    _dismissed.add(id);
    state = state.where((item) => item.id != id).toList();
    _persist();
  }

  void _persist() {
    final snapshot = List<ReceiptUploadActivity>.of(state);
    final dismissed = Set<String>.of(_dismissed);
    // Delay serializing until restoration finishes, so a very fast new upload
    // cannot overwrite references saved by an earlier app session.
    _writes = _writes
        .then((_) async {
          await restored;
          final merged = [
            ..._restoredItems.where(
              (item) =>
                  !dismissed.contains(item.id) &&
                  !snapshot.any((current) => current.id == item.id),
            ),
            ...snapshot,
          ];
          final values = merged
              .map(
                (item) => {
                  'id': item.id,
                  'startedAt': item.startedAt.toIso8601String(),
                  'guided': item.guided,
                  'first': item.first,
                },
              )
              .toList();
          final preferences = await SharedPreferences.getInstance();
          await preferences.setString(_key, jsonEncode(values));
        })
        .catchError((Object _) {});
  }
}
