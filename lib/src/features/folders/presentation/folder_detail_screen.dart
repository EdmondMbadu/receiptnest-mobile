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
  const FolderDetailScreen({super.key, required this.folderId});

  final String folderId;

  @override
  ConsumerState<FolderDetailScreen> createState() =>
      _FolderDetailScreenState();
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: folder.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: isDark ? const Color(0xFF1A1A28) : Colors.white,
          title: const Text('Rename collection'),
          content: TextField(controller: controller),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;
    await ref
        .read(folderRepositoryProvider)
        .renameFolder(uid, folder.id, controller.text);
  }

  Future<void> _delete(Folder folder) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: isDark ? const Color(0xFF1A1A28) : Colors.white,
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.warning_amber_rounded,
                    size: 20, color: cs.error),
              ),
              const SizedBox(width: 12),
              const Text('Delete collection'),
            ],
          ),
          content: Text('Delete "${folder.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
              ),
              child: const Text('Delete'),
            ),
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
    final candidates = allReceipts
        .where((receipt) => !folder.receiptIds.contains(receipt.id))
        .toList();
    if (candidates.isEmpty) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor:
                  isDark ? const Color(0xFF1A1A28) : Colors.white,
              title: const Text('Add receipts'),
              content: SizedBox(
                width: 420,
                child: ListView(
                  shrinkWrap: true,
                  children: candidates.take(60).map((receipt) {
                    final merchant =
                        receipt.merchant?.canonicalName ??
                        receipt.merchant?.rawName ??
                        receipt.file.originalName;
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: selected.contains(receipt.id),
                      title: Text(
                        merchant,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        formatCurrency(receipt.effectiveTotalAmount),
                      ),
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
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true || selected.isEmpty) return;
    await ref
        .read(folderRepositoryProvider)
        .addReceipts(uid, folder, selected.toList());
  }

  Future<void> _removeSelected(Folder folder) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null || _selectedReceiptIds.isEmpty) return;

    await ref
        .read(folderRepositoryProvider)
        .removeReceipts(uid, folder, _selectedReceiptIds.toList());
    setState(() => _selectedReceiptIds.clear());
  }

  Future<void> _exportCsv(
      Folder folder, List<Receipt> receiptsInFolder) async {
    if (receiptsInFolder.isEmpty) return;

    final rows = <String>['"Merchant","Date","Amount"'];
    var total = 0.0;

    for (final receipt in receiptsInFolder) {
      final merchant =
          receipt.merchant?.canonicalName ??
          receipt.merchant?.rawName ??
          receipt.extraction?.supplierName?.value?.toString() ??
          'Unknown';
      final date = receipt.date ?? '';
      final amount = receipt.effectiveTotalAmount ?? 0;
      total += amount;
      rows.add(
        '"${merchant.replaceAll('"', '""')}","$date","${amount.toStringAsFixed(2)}"',
      );
    }

    rows.add('"Total","","${total.toStringAsFixed(2)}"');

    final csv = rows.join('\n');
    await SharePlus.instance.share(
      ShareParams(text: csv, subject: '${folder.name} receipts CSV'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foldersAsync = ref.watch(foldersStreamProvider);
    final receipts =
        ref.watch(receiptsStreamProvider).valueOrNull ?? const <Receipt>[];

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D0D14) : const Color(0xFFF6F7F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Collection'),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
      ),
      body: foldersAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: cs.primary,
          ),
        ),
        error: (err, _) =>
            Center(child: Text('Failed to load collection: $err')),
        data: (folders) {
          final folder = _folderById(folders);
          if (folder == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_off_outlined,
                      size: 48,
                      color: cs.onSurface.withValues(alpha: 0.15)),
                  const SizedBox(height: 12),
                  Text(
                    'Collection not found',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            );
          }

          final receiptsInFolder = receipts
              .where(
                  (receipt) => folder.receiptIds.contains(receipt.id))
              .toList()
            ..sort((a, b) {
              final aDate = a.effectiveDate ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              final bDate = b.effectiveDate ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              return bDate.compareTo(aDate);
            });

          final total = receiptsInFolder.fold<double>(
            0,
            (sum, receipt) =>
                sum + (receipt.effectiveTotalAmount ?? 0),
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              // ── Folder header card ──
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF151520)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.grey.shade200,
                  ),
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: 0.04),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                cs.primary
                                    .withValues(alpha: 0.15),
                                cs.primary
                                    .withValues(alpha: 0.05),
                              ],
                            ),
                            borderRadius:
                                BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.folder_rounded,
                            color: cs.primary,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                folder.name,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${folder.receiptIds.length} receipts \u2022 ${formatCurrency(total)}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: cs.onSurface
                                      .withValues(alpha: 0.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
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
                            onTap: () =>
                                _addReceipts(folder, receipts),
                          ),
                          const SizedBox(width: 8),
                          _ActionButton(
                            icon: Icons.remove_circle_outline,
                            label:
                                'Remove (${_selectedReceiptIds.length})',
                            onTap: _selectedReceiptIds.isEmpty
                                ? null
                                : () =>
                                    _removeSelected(folder),
                          ),
                          const SizedBox(width: 8),
                          _ActionButton(
                            icon:
                                Icons.file_download_outlined,
                            label: 'CSV',
                            onTap: () => _exportCsv(
                                folder, receiptsInFolder),
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

              // ── Merged sources ──
              if (folder.mergedSources.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF151520)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark
                          ? Colors.white
                              .withValues(alpha: 0.06)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Colors.orange
                                  .withValues(alpha: 0.1),
                              borderRadius:
                                  BorderRadius.circular(8),
                            ),
                            child: Icon(
                                Icons.merge_rounded,
                                size: 16,
                                color: Colors.orange.shade700),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Merged sources (${folder.mergedSources.length})',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...folder.mergedSources.map((entry) {
                        return Padding(
                          padding:
                              const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  children: [
                                    Text(
                                      entry.sourceFolderName,
                                      style: TextStyle(
                                        fontWeight:
                                            FontWeight.w600,
                                        fontSize: 14,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    Text(
                                      '${entry.sourceFolderReceiptIds.length} receipts',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurface
                                            .withValues(
                                                alpha: 0.4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  final uid = ref.read(
                                      currentUserIdProvider);
                                  if (uid == null) return;
                                  await ref
                                      .read(
                                          folderRepositoryProvider)
                                      .unmergeFolder(
                                        uid,
                                        target: folder,
                                        mergeEntry: entry,
                                      );
                                },
                                style: TextButton.styleFrom(
                                  textStyle:
                                      const TextStyle(
                                    fontSize: 13,
                                    fontWeight:
                                        FontWeight.w600,
                                  ),
                                ),
                                child:
                                    const Text('Unmerge'),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // ── Receipt list ──
              if (receiptsInFolder.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF151520)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark
                          ? Colors.white
                              .withValues(alpha: 0.06)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: cs.primary
                              .withValues(alpha: 0.08),
                          borderRadius:
                              BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.receipt_long_outlined,
                          size: 24,
                          color: cs.onSurface
                              .withValues(alpha: 0.2),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No receipts in this collection',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface
                              .withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...receiptsInFolder.map((receipt) {
                  final merchant =
                      receipt.merchant?.canonicalName ??
                      receipt.merchant?.rawName ??
                      receipt.file.originalName;
                  final isSelected =
                      _selectedReceiptIds.contains(receipt.id);

                  // Generate initials
                  final words = merchant.trim().split(RegExp(r'\s+'));
                  final initials = words.length >= 2
                      ? '${words[0][0]}${words[1][0]}'.toUpperCase()
                      : merchant.substring(0, merchant.length.clamp(0, 2)).toUpperCase();

                  const avatarColors = [
                    Color(0xFF6366F1),
                    Color(0xFF8B5CF6),
                    Color(0xFFEC4899),
                    Color(0xFFF59E0B),
                    Color(0xFF10B981),
                    Color(0xFF3B82F6),
                    Color(0xFFEF4444),
                    Color(0xFF14B8A6),
                  ];
                  final avatarColor = avatarColors[
                      merchant.hashCode.abs() % avatarColors.length];

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF151520)
                            : Colors.white,
                        borderRadius:
                            BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? cs.primary
                                  .withValues(alpha: 0.3)
                              : (isDark
                                  ? Colors.white
                                      .withValues(
                                          alpha: 0.06)
                                  : Colors.grey.shade200),
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedReceiptIds
                                    .remove(receipt.id);
                              } else {
                                _selectedReceiptIds
                                    .add(receipt.id);
                              }
                            });
                          },
                          borderRadius:
                              BorderRadius.circular(16),
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: avatarColor
                                        .withValues(
                                            alpha: 0.12),
                                    borderRadius:
                                        BorderRadius
                                            .circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      initials,
                                      style: TextStyle(
                                        color: avatarColor,
                                        fontWeight:
                                            FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                    children: [
                                      Text(
                                        merchant,
                                        style: TextStyle(
                                          fontWeight:
                                              FontWeight
                                                  .w600,
                                          fontSize: 14,
                                          color: cs
                                              .onSurface,
                                        ),
                                      ),
                                      const SizedBox(
                                          height: 2),
                                      Text(
                                        '${formatDate(receipt.effectiveDate)} \u2022 ${formatCurrency(receipt.effectiveTotalAmount)}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: cs
                                              .onSurface
                                              .withValues(
                                                  alpha:
                                                      0.45),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons
                                        .check_circle_rounded,
                                    size: 22,
                                    color: cs.primary,
                                  ),
                                const SizedBox(width: 4),
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: cs.primary
                                        .withValues(
                                            alpha: 0.06),
                                    borderRadius:
                                        BorderRadius
                                            .circular(8),
                                  ),
                                  child: IconButton(
                                    onPressed: () =>
                                        context.push(
                                            '/app/receipt/${receipt.id}'),
                                    icon: Icon(
                                      Icons
                                          .open_in_new_outlined,
                                      size: 16,
                                      color: cs.onSurface
                                          .withValues(
                                              alpha:
                                                  0.4),
                                    ),
                                    padding:
                                        EdgeInsets.zero,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = destructive ? cs.error : cs.primary;
    final isDisabled = onTap == null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDisabled
                ? Colors.transparent
                : color.withValues(alpha: 0.06),
            border: Border.all(
              color: isDisabled
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.grey.shade200)
                  : color.withValues(alpha: 0.15),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isDisabled
                    ? cs.onSurface.withValues(alpha: 0.2)
                    : color,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDisabled
                      ? cs.onSurface.withValues(alpha: 0.2)
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
