import 'package:flutter/material.dart';
import 'package:wallet/database/database_helper.dart';
import 'package:wallet/models/category_model.dart';
import 'package:wallet/currency.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Trash Bin Page
// ─────────────────────────────────────────────────────────────────────────────
//
// Shows three tabs — Transactions, Accounts, and Categories — containing
// soft-deleted items.
//
// Features:
//   • View all trashed transactions, accounts, and categories grouped by
//     deletion date (transactions/accounts) or by category group
//     (categories).
//   • Restore individual items back to the live tables.
//   • Permanently delete individual items (no undo).
//   • Empty-trash action that wipes all tables at once.
//   • Live item-count badge shown in the drawer entry (via [TrashBinPage.count]).
// ─────────────────────────────────────────────────────────────────────────────

class TrashBinPage extends StatefulWidget {
  const TrashBinPage({super.key});

  @override
  State<TrashBinPage> createState() => _TrashBinPageState();
}

class _TrashBinPageState extends State<TrashBinPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  List<TrashedTransaction> _transactions = [];
  List<TrashedAccount> _accounts = [];
  List<TrashedCategory> _categories = [];
  CategoryRegistry _registry = CategoryRegistry.empty();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
        length: 3, vsync: this); // Transactions, Accounts, Categories
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final txs = await DatabaseHelper.instance.getTrashedTransactions();
    final accts = await DatabaseHelper.instance.getTrashedAccounts();
    final cats = await DatabaseHelper.instance.getTrashedCategories();
    final registry = await DatabaseHelper.instance.getCategoryRegistry();
    if (!mounted) return;
    setState(() {
      _transactions = txs;
      _accounts = accts;
      _categories = cats;
      _registry = registry;
      _loading = false;
    });
  }

  int get _totalCount =>
      _transactions.length + _accounts.length + _categories.length;

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _restoreTransaction(TrashedTransaction item, int trashId) async {
    await DatabaseHelper.instance.restoreTransaction(trashId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('\"${item.transaction.title}\" restored.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _load();
  }

  Future<void> _permanentDeleteTransaction(
      TrashedTransaction item, int trashId) async {
    final confirm = await _confirmDialog(
      title: 'Delete Forever?',
      itemName: item.transaction.title,
    );
    if (!confirm) return;
    await DatabaseHelper.instance.permanentlyDeleteTransaction(trashId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Transaction permanently deleted.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _load();
  }

  Future<void> _restoreAccount(TrashedAccount item, int trashId) async {
    await DatabaseHelper.instance.restoreAccount(trashId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('\"${item.account.name}\" restored.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _load();
  }

  Future<void> _permanentDeleteAccount(TrashedAccount item, int trashId) async {
    final confirm = await _confirmDialog(
      title: 'Delete Forever?',
      itemName: item.account.name,
    );
    if (!confirm) return;
    await DatabaseHelper.instance.permanentlyDeleteAccount(trashId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Account permanently deleted.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _load();
  }

  Future<void> _restoreCategory(TrashedCategory item, int trashId) async {
    await DatabaseHelper.instance.restoreCategory(trashId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('\"${item.category.name}\" restored.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _load();
  }

  Future<void> _permanentDeleteCategory(
      TrashedCategory item, int trashId) async {
    final confirm = await _confirmDialog(
      title: 'Delete Forever?',
      itemName: item.category.name,
    );
    if (!confirm) return;
    await DatabaseHelper.instance.permanentlyDeleteCategory(trashId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Category permanently deleted.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _load();
  }

  Future<void> _emptyTrash() async {
    if (_totalCount == 0) return;
    final confirm = await _confirmDialog(
      title: 'Empty Trash?',
      itemCount: _totalCount,
      confirmLabel: 'Empty Trash',
      isEmptyAll: true,
    );
    if (!confirm) return;
    await DatabaseHelper.instance.emptyTrash();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Trash emptied.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _load();
  }

  Future<bool> _confirmDialog({
    required String title,
    String? itemName,
    int? itemCount,
    String confirmLabel = 'Delete Forever',
    bool isEmptyAll = false,
  }) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // The default ColorScheme.error reads as a muted, desaturated pink in
    // dark mode. For the higher-stakes "Empty Trash" flow, use a punchier,
    // more saturated red instead so the warning lands harder.
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = isDark ? Colors.red.shade400 : cs.error;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DangerDialog(
        title: title,
        itemName: itemName,
        itemCount: itemCount,
        confirmLabel: confirmLabel,
        isEmptyAll: isEmptyAll,
        accentColor: accentColor,
      ),
    );
    return result ?? false;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Trash'),
            if (_totalCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$_totalCount',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_totalCount > 0)
            TextButton.icon(
              onPressed: _emptyTrash,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('Empty'),
              style: TextButton.styleFrom(
                foregroundColor: theme.brightness == Brightness.dark
                    ? Colors.red.shade400
                    : cs.error,
              ),
            ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.receipt_long_outlined, size: 16),
                  const SizedBox(width: 6),
                  const Text('Transactions'),
                  if (_transactions.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _CountChip(count: _transactions.length),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 16),
                  const SizedBox(width: 6),
                  const Text('Accounts'),
                  if (_accounts.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _CountChip(count: _accounts.length),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.category_outlined, size: 16),
                  const SizedBox(width: 6),
                  const Text('Categories'),
                  if (_categories.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _CountChip(count: _categories.length),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _TransactionsTab(
                        items: _transactions,
                        registry: _registry,
                        onRestore: _restoreTransaction,
                        onDelete: _permanentDeleteTransaction,
                      ),
                      _AccountsTab(
                        items: _accounts,
                        registry: _registry,
                        onRestore: _restoreAccount,
                        onDelete: _permanentDeleteAccount,
                      ),
                      _CategoriesTab(
                        items: _categories,
                        onRestore: _restoreCategory,
                        onDelete: _permanentDeleteCategory,
                      ),
                    ],
                  ),
                ),
                const _DeletionTimerBanner(),
              ],
            ),
    );
  }
}

// ── Count chip ────────────────────────────────────────────────────────────────

class _CountChip extends StatelessWidget {
  final int count;
  const _CountChip({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

// ── Transactions tab ──────────────────────────────────────────────────────────

/// Represents either a single non-transfer transaction or a paired
/// transfer_out + transfer_in displayed as one card.
class _TxRow {
  /// The "primary" trashed transaction (for non-transfers, the only one;
  /// for transfers, the transfer_out leg).
  final TrashedTransaction primary;

  /// For transfers only: the matching transfer_in leg.
  final TrashedTransaction? transferIn;

  const _TxRow(this.primary, {this.transferIn});

  bool get isTransfer =>
      transferIn != null ||
      primary.transaction.type == 'transfer_out' ||
      primary.transaction.type == 'transfer_in';
}

class _TransactionsTab extends StatelessWidget {
  final List<TrashedTransaction> items;
  final CategoryRegistry registry;
  final void Function(TrashedTransaction item, int trashId) onRestore;
  final void Function(TrashedTransaction item, int trashId) onDelete;

  const _TransactionsTab({
    required this.items,
    required this.registry,
    required this.onRestore,
    required this.onDelete,
  });

  /// Extracts the __ref:VALUE__ tag from a note string — the shared key
  /// that links a transfer_out and transfer_in leg.
  static String? _extractRef(String? note) {
    if (note == null) return null;
    final m = RegExp(r'__ref:([^_]+)__').firstMatch(note);
    return m?.group(1);
  }

  /// Pairs transfer_out + transfer_in rows into single [_TxRow] entries
  /// using the shared __ref:...__  tag in their notes.
  List<_TxRow> _buildRows(List<TrashedTransaction> flat) {
    final rows = <_TxRow>[];
    final usedIds = <int>{};

    for (final item in flat) {
      if (usedIds.contains(item.trashId)) continue;
      final tx = item.transaction;

      if (tx.type == 'transfer_out') {
        final ref = _extractRef(tx.note);
        TrashedTransaction? match;
        if (ref != null) {
          try {
            match = flat.firstWhere(
              (other) =>
                  !usedIds.contains(other.trashId) &&
                  other.transaction.type == 'transfer_in' &&
                  _extractRef(other.transaction.note) == ref,
            );
          } catch (_) {
            match = null;
          }
        }
        usedIds.add(item.trashId);
        if (match != null) {
          usedIds.add(match.trashId);
          rows.add(_TxRow(item, transferIn: match));
        } else {
          rows.add(_TxRow(item));
        }
      } else if (tx.type == 'transfer_in') {
        // Only reaches here if its out-leg was already consumed or missing.
        usedIds.add(item.trashId);
        rows.add(_TxRow(item));
      } else {
        usedIds.add(item.trashId);
        rows.add(_TxRow(item));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty)
      return const _EmptyState(label: 'No deleted transactions');

    final rows = _buildRows(items);

    final grouped = _groupByDate<_TxRow>(
      rows,
      (r) => r.primary.deletedAt,
    );

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: grouped.length,
      itemBuilder: (ctx, idx) {
        final entry = grouped[idx];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DateHeader(label: _formatSectionDate(entry.key)),
            ...entry.value.map((row) {
              if (row.transferIn != null) {
                return _TransferTile(
                  outItem: row.primary,
                  inItem: row.transferIn!,
                  onRestore: () {
                    onRestore(row.primary, row.primary.trashId);
                    onRestore(row.transferIn!, row.transferIn!.trashId);
                  },
                  onDelete: () {
                    onDelete(row.primary, row.primary.trashId);
                    onDelete(row.transferIn!, row.transferIn!.trashId);
                  },
                );
              }
              return _TransactionTile(
                item: row.primary,
                registry: registry,
                onRestore: () => onRestore(row.primary, row.primary.trashId),
                onDelete: () => onDelete(row.primary, row.primary.trashId),
              );
            }),
          ],
        );
      },
    );
  }
}

// ── Accounts tab ─────────────────────────────────────────────────────────────

class _AccountsTab extends StatelessWidget {
  final List<TrashedAccount> items;
  final CategoryRegistry registry;
  final void Function(TrashedAccount item, int trashId) onRestore;
  final void Function(TrashedAccount item, int trashId) onDelete;

  const _AccountsTab({
    required this.items,
    required this.registry,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _EmptyState(label: 'No deleted accounts');

    final grouped = _groupByDate<TrashedAccount>(
      items,
      (i) => i.deletedAt,
    );

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: grouped.length,
      itemBuilder: (ctx, idx) {
        final entry = grouped[idx];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DateHeader(label: _formatSectionDate(entry.key)),
            ...entry.value.map((item) => _AccountTile(
                  item: item,
                  registry: registry,
                  onRestore: () => onRestore(item, item.trashId),
                  onDelete: () => onDelete(item, item.trashId),
                )),
          ],
        );
      },
    );
  }
}

// ── Categories tab ───────────────────────────────────────────────────────────

class _CategoriesTab extends StatelessWidget {
  final List<TrashedCategory> items;
  final void Function(TrashedCategory item, int trashId) onRestore;
  final void Function(TrashedCategory item, int trashId) onDelete;

  const _CategoriesTab({
    required this.items,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _EmptyState(label: 'No deleted categories');

    // Build a flat, ordered list of (sectionLabel, items) pairs.
    // Transaction categories are split into Income / Expense / Transfer
    // sub-sections instead of one combined block.
    final List<(String, List<TrashedCategory>)> sections = [];

    void addSection(String label, List<TrashedCategory> slice) {
      if (slice.isNotEmpty) sections.add((label, slice));
    }

    addSection(
      'ACCOUNT TYPES',
      items
          .where((c) => c.category.groupType == kCategoryGroupAccountType)
          .toList(),
    );
    addSection(
      'ACCOUNT CATEGORIES',
      items
          .where((c) => c.category.groupType == kCategoryGroupAccountCategory)
          .toList(),
    );
    addSection(
      'INCOME CATEGORIES',
      items
          .where((c) =>
              c.category.groupType == kCategoryGroupTransactionCategory &&
              c.category.subType == kSubTypeIncome)
          .toList(),
    );
    addSection(
      'EXPENSE CATEGORIES',
      items
          .where((c) =>
              c.category.groupType == kCategoryGroupTransactionCategory &&
              c.category.subType == kSubTypeExpense)
          .toList(),
    );
    // Any remaining transaction categories (e.g. Transfer/system or unknown subType)
    final accounted = {kSubTypeIncome, kSubTypeExpense};
    addSection(
      'OTHER CATEGORIES',
      items
          .where((c) =>
              c.category.groupType == kCategoryGroupTransactionCategory &&
              !accounted.contains(c.category.subType))
          .toList(),
    );

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: sections.length,
      itemBuilder: (ctx, idx) {
        final (label, slice) = sections[idx];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DateHeader(label: label),
            ...slice.map((item) => _TrashedCategoryTile(
                  item: item,
                  onRestore: () => onRestore(item, item.trashId),
                  onDelete: () => onDelete(item, item.trashId),
                )),
          ],
        );
      },
    );
  }
}

