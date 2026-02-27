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
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (value) => setState(() => _search = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search folders...',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _openCreateFolderDialog(receipts),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('New'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _syncingAutoFolders ? null : () => _syncAutoFolders(folders, receipts),
              icon: const Icon(Icons.auto_awesome),
              label: Text(_syncingAutoFolders ? 'Syncing...' : 'Sync auto folders'),
            ),
            const SizedBox(height: 12),
            if (visibleFolders.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No folders yet. Create one and group your receipts.'),
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
                  child: ListTile(
                    onTap: () => context.push('/app/folders/${folder.id}'),
                    title: Text(folder.name),
                    subtitle: Text('${folder.receiptIds.length} receipts • ${formatCurrency(total)}'),
                    trailing: PopupMenuButton<String>(
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
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}
