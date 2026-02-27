import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../auth/data/auth_repository.dart';
import '../../receipts/data/receipt_repository.dart';
import '../../receipts/models/receipt.dart';
import '../data/folder_repository.dart';
import '../models/folder.dart';

class FoldersScreen extends ConsumerStatefulWidget {
  const FoldersScreen({super.key});

  @override
  ConsumerState<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends ConsumerState<FoldersScreen> {
  bool _syncingAutoFolders = false;
  String _search = '';

  Future<void> _openCreateFolderDialog(List<Receipt> receipts) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    final nameController = TextEditingController();
    final selected = <String>{};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Create folder'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Folder name'),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: receipts.take(30).map((receipt) {
                          final merchant = receipt.merchant?.canonicalName ??
                              receipt.merchant?.rawName ??
                              receipt.file.originalName;
                          return CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(merchant, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(formatCurrency(receipt.totalAmount)),
                            value: selected.contains(receipt.id),
                            onChanged: (value) {
                              setLocalState(() {
                                if (value == true) {
                                  selected.add(receipt.id);
                                } else {
                                  selected.remove(receipt.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Create')),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    try {
      await ref.read(folderRepositoryProvider).createFolder(
            uid,
            nameController.text,
            selected.toList(),
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create folder: $e')),
      );
    }
  }

  Future<void> _syncAutoFolders(List<Folder> folders, List<Receipt> receipts) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null || _syncingAutoFolders) return;

    setState(() => _syncingAutoFolders = true);
    try {
      await ref.read(folderRepositoryProvider).syncAutoFolders(uid, folders, receipts);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auto folders synced.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to sync auto folders: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _syncingAutoFolders = false);
      }
    }
  }

  Future<void> _renameFolder(Folder folder) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    final controller = TextEditingController(text: folder.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename folder'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Folder name'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await ref.read(folderRepositoryProvider).renameFolder(uid, folder.id, controller.text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to rename folder: $e')),
      );
    }
  }

  Future<void> _deleteFolder(Folder folder) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete folder'),
          content: Text('Delete "${folder.name}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await ref.read(folderRepositoryProvider).deleteFolder(uid, folder.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete folder: $e')),
      );
    }
  }

  Future<void> _mergeFolder(Folder source, List<Folder> folders) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    final options = folders.where((f) => f.id != source.id).toList();
    if (options.isEmpty) return;

    Folder target = options.first;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setLocalState) {
          return AlertDialog(
            title: const Text('Merge folders'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Move all receipts from "${source.name}" into:'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: target.id,
                  items: options
                      .map((folder) => DropdownMenuItem(value: folder.id, child: Text(folder.name)))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setLocalState(() {
                      target = options.firstWhere((folder) => folder.id == value);
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Merge')),
            ],
          );
        });
      },
    );

    if (ok != true) return;

    try {
      await ref.read(folderRepositoryProvider).mergeFolders(
            uid,
            source: source,
            target: target,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to merge folders: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foldersAsync = ref.watch(foldersStreamProvider);
    final receipts = ref.watch(receiptsStreamProvider).valueOrNull ?? const <Receipt>[];

    return foldersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Failed to load folders: $err')),
      data: (folders) {
        final receiptMap = {for (final receipt in receipts) receipt.id: receipt};

        final visibleFolders = folders.where((folder) {
          if (_search.trim().isEmpty) return true;
          final q = _search.toLowerCase();
          return folder.name.toLowerCase().contains(q) ||
              (folder.autoType ?? '').toLowerCase().contains(q);
        }).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (value) => setState(() => _search = value),
                    decoration: InputDecoration(
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                      hintText: 'Search folders...',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _openCreateFolderDialog(receipts),
                  icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                  label: const Text('New'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _syncingAutoFolders ? null : () => _syncAutoFolders(folders, receipts),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(_syncingAutoFolders ? 'Syncing...' : 'Sync auto folders'),
            ),
            const SizedBox(height: 16),
            if (visibleFolders.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 40,
                        color: cs.onSurface.withValues(alpha: 0.15),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No folders yet',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Create one to group your receipts',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.35),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...visibleFolders.map((folder) {
                final receiptsInFolder = folder.receiptIds
                    .map((id) => receiptMap[id])
                    .whereType<Receipt>()
                    .toList();
                final total = receiptsInFolder.fold<double>(0, (sum, r) => sum + (r.totalAmount ?? 0));

                return Card(
                  child: InkWell(
                    onTap: () => context.push('/app/folders/${folder.id}'),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              folder.autoType != null
                                  ? Icons.auto_awesome_rounded
                                  : Icons.folder_rounded,
                              color: cs.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  folder.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${folder.receiptIds.length} receipts \u2022 ${formatCurrency(total)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: cs.onSurface.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert_rounded,
                              color: cs.onSurface.withValues(alpha: 0.4),
                              size: 20,
                            ),
                            onSelected: (value) {
                              switch (value) {
                                case 'rename':
                                  _renameFolder(folder);
                                  break;
                                case 'merge':
                                  _mergeFolder(folder, folders);
                                  break;
                                case 'delete':
                                  _deleteFolder(folder);
                                  break;
                              }
                            },
                            itemBuilder: (context) {
                              return const [
                                PopupMenuItem(value: 'rename', child: Text('Rename')),
                                PopupMenuItem(value: 'merge', child: Text('Merge')),
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ];
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}