// ── Trashed category tile ─────────────────────────────────────────────────────

class _TrashedCategoryTile extends StatelessWidget {
  final TrashedCategory item;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _TrashedCategoryTile({
    required this.item,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cat = item.category;

    // ignore: unused_local_variable
    Color catColor;
    try {
      final hex = cat.colorHex.replaceAll('#', '');
      catColor = Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      catColor = cs.primary;
    }

    final icon = kCategoryIcons[cat.icon] ?? Icons.label_outline;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            // Category icon — grayed out to indicate deleted state
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.outlineVariant.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: cs.outline, size: 20),
            ),
            const SizedBox(width: 12),

            // Name + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cat.name,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subTypeLabel(cat.subType),
                    style:
                        theme.textTheme.labelSmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Deleted ${_timeAgo(item.deletedAt)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.outlineVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

            _ActionMenu(onRestore: onRestore, onDelete: onDelete),
          ],
        ),
      ),
    );
  }

  String _subTypeLabel(String subType) {
    switch (subType) {
      case kSubTypeIncome:
        return 'Income';
      case kSubTypeExpense:
        return 'Expense';
      default:
        return subType.isEmpty ? '\u2014' : subType;
    }
  }
}

// ── Transaction tile ──────────────────────────────────────────────────────────

class _TransactionTile extends StatelessWidget {
  final TrashedTransaction item;
  final CategoryRegistry registry;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _TransactionTile({
    required this.item,
    required this.registry,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tx = item.transaction;

    final isIncome = tx.type == 'income';
    final isTransfer = tx.type == 'transfer_in' || tx.type == 'transfer_out';

    Color amountColor = isTransfer
        ? cs.secondary
        : isIncome
            ? const Color(0xFF16A34A)
            : Colors.red;
    final prefix = isIncome
        ? '+'
        : tx.type == 'transfer_in'
            ? '+'
            : '-';

    // Resolve icon via the live category registry (name → WalletCategory → iconData),
    // falling back to Icons.category for unknown/custom categories.
    final icon = registry.transactionCategoryIcon(tx.category);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            // Category icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: amountColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: amountColor, size: 20),
            ),
            const SizedBox(width: 12),

            // Title + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.title,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        tx.category,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.outline),
                      ),
                      if (item.accountName != null &&
                          item.accountName!.isNotEmpty) ...[
                        Text(' • ',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: cs.outlineVariant)),
                        Flexible(
                          child: Text(
                            item.accountName!,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: cs.outline),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Deleted ${_timeAgo(item.deletedAt)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.outlineVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

            // Amount
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '$prefix${currencySymbolNotifier.value}${tx.amount.toStringAsFixed(2)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: amountColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // Action buttons
            _ActionMenu(onRestore: onRestore, onDelete: onDelete),
          ],
        ),
      ),
    );
  }
}

