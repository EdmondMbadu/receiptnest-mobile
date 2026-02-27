import '../../../core/utils/firestore_utils.dart';

class GraphSharePoint {
  const GraphSharePoint({
    required this.day,
    required this.amount,
    required this.cumulative,
  });

  final int day;
  final double amount;
  final double cumulative;

  Map<String, dynamic> toMap() => {
        'day': day,
        'amount': amount,
        'cumulative': cumulative,
      };

  factory GraphSharePoint.fromMap(Map<String, dynamic> map) {
    return GraphSharePoint(
      day: (map['day'] as num?)?.toInt() ?? 0,
      amount: ((map['amount'] as num?) ?? 0).toDouble(),
      cumulative: ((map['cumulative'] as num?) ?? 0).toDouble(),
    );
  }
}

class GraphShare {
  const GraphShare({
    required this.id,
    required this.userId,
    required this.month,
    required this.year,
    required this.monthLabel,
    required this.totalSpend,
    required this.dailyData,
    required this.includeName,
    required this.includeEmail,
    this.ownerName,
    this.ownerEmail,
  });

  final String id;
  final String userId;
  final int month;
  final int year;
  final String monthLabel;
  final double totalSpend;
  final List<GraphSharePoint> dailyData;
  final bool includeName;
  final bool includeEmail;
  final String? ownerName;
  final String? ownerEmail;

  factory GraphShare.fromMap(String id, Map<String, dynamic> map) {
    return GraphShare(
      id: id,
      userId: (map['userId'] as String?) ?? '',
      month: (map['month'] as num?)?.toInt() ?? 0,
      year: (map['year'] as num?)?.toInt() ?? 0,
      monthLabel: (map['monthLabel'] as String?) ?? '',
      totalSpend: ((map['totalSpend'] as num?) ?? 0).toDouble(),
      dailyData: (map['dailyData'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(GraphSharePoint.fromMap)
          .toList(),
      includeName: (map['includeName'] as bool?) ?? false,
      includeEmail: (map['includeEmail'] as bool?) ?? false,
      ownerName: map['ownerName'] as String?,
      ownerEmail: map['ownerEmail'] as String?,
    );
  }
}

class ChatShareMessage {
  const ChatShareMessage({
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

  factory ChatShareMessage.fromMap(Map<String, dynamic> map) {
    return ChatShareMessage(
      id: (map['id'] as String?) ?? '',
      role: (map['role'] as String?) ?? 'user',
      content: (map['content'] as String?) ?? '',
      timestamp: asDateTime(map['timestamp']) ?? DateTime.now(),
    );
  }
}

class ChatShare {
  const ChatShare({
    required this.id,
    required this.userId,
    required this.chatId,
    required this.title,
    required this.messages,
    required this.messageCount,
  });

  final String id;
  final String userId;
  final String chatId;
  final String title;
  final List<ChatShareMessage> messages;
  final int messageCount;

  factory ChatShare.fromMap(String id, Map<String, dynamic> map) {
    return ChatShare(
      id: id,
      userId: (map['userId'] as String?) ?? '',
      chatId: (map['chatId'] as String?) ?? '',
      title: (map['title'] as String?) ?? 'Shared conversation',
      messages: (map['messages'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ChatShareMessage.fromMap)
          .toList(),
      messageCount: (map['messageCount'] as num?)?.toInt() ?? 0,
    );
  }
}

enum PublicShareType { graph, chat }

class PublicShare {
  const PublicShare.graph(this.graph)
      : type = PublicShareType.graph,
        chat = null;

  const PublicShare.chat(this.chat)
      : type = PublicShareType.chat,
        graph = null;

  final PublicShareType type;
  final GraphShare? graph;
  final ChatShare? chat;
}
