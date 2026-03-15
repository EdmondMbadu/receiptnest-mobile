import '../../../core/utils/firestore_utils.dart';

class FolderMergeEntry {
  const FolderMergeEntry({
    required this.mergeId,
    required this.sourceFolderId,
    required this.sourceFolderName,
    required this.sourceFolderReceiptIds,
    required this.sourceOnlyReceiptIds,
    this.sourceIsAuto,
    this.sourceAutoType,
    this.sourceAutoKey,
    this.mergedAt,
  });

  final String mergeId;
  final String sourceFolderId;
  final String sourceFolderName;
  final List<String> sourceFolderReceiptIds;
  final List<String> sourceOnlyReceiptIds;
  final bool? sourceIsAuto;
  final String? sourceAutoType;
  final String? sourceAutoKey;
  final DateTime? mergedAt;

  factory FolderMergeEntry.fromMap(Map<String, dynamic> data) {
    return FolderMergeEntry(
      mergeId: (data['mergeId'] as String?) ?? '',
      sourceFolderId: (data['sourceFolderId'] as String?) ?? '',
      sourceFolderName: (data['sourceFolderName'] as String?) ?? '',
      sourceFolderReceiptIds:
          (data['sourceFolderReceiptIds'] as List<dynamic>? ?? const []).whereType<String>().toList(),
      sourceOnlyReceiptIds:
          (data['sourceOnlyReceiptIds'] as List<dynamic>? ?? const []).whereType<String>().toList(),
      sourceIsAuto: data['sourceIsAuto'] as bool?,
      sourceAutoType: data['sourceAutoType'] as String?,
      sourceAutoKey: data['sourceAutoKey'] as String?,
      mergedAt: asDateTime(data['mergedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'mergeId': mergeId,
      'sourceFolderId': sourceFolderId,
      'sourceFolderName': sourceFolderName,
      'sourceFolderReceiptIds': sourceFolderReceiptIds,
      'sourceOnlyReceiptIds': sourceOnlyReceiptIds,
      'sourceIsAuto': sourceIsAuto,
      'sourceAutoType': sourceAutoType,
      'sourceAutoKey': sourceAutoKey,
      'mergedAt': mergedAt,
    };
  }
}

class Folder {
  const Folder({
    required this.id,
    required this.userId,
    required this.name,
    required this.receiptIds,
    this.isAuto = false,
    this.autoType,
    this.autoKey,
    this.mergedSources = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final String name;
  final List<String> receiptIds;
  final bool isAuto;
  final String? autoType;
  final String? autoKey;
  final List<FolderMergeEntry> mergedSources;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Folder.fromDoc(String id, Map<String, dynamic> data) {
    return Folder(
      id: id,
      userId: (data['userId'] as String?) ?? '',
      name: (data['name'] as String?) ?? 'Collection',
      receiptIds: (data['receiptIds'] as List<dynamic>? ?? const []).whereType<String>().toList(),
      isAuto: (data['isAuto'] as bool?) ?? false,
      autoType: data['autoType'] as String?,
      autoKey: data['autoKey'] as String?,
      mergedSources: (data['mergedSources'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FolderMergeEntry.fromMap)
          .toList(),
      createdAt: asDateTime(data['createdAt']),
      updatedAt: asDateTime(data['updatedAt']),
    );
  }
}
