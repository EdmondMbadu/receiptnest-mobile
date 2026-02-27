import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_utils.dart';

class AiChatMessage {
  const AiChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
  });

  final String id;
  final String role;
  final String content;
  final DateTime timestamp;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory AiChatMessage.fromMap(Map<String, dynamic> map) {
    return AiChatMessage(
      id: (map['id'] as String?) ?? '',
      role: (map['role'] as String?) ?? 'user',
      content: (map['content'] as String?) ?? '',
      timestamp: asDateTime(map['timestamp']) ?? DateTime.now(),
    );
  }
}

class AiChatHistoryItem {
  const AiChatHistoryItem({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messageCount,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;

  factory AiChatHistoryItem.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return AiChatHistoryItem(
      id: doc.id,
      title: (data['title'] as String?) ?? 'New chat',
      createdAt: asDateTime(data['createdAt']) ?? DateTime.now(),
      updatedAt: asDateTime(data['updatedAt']) ?? DateTime.now(),
      messageCount: (data['messageCount'] as num?)?.toInt() ??
          ((data['messages'] as List<dynamic>?)?.length ?? 0),
    );
  }
}
