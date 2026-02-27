import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../models/share_models.dart';

final shareRepositoryProvider = Provider<ShareRepository>((ref) {
  return ShareRepository(db: ref.watch(firestoreProvider));
});

class ShareRepository {
  ShareRepository({required FirebaseFirestore db}) : _db = db;

  final FirebaseFirestore _db;

  Future<GraphShare> createGraphShare({
    required String userId,
    required int month,
    required int year,
    required String monthLabel,
    required double totalSpend,
    required List<GraphSharePoint> dailyData,
    required bool includeName,
    required bool includeEmail,
    String? ownerName,
    String? ownerEmail,
  }) async {
    if (dailyData.isEmpty) {
      throw Exception('No spending data available for this month.');
    }

    final payload = {
      'userId': userId,
      'month': month,
      'year': year,
      'monthLabel': monthLabel,
      'totalSpend': totalSpend,
      'dailyData': dailyData.map((d) => d.toMap()).toList(),
      'includeName': includeName,
      'includeEmail': includeEmail,
      'ownerName': includeName ? (ownerName ?? '').trim() : '',
      'ownerEmail': includeEmail ? (ownerEmail ?? '').trim() : '',
      'createdAt': FieldValue.serverTimestamp(),
    };

    final ref = await _db.collection('graphShares').add(payload);
    return GraphShare.fromMap(ref.id, payload);
  }

  Future<ChatShare> createChatShare({
    required String userId,
    required String chatId,
    required String title,
    required List<ChatShareMessage> messages,
  }) async {
    if (messages.isEmpty) {
      throw Exception('Cannot share an empty chat.');
    }

    final payload = {
      'userId': userId,
      'chatId': chatId,
      'title': title,
      'messages': messages.map((m) => m.toMap()).toList(),
      'messageCount': messages.length,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final ref = await _db.collection('chatShares').add(payload);
    return ChatShare.fromMap(ref.id, payload);
  }

  Future<GraphShare?> getGraphShare(String shareId) async {
    final snapshot = await _db.collection('graphShares').doc(shareId).get();
    if (!snapshot.exists) return null;
    return GraphShare.fromMap(snapshot.id, snapshot.data() ?? const {});
  }

  Future<ChatShare?> getChatShare(String shareId) async {
    final snapshot = await _db.collection('chatShares').doc(shareId).get();
    if (!snapshot.exists) return null;
    return ChatShare.fromMap(snapshot.id, snapshot.data() ?? const {});
  }

  Future<PublicShare?> getPublicShare(String shareId) async {
    final graph = await getGraphShare(shareId);
    if (graph != null) {
      return PublicShare.graph(graph);
    }

    final chat = await getChatShare(shareId);
    if (chat != null) {
      return PublicShare.chat(chat);
    }

    return null;
  }
}