// ── Transfer tile (paired out + in shown as one card) ─────────────────────────

class _TransferTile extends StatelessWidget {
  final TrashedTransaction outItem;
  final TrashedTransaction inItem;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _TransferTile({
    required this.outItem,
    required this.inItem,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    const blue = Color(0xFF2563EB);
    const blueBg = Color(0xFFDBEAFE);

    final fromAcc = outItem.accountName ?? '—';
    final toAcc = inItem.accountName ?? '—';
    final amount = outItem.transaction.amount;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            // Transfer icon — matches the rounded-square style of _TransactionTile
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: blueBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  const Icon(Icons.swap_horiz_rounded, color: blue, size: 20),
            ),
            const SizedBox(width: 12),

            // Title + accounts
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Transfer',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$fromAcc → $toAcc',
                    style:
                        theme.textTheme.labelSmall?.copyWith(color: cs.outline),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Deleted ${_timeAgo(outItem.deletedAt)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.outlineVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

            // Amount
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '± ${currencySymbolNotifier.value}${amount.toStringAsFixed(2)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            _ActionMenu(onRestore: onRestore, onDelete: onDelete),
          ],
        ),
      ),
    );
  }
}

// ── Account tile ──────────────────────────────────────────────────────────────

class _AccountTile extends StatelessWidget {
  final TrashedAccount item;
  final CategoryRegistry registry;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _AccountTile({
    required this.item,
    required this.registry,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final acct = item.account;

    // Use the account type's colour and icon from the registry snapshot.
    // Falls back gracefully if the type no longer exists.
    Color acctColor;
    try {
      final hex = acct.colorHex.replaceAll('#', '');
      acctColor = Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      acctColor = cs.primary;
    }

    // Resolve the icon via the account *type* name (same as accounts_page does).
    final typeIcon = registry.typeIcon(acct.type);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            // Account type icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: acctColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                typeIcon,
                color: acctColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),

            // Name + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    acct.name,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        acct.type,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.outline),
                      ),
                      Text(' • ',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.outlineVariant)),
                      Text(
                        acct.category,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Deleted ${_timeAgo(item.deletedAt)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.outlineVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

            // Balance (shown greyed out — it was the balance at deletion time)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${currencySymbolNotifier.value}${acct.balance.toStringAsFixed(2)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.outline,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            _ActionMenu(onRestore: onRestore, onDelete: onDelete),
          ],
        ),
      ),
    );
  }
}

