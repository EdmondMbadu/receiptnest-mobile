import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../receipts/models/receipt.dart';
import '../models/folder.dart';

final folderRepositoryProvider = Provider<FolderRepository>((ref) {
  return FolderRepository(db: ref.watch(firestoreProvider));
});

final foldersStreamProvider = StreamProvider<List<Folder>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream.value(const []);
  }
  return ref.watch(folderRepositoryProvider).watchFolders(uid);
});

class FolderRepository {
  FolderRepository({required FirebaseFirestore db}) : _db = db;

  final FirebaseFirestore _db;

  Stream<List<Folder>> watchFolders(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('folders')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Folder.fromDoc(doc.id, doc.data()))
          .toList();
    });
  }

  Future<void> createFolder(
    String userId,
    String name,
    List<String> receiptIds,
  ) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw Exception('Folder name is required.');
    }

    await _db.collection('users').doc(userId).collection('folders').add({
      'userId': userId,
      'name': cleanName,
      'receiptIds': receiptIds.toSet().toList(),
      'isAuto': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> renameFolder(String userId, String folderId, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) {
      throw Exception('Folder name is required.');
    }

    await _db.collection('users').doc(userId).collection('folders').doc(folderId).update({
      'name': clean,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteFolder(String userId, String folderId) {
    return _db.collection('users').doc(userId).collection('folders').doc(folderId).delete();
  }

  Future<void> addReceipts(String userId, Folder folder, List<String> receiptIds) async {
    final next = {...folder.receiptIds, ...receiptIds}.toList();
    await _updateFolderReceipts(userId, folder.id, next);
  }

  Future<void> removeReceipts(String userId, Folder folder, List<String> receiptIds) async {
    final remove = receiptIds.toSet();
    final next = folder.receiptIds.where((id) => !remove.contains(id)).toList();
    await _updateFolderReceipts(userId, folder.id, next);
  }

  Future<void> mergeFolders(
    String userId, {
    required Folder source,
    required Folder target,
  }) async {
    if (source.id == target.id) {
      throw Exception('Choose two different folders to merge.');
    }

    final targetReceiptSet = target.receiptIds.toSet();
    final sourceReceiptIds = source.receiptIds.toSet().toList();
    final sourceOnly = sourceReceiptIds.where((id) => !targetReceiptSet.contains(id)).toList();

    final merged = <String>{...target.receiptIds, ...source.receiptIds}.toList();
    final mergeEntry = {
      'mergeId': '${source.id}-${DateTime.now().millisecondsSinceEpoch}',
      'sourceFolderId': source.id,
      'sourceFolderName': source.name,
      'sourceFolderReceiptIds': sourceReceiptIds,
      'sourceOnlyReceiptIds': sourceOnly,
      'sourceIsAuto': source.isAuto,
      'sourceAutoType': source.autoType,
      'sourceAutoKey': source.autoKey,
      'mergedAt': Timestamp.now(),
    };

    final batch = _db.batch();
    final targetRef = _db.collection('users').doc(userId).collection('folders').doc(target.id);
    final sourceRef = _db.collection('users').doc(userId).collection('folders').doc(source.id);

    batch.update(targetRef, {
      'receiptIds': merged,
      'mergedSources': [...target.mergedSources.map((e) => e.toMap()), mergeEntry],
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.delete(sourceRef);
    await batch.commit();
  }

  Future<void> unmergeFolder(
    String userId, {
    required Folder target,
    required FolderMergeEntry mergeEntry,
  }) async {
    final sourceOnlySet = mergeEntry.sourceOnlyReceiptIds.toSet();
    final nextReceipts = target.receiptIds.where((id) => !sourceOnlySet.contains(id)).toList();

    final nextMerged = target.mergedSources
        .where((entry) => entry.mergeId != mergeEntry.mergeId)
        .map((entry) => entry.toMap())
        .toList();

    final batch = _db.batch();
    final targetRef = _db.collection('users').doc(userId).collection('folders').doc(target.id);
    final restoredRef = _db
        .collection('users')
        .doc(userId)
        .collection('folders')
        .doc(mergeEntry.sourceFolderId);

    batch.update(targetRef, {
      'receiptIds': nextReceipts,
      'mergedSources': nextMerged,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(restoredRef, {
      'userId': userId,
      'name': mergeEntry.sourceFolderName,
      'receiptIds': mergeEntry.sourceFolderReceiptIds.toSet().toList(),
      'isAuto': mergeEntry.sourceIsAuto ?? false,
      'autoType': mergeEntry.sourceAutoType,
      'autoKey': mergeEntry.sourceAutoKey,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  Future<void> syncAutoFolders(String userId, List<Folder> currentFolders, List<Receipt> receipts) async {
    final groups = _buildAutoGroups(receipts);
    final desired = {
      for (final group in groups) '${group.type}:${group.key}': group,
    };

    final currentAuto = currentFolders.where((f) => f.isAuto && f.autoType != null && f.autoKey != null).toList();
    final currentByKey = {
      for (final folder in currentAuto) '${folder.autoType}:${folder.autoKey}': folder,
    };

    final tasks = <Future<void>>[];

    for (final entry in desired.entries) {
      final existing = currentByKey[entry.key];
      final value = entry.value;

      if (existing == null) {
        tasks.add(_db.collection('users').doc(userId).collection('folders').add({
          'userId': userId,
          'name': value.name,
          'receiptIds': value.receiptIds,
          'isAuto': true,
          'autoType': value.type,
          'autoKey': value.key,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }).then((_) {}));
        continue;
      }

      final changedName = existing.name != value.name;
      final changedReceipts = !_sameIds(existing.receiptIds, value.receiptIds);
      if (changedName || changedReceipts) {
        tasks.add(_db.collection('users').doc(userId).collection('folders').doc(existing.id).update({
          'name': value.name,
          'receiptIds': value.receiptIds,
          'updatedAt': FieldValue.serverTimestamp(),
        }));
      }
    }

    for (final folder in currentAuto) {
      final composite = '${folder.autoType}:${folder.autoKey}';
      if (!desired.containsKey(composite)) {
        tasks.add(_db.collection('users').doc(userId).collection('folders').doc(folder.id).delete());
      }
    }

    if (tasks.isNotEmpty) {
      await Future.wait(tasks);
    }
  }

  Future<void> _updateFolderReceipts(String userId, String folderId, List<String> receiptIds) async {
    await _db.collection('users').doc(userId).collection('folders').doc(folderId).update({
      'receiptIds': receiptIds.toSet().toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  List<_AutoFolderGroup> _buildAutoGroups(List<Receipt> receipts) {
    final buckets = <String, _AutoFolderBucket>{};

    for (final receipt in receipts) {
      _addBucket(
        buckets,
        type: 'merchant',
        label: _cleanLabel(receipt.merchant?.canonicalName ?? receipt.merchant?.rawName),
        receiptId: receipt.id,
      );
    }

    return buckets.values
        .where((bucket) => bucket.receiptIds.length >= 2)
        .map((bucket) => _AutoFolderGroup(
              type: bucket.type,
              key: bucket.key,
              name: bucket.label,
              receiptIds: bucket.receiptIds.toList()..sort(),
            ))
        .toList()
      ..sort((a, b) => b.receiptIds.length.compareTo(a.receiptIds.length));
  }

  void _addBucket(
    Map<String, _AutoFolderBucket> buckets, {
    required String type,
    required String? label,
    required String receiptId,
  }) {
    if (label == null || label.trim().isEmpty) return;
    final key = _normalizeKey(label);
    if (key.isEmpty) return;

    final composite = '$type:$key';
    final bucket = buckets.putIfAbsent(
      composite,
      () => _AutoFolderBucket(type: type, key: key, label: label, receiptIds: <String>{}),
    );

    bucket.receiptIds.add(receiptId);
  }

  String _normalizeKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String? _cleanLabel(String? value) {
    if (value == null) return null;
    final cleaned = value.trim();
    if (cleaned.isEmpty) return null;
    return cleaned.length > 60 ? cleaned.substring(0, 60).trim() : cleaned;
  }

  bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final aSorted = [...a]..sort();
    final bSorted = [...b]..sort();
    for (var i = 0; i < aSorted.length; i++) {
      if (aSorted[i] != bSorted[i]) return false;
    }
    return true;
  }
}

class _AutoFolderBucket {
  _AutoFolderBucket({
    required this.type,
    required this.key,
    required this.label,
    required this.receiptIds,
  });

  final String type;
  final String key;
  final String label;
  final Set<String> receiptIds;
}

class _AutoFolderGroup {
  _AutoFolderGroup({
    required this.type,
    required this.key,
    required this.name,
    required this.receiptIds,
  });

  final String type;
  final String key;
  final String name;
  final List<String> receiptIds;
}
