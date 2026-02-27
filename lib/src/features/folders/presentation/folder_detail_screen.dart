import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/formatters.dart';
import '../../auth/data/auth_repository.dart';
import '../../receipts/data/receipt_repository.dart';
import '../../receipts/models/receipt.dart';
import '../data/folder_repository.dart';
import '../models/folder.dart';

class FolderDetailScreen extends ConsumerStatefulWidget {
  const FolderDetailScreen({
    super.key,
    required this.folderId,
  });

  final String folderId;

  @override
  ConsumerState<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends ConsumerState<FolderDetailScreen> {
  final _selectedReceiptIds = <String>{};

  Folder? _folderById(List<Folder> folders) {
    for (final folder in folders) {
      if (folder.id == widget.folderId) return folder;
    }
    return null;
  }

  Future<void> _rename(Folder folder) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    final controller = TextEditingController(text: folder.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename folder'),
          content: TextField(controller: controller),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
          ],
        );
      },
    );

    if (ok != true) return;
    await ref.read(folderRepositoryProvider).renameFolder(uid, folder.id, controller.text);
  }

  Future<void> _delete(Folder folder) async {
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
    await ref.read(folderRepositoryProvider).deleteFolder(uid, folder.id);
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/app/folders');
  }

  Future<void> _addReceipts(Folder folder, List<Receipt> allReceipts) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    final selected = <String>{};
    final candidates = allReceipts.where((receipt) => !folder.receiptIds.contains(receipt.id)).toList();
    if (candidates.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setLocalState) {
          return AlertDialog(
            title: const Text('Add receipts'),
            content: SizedBox(
              width: 420,
              child: ListView(
                shrinkWrap: true,
                children: candidates.take(60).map((receipt) {
                  final merchant = receipt.merchant?.canonicalName ??
                      receipt.merchant?.rawName ??
                      receipt.file.originalName;
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: selected.contains(receipt.id),
                    title: Text(merchant, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(formatCurrency(receipt.totalAmount)),
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
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Add')),
            ],
          );
        });
      },
    );

    if (ok != true || selected.isEmpty) return;
    await ref.read(folderRepositoryProvider).addReceipts(uid, folder, selected.toList());
  }

  Future<void> _removeSelected(Folder folder) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null || _selectedReceiptIds.isEmpty) return;

    await ref.read(folderRepositoryProvider).removeReceipts(uid, folder, _selectedReceiptIds.toList());
    setState(() => _selectedReceiptIds.clear());
  }

  Future<void> _exportCsv(Folder folder, List<Receipt> receiptsInFolder) async {
    if (receiptsInFolder.isEmpty) return;

    final rows = <String>['"Merchant","Date","Amount"'];
    var total = 0.0;

    for (final receipt in receiptsInFolder) {
      final merchant = receipt.merchant?.canonicalName ??
          receipt.merchant?.rawName ??
          receipt.extraction?.supplierName?.value?.toString() ??
          'Unknown';
      final date = receipt.date ?? '';
      final amount = receipt.totalAmount ?? 0;
      total += amount;
      rows.add('"${merchant.replaceAll('"', '""')}","$date","${amount.toStringAsFixed(2)}"');
    }

    rows.add('"Total","","${total.toStringAsFixed(2)}"');

    final csv = rows.join('\n');
    await SharePlus.instance.share(
      ShareParams(
        text: csv,
        subject: '${folder.name} receipts CSV',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foldersAsync = ref.watch(foldersStreamProvider);
    final receipts = ref.watch(receiptsStreamProvider).valueOrNull ?? const <Receipt>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Folder'),
      ),
      body: foldersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load folder: $err')),
        data: (folders) {
          final folder = _folderById(folders);
          if (folder == null) {
            return const Center(child: Text('Folder not found.'));
          }

          final receiptsInFolder = receipts
              .where((receipt) => folder.receiptIds.contains(receipt.id))
              .toList()
            ..sort((a, b) {
              final aDate = a.effectiveDate ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bDate = b.effectiveDate ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bDate.compareTo(aDate);
            });

          final total = receiptsInFolder.fold<double>(0, (sum, receipt) => sum + (receipt.totalAmount ?? 0));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              // Folder header card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.folder_rounded,
                              color: cs.primary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  folder.name,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 2),
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
                        ],
                      ),
                      const SizedBox(height: 16),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _ActionButton(
                              icon: Icons.edit_outlined,
                              label: 'Rename',
                              onTap: () => _rename(folder),
                            ),
                            const SizedBox(width: 8),
                            _ActionButton(
                              icon: Icons.add_rounded,
                              label: 'Add',
                              onTap: () => _addReceipts(folder, receipts),
                            ),
                            const SizedBox(width: 8),
                            _ActionButton(
                              icon: Icons.remove_circle_outline,
                              label: 'Remove (${_selectedReceiptIds.length})',
                              onTap: _selectedReceiptIds.isEmpty ? null : () => _removeSelected(folder),
                            ),
                            const SizedBox(width: 8),
                            _ActionButton(
                              icon: Icons.file_download_outlined,
                              label: 'CSV',
                              onTap: () => _exportCsv(folder, receiptsInFolder),
                            ),
                            const SizedBox(width: 8),
                            _ActionButton(
                              icon: Icons.delete_outline,
                              label: 'Delete',
                              onTap: () => _delete(folder),
                              destructive: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (folder.mergedSources.isNotEmpty) ...[
                const SizedBox(height: 4),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Merged sources (${folder.mergedSources.length})',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        ...folder.mergedSources.map((entry) {
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(entry.sourceFolderName),
                            subtitle: Text('${entry.sourceFolderReceiptIds.length} receipts'),
                            trailing: TextButton(
                              onPressed: () async {
                                final uid = ref.read(currentUserIdProvider);
                                if (uid == null) return;
                                await ref.read(folderRepositoryProvider).unmergeFolder(
                                      uid,
                                      target: folder,
                                      mergeEntry: entry,
                                    );
                              },
                              child: const Text('Unmerge'),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (receiptsInFolder.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 36,
                          color: cs.onSurface.withValues(alpha: 0.15),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No receipts in this folder',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...receiptsInFolder.map((receipt) {
                  final merchant = receipt.merchant?.canonicalName ??
                      receipt.merchant?.rawName ??
                      receipt.file.originalName;
                  final isSelected = _selectedReceiptIds.contains(receipt.id);
                  return Card(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedReceiptIds.remove(receipt.id);
                          } else {
                            _selectedReceiptIds.add(receipt.id);
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            Checkbox(
                              value: isSelected,
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedReceiptIds.add(receipt.id);
                                  } else {
                                    _selectedReceiptIds.remove(receipt.id);
                                  }
                                });
                              },
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    merchant,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '${formatDate(receipt.effectiveDate)} \u2022 ${formatCurrency(receipt.totalAmount)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: cs.onSurface.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => context.push('/app/receipt/${receipt.id}'),
                              icon: Icon(
                                Icons.open_in_new_outlined,
                                size: 20,
                                color: cs.onSurface.withValues(alpha: 0.4),
                              ),
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
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = destructive ? cs.error : cs.primary;
    final isDisabled = onTap == null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: isDisabled
                  ? cs.onSurface.withValues(alpha: 0.08)
                  : color.withValues(alpha: 0.15),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isDisabled
                    ? cs.onSurface.withValues(alpha: 0.25)
                    : color,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDisabled
                      ? cs.onSurface.withValues(alpha: 0.25)
                      : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
