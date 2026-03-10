import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../auth/data/auth_repository.dart';
import '../../receipts/data/receipt_repository.dart';
import '../../receipts/models/category.dart';
import '../../receipts/models/receipt.dart';
import '../data/folder_repository.dart';
import '../models/folder.dart';

class FoldersScreen extends ConsumerStatefulWidget {
  const FoldersScreen({super.key});

  @override
  ConsumerState<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends ConsumerState<FoldersScreen>
    with SingleTickerProviderStateMixin {
  bool _syncingAutoFolders = false;
  String _search = '';
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Folder CRUD helpers ──

  Future<void> _openCreateFolderDialog(List<Receipt> receipts) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    final nameController = TextEditingController();
    final selected = <String>{};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor:
                  isDark ? const Color(0xFF1A1A28) : Colors.white,
              title: const Text('Create folder'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Folder name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: receipts.take(30).map((receipt) {
                          final merchant =
                              receipt.merchant?.canonicalName ??
                              receipt.merchant?.rawName ??
                              receipt.file.originalName;
                          return CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              merchant,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              formatCurrency(receipt.effectiveTotalAmount),
                            ),
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
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    try {
      await ref
          .read(folderRepositoryProvider)
          .createFolder(uid, nameController.text, selected.toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to create folder: $e')));
    }
  }

  Future<void> _syncAutoFolders(
    List<Folder> folders,
    List<Receipt> receipts,
  ) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null || _syncingAutoFolders) return;

    setState(() => _syncingAutoFolders = true);
    try {
      await ref
          .read(folderRepositoryProvider)
          .syncAutoFolders(uid, folders, receipts);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Auto folders synced.')));
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
          title: const Text('Rename folder'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Folder name'),
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
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await ref
          .read(folderRepositoryProvider)
          .renameFolder(uid, folder.id, controller.text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to rename folder: $e')));
    }
  }

  Future<void> _deleteFolder(Folder folder) async {
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
              const Text('Delete folder'),
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

    try {
      await ref.read(folderRepositoryProvider).deleteFolder(uid, folder.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to delete folder: $e')));
    }
  }

  Future<void> _mergeFolder(Folder source, List<Folder> folders) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    final options = folders.where((f) => f.id != source.id).toList();
    if (options.isEmpty) return;

    Folder target = options.first;
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
                        .map(
                          (folder) => DropdownMenuItem(
                            value: folder.id,
                            child: Text(folder.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setLocalState(() {
                        target = options.firstWhere(
                          (folder) => folder.id == value,
                        );
                      });
                    },
                  ),
                ],
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
                  child: const Text('Merge'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;

    try {
      await ref
          .read(folderRepositoryProvider)
          .mergeFolders(uid, source: source, target: target);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to merge folders: $e')));
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foldersAsync = ref.watch(foldersStreamProvider);
    final receipts =
        ref.watch(receiptsStreamProvider).valueOrNull ?? const <Receipt>[];

    return Column(
      children: [
        // ── Tab bar ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF151520) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: isDark ? const Color(0xFF252538) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.all(3),
              dividerColor: Colors.transparent,
              labelColor: cs.onSurface,
              unselectedLabelColor: cs.onSurface.withValues(alpha: 0.4),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13.5,
              ),
              tabs: const [
                Tab(text: 'Categories'),
                Tab(text: 'My Folders'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Tab views ──
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _CategoriesTab(receipts: receipts),
              _MyFoldersTab(
                foldersAsync: foldersAsync,
                receipts: receipts,
                search: _search,
                onSearchChanged: (v) => setState(() => _search = v),
                syncingAutoFolders: _syncingAutoFolders,
                onCreateFolder: () => _openCreateFolderDialog(receipts),
                onSyncAutoFolders: (folders) =>
                    _syncAutoFolders(folders, receipts),
                onRenameFolder: _renameFolder,
                onDeleteFolder: _deleteFolder,
                onMergeFolder: _mergeFolder,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Categories Tab
// ────────────────────────────────────────────────────────────────────────────

class _CategoriesTab extends StatelessWidget {
  const _CategoriesTab({required this.receipts});

  final List<Receipt> receipts;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final byCategory = <String, List<Receipt>>{};
    for (final receipt in receipts) {
      final catId = receipt.category?.id ?? 'other';
      byCategory.putIfAbsent(catId, () => []).add(receipt);
    }

    final entries = defaultCategories.map((cat) {
      final list = byCategory[cat.id] ?? [];
      final total = list.fold<double>(
          0, (sum, r) => sum + (r.effectiveTotalAmount ?? 0));
      return _CategoryEntry(category: cat, receipts: list, total: total);
    }).where((e) => e.receipts.isNotEmpty).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.category_outlined,
                size: 28,
                color: cs.onSurface.withValues(alpha: 0.25),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No categorized receipts yet',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Upload receipts to see categories',
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      );
    }

    final grandTotal = entries.fold<double>(0, (s, e) => s + e.total);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        // ── Summary card ──
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF151520) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entries.length} categories',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatCurrency(grandTotal),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${receipts.length} receipts',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Category cards ──
        ...entries.map((entry) {
          final pct =
              grandTotal > 0 ? (entry.total / grandTotal * 100).round() : 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF151520) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.grey.shade200,
                ),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () =>
                      context.push('/app/categories/${entry.category.id}'),
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Text(
                              entry.category.icon,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.category.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    '${entry.receipts.length} receipts',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: cs.onSurface
                                          .withValues(alpha: 0.45),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6),
                                    child: Text(
                                      '\u00B7',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: cs.onSurface
                                            .withValues(alpha: 0.2),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '$pct%',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: cs.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatCurrency(entry.total),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: cs.onSurface,
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
  }
}

class _CategoryEntry {
  const _CategoryEntry({
    required this.category,
    required this.receipts,
    required this.total,
  });

  final ExpenseCategory category;
  final List<Receipt> receipts;
  final double total;
}

// ────────────────────────────────────────────────────────────────────────────
// My Folders Tab
// ────────────────────────────────────────────────────────────────────────────

class _MyFoldersTab extends StatelessWidget {
  const _MyFoldersTab({
    required this.foldersAsync,
    required this.receipts,
    required this.search,
    required this.onSearchChanged,
    required this.syncingAutoFolders,
    required this.onCreateFolder,
    required this.onSyncAutoFolders,
    required this.onRenameFolder,
    required this.onDeleteFolder,
    required this.onMergeFolder,
  });

  final AsyncValue<List<Folder>> foldersAsync;
  final List<Receipt> receipts;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final bool syncingAutoFolders;
  final VoidCallback onCreateFolder;
  final void Function(List<Folder>) onSyncAutoFolders;
  final void Function(Folder) onRenameFolder;
  final void Function(Folder) onDeleteFolder;
  final void Function(Folder, List<Folder>) onMergeFolder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return foldersAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: cs.primary,
        ),
      ),
      error: (err, _) => Center(child: Text('Failed to load folders: $err')),
      data: (folders) {
        final receiptMap = {
          for (final receipt in receipts) receipt.id: receipt,
        };

        final visibleFolders = folders.where((folder) {
          if (search.trim().isEmpty) return true;
          final q = search.toLowerCase();
          return folder.name.toLowerCase().contains(q) ||
              (folder.autoType ?? '').toLowerCase().contains(q);
        }).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            // ── Search + New button ──
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF151520) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: TextField(
                      onChanged: onSearchChanged,
                      decoration: InputDecoration(
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: cs.onSurface.withValues(alpha: 0.35),
                          size: 20,
                        ),
                        hintText: 'Search folders...',
                        hintStyle: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.3),
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: onCreateFolder,
                    icon:
                        const Icon(Icons.create_new_folder_outlined, size: 20),
                    label: const Text('New'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Sync auto folders (merchant-based) ──
            SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                onPressed: syncingAutoFolders
                    ? null
                    : () => onSyncAutoFolders(folders),
                icon: Icon(
                  syncingAutoFolders
                      ? Icons.hourglass_top_rounded
                      : Icons.auto_awesome_rounded,
                  size: 18,
                ),
                label: Text(
                  syncingAutoFolders
                      ? 'Syncing...'
                      : 'Group by merchant',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.grey.shade300,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // ── Folder list ──
            if (visibleFolders.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF151520) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.grey.shade200,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.folder_outlined,
                        size: 28,
                        color: cs.onSurface.withValues(alpha: 0.25),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'No folders yet',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Create one to group your receipts',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.3),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...visibleFolders.map((folder) {
                final receiptsInFolder = folder.receiptIds
                    .map((id) => receiptMap[id])
                    .whereType<Receipt>()
                    .toList();
                final total = receiptsInFolder.fold<double>(
                  0,
                  (sum, r) => sum + (r.effectiveTotalAmount ?? 0),
                );

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color:
                          isDark ? const Color(0xFF151520) : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.grey.shade200,
                      ),
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                color:
                                    Colors.black.withValues(alpha: 0.03),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              ),
                            ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () =>
                            context.push('/app/folders/${folder.id}'),
                        borderRadius: BorderRadius.circular(18),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: folder.autoType != null
                                        ? [
                                            Colors.amber
                                                .withValues(alpha: 0.15),
                                            Colors.orange
                                                .withValues(alpha: 0.05),
                                          ]
                                        : [
                                            cs.primary
                                                .withValues(alpha: 0.15),
                                            cs.primary
                                                .withValues(alpha: 0.05),
                                          ],
                                  ),
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  folder.autoType != null
                                      ? Icons.store_rounded
                                      : Icons.folder_rounded,
                                  color: folder.autoType != null
                                      ? Colors.amber.shade700
                                      : cs.primary,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      folder.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${folder.receiptIds.length} receipts \u2022 ${formatCurrency(total)}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: cs.onSurface
                                            .withValues(alpha: 0.45),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.more_vert_rounded,
                                  color: cs.onSurface
                                      .withValues(alpha: 0.35),
                                  size: 20,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                                onSelected: (value) {
                                  switch (value) {
                                    case 'rename':
                                      onRenameFolder(folder);
                                      break;
                                    case 'merge':
                                      onMergeFolder(folder, folders);
                                      break;
                                    case 'delete':
                                      onDeleteFolder(folder);
                                      break;
                                  }
                                },
                                itemBuilder: (context) {
                                  return const [
                                    PopupMenuItem(
                                      value: 'rename',
                                      child: Text('Rename'),
                                    ),
                                    PopupMenuItem(
                                      value: 'merge',
                                      child: Text('Merge'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete'),
                                    ),
                                  ];
                                },
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
    );
  }
}