// ── Deletion timer banner ─────────────────────────────────────────────────────
//
// Shows a notice explaining that items are auto-deleted after 30 days,
// with a countdown to the nearest upcoming deletion.

class _DeletionTimerBanner extends StatelessWidget {
  const _DeletionTimerBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // ignore: unused_local_variable
    final cs = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.30),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.timer_outlined,
            size: 18,
            color: Colors.orange.shade700,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Items in trash are permanently deleted after 30 days.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.orange.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Danger confirmation dialog ────────────────────────────────────────────────
//
// Shared dialog for both "Delete Forever" (single item) and "Empty Trash"
// (bulk) confirmations. Leads with an icon badge, a clear consequence
// statement, and a "this can't be undone" notice — styled to read as a
// genuine warning rather than a routine pop-up.

class _DangerDialog extends StatelessWidget {
  final String title;
  final String? itemName;
  final int? itemCount;
  final String confirmLabel;
  final bool isEmptyAll;
  final Color accentColor;

  const _DangerDialog({
    required this.title,
    required this.confirmLabel,
    required this.isEmptyAll,
    required this.accentColor,
    this.itemName,
    this.itemCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Dialog(
      backgroundColor: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon badge
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isEmptyAll
                    ? Icons.delete_sweep_rounded
                    : Icons.delete_forever_rounded,
                color: accentColor,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),

            // Body copy
            Text.rich(
              _buildBody(theme, cs),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),

            // "Can't be undone" pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: accentColor),
                  const SizedBox(width: 8),
                  Text(
                    'This action cannot be undone',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accentColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.onSurface,
                      side: BorderSide(color: cs.outlineVariant),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: cs.onError,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(
                      confirmLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TextSpan _buildBody(ThemeData theme, ColorScheme cs) {
    final base = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
      height: 1.4,
    );
    final strong = base?.copyWith(
      color: cs.onSurface,
      fontWeight: FontWeight.w700,
    );

    if (isEmptyAll) {
      final count = itemCount ?? 0;
      return TextSpan(style: base, children: [
        const TextSpan(text: 'All '),
        TextSpan(text: '$count item${count == 1 ? '' : 's'}', style: strong),
        const TextSpan(text: ' in your trash will be permanently erased.'),
      ]);
    }

    return TextSpan(style: base, children: [
      const TextSpan(text: '"'),
      TextSpan(text: itemName ?? 'This item', style: strong),
      const TextSpan(text: '" will be permanently erased.'),
    ]);
  }
}

// ── Shared action pop-up menu ─────────────────────────────────────────────────

class _ActionMenu extends StatelessWidget {
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _ActionMenu({required this.onRestore, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_TrashAction>(
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (action) {
        if (action == _TrashAction.restore) {
          onRestore();
        } else {
          onDelete();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _TrashAction.restore,
          child: Row(
            children: [
              Icon(Icons.restore, size: 18, color: Colors.green),
              SizedBox(width: 10),
              Text('Restore'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: _TrashAction.delete,
          child: Row(
            children: [
              Icon(Icons.delete_forever, size: 18, color: Colors.red),
              SizedBox(width: 10),
              Text('Delete Forever', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }
}

enum _TrashAction { restore, delete }

// ── Date section header ────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  final String label;
  const _DateHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String label;
  const _EmptyState({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.delete_outline_rounded,
                size: 44,
                color: cs.outline,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Items you delete will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Groups a list by the calendar date portion of an ISO-8601 timestamp.
List<MapEntry<String, List<T>>> _groupByDate<T>(
  List<T> items,
  String Function(T) getTimestamp,
) {
  final map = <String, List<T>>{};
  for (final item in items) {
    final key = getTimestamp(item).substring(0, 10); // YYYY-MM-DD
    map.putIfAbsent(key, () => []).add(item);
  }
  final sorted = map.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
  return sorted;
}

/// Formats a YYYY-MM-DD section key into a human-readable label.
String _formatSectionDate(String ymd) {
  final parts = ymd.split('-');
  if (parts.length < 3) return ymd;
  final dt = DateTime.tryParse(ymd) ?? DateTime.now();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(dt.year, dt.month, dt.day);
  if (date == today) return 'TODAY';
  if (date == today.subtract(const Duration(days: 1))) return 'YESTERDAY';
  const months = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${months[dt.month]} ${dt.day}, ${dt.year}'.toUpperCase();
}

/// Simple relative-time helper for "Deleted X ago" labels.
String _timeAgo(String iso) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
  return '${(diff.inDays / 365).floor()}y ago';
}
