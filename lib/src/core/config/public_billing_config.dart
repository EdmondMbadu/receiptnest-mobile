import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';

const defaultFreePlanReceiptLimit = 50;
const publicConfigCollection = 'publicConfig';
const publicBillingConfigDocId = 'billing';

int normalizeFreePlanReceiptLimit(Object? value) {
  final parsed = switch (value) {
    int n => n,
    double n => n.toInt(),
    String s => int.tryParse(s),
    _ => null,
  };

  if (parsed == null || parsed < 1) {
    return defaultFreePlanReceiptLimit;
  }

  return parsed;
}

class PublicBillingConfig {
  const PublicBillingConfig({required this.freePlanReceiptLimit});

  final int freePlanReceiptLimit;

  factory PublicBillingConfig.fromMap(Map<String, dynamic>? data) {
    return PublicBillingConfig(
      freePlanReceiptLimit: normalizeFreePlanReceiptLimit(
        data?['freePlanReceiptLimit'],
      ),
    );
  }
}

final publicBillingConfigProvider = StreamProvider<PublicBillingConfig>((ref) {
  final db = ref.watch(firestoreProvider);
  return db
      .collection(publicConfigCollection)
      .doc(publicBillingConfigDocId)
      .snapshots()
      .map((snapshot) => PublicBillingConfig.fromMap(snapshot.data()));
});

Future<int> fetchFreePlanReceiptLimit(FirebaseFirestore db) async {
  final snapshot = await db
      .collection(publicConfigCollection)
      .doc(publicBillingConfigDocId)
      .get();
  return normalizeFreePlanReceiptLimit(
    snapshot.data()?['freePlanReceiptLimit'],
  );
}
