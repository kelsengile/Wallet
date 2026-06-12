import 'package:flutter/material.dart';
import 'package:wallet/database/database_helper.dart';
import 'package:wallet/models/transaction_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Trash Bin Page
// ─────────────────────────────────────────────────────────────────────────────
//
// Shows two tabs — Transactions and Accounts — containing soft-deleted items.
//
// Features:
//   • View all trashed transactions and accounts grouped by deletion date.
//   • Restore individual items back to the live tables.
//   • Permanently delete individual items (no undo).
//   • Empty-trash action that wipes both tables at once.
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
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
    if (!mounted) return;
    setState(() {
      _transactions = txs;
      _accounts = accts;
      _loading = false;
    });
  }

  int get _totalCount => _transactions.length + _accounts.length;

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
      title: 'Delete Permanently?',
      body:
          '"${item.transaction.title}" will be gone forever. This cannot be undone.',
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
      title: 'Delete Permanently?',
      body:
          '"${item.account.name}" will be gone forever. This cannot be undone.',
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

  Future<void> _emptyTrash() async {
    if (_totalCount == 0) return;
    final confirm = await _confirmDialog(
      title: 'Empty Trash?',
      body:
          'All $_totalCount item${_totalCount == 1 ? '' : 's'} will be permanently deleted. This cannot be undone.',
      confirmLabel: 'Empty Trash',
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
    required String body,
    String confirmLabel = 'Delete',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
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
              style: TextButton.styleFrom(foregroundColor: Colors.red),
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
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _TransactionsTab(
                  items: _transactions,
                  onRestore: _restoreTransaction,
                  onDelete: _permanentDeleteTransaction,
                ),
                _AccountsTab(
                  items: _accounts,
                  onRestore: _restoreAccount,
                  onDelete: _permanentDeleteAccount,
                ),
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

class _TransactionsTab extends StatelessWidget {
  final List<TrashedTransaction> items;
  final void Function(TrashedTransaction item, int trashId) onRestore;
  final void Function(TrashedTransaction item, int trashId) onDelete;

  const _TransactionsTab({
    required this.items,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty)
      return const _EmptyState(label: 'No deleted transactions');

    final grouped = _groupByDate<TrashedTransaction>(
      items,
      (i) => i.deletedAt,
    );

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: grouped.length,
      itemBuilder: (ctx, sectionIdx) {
        final entry = grouped[sectionIdx];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DateHeader(label: _formatSectionDate(entry.key)),
            ...entry.value.map((item) => _TransactionTile(
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

// ── Accounts tab ─────────────────────────────────────────────────────────────

class _AccountsTab extends StatelessWidget {
  final List<TrashedAccount> items;
  final void Function(TrashedAccount item, int trashId) onRestore;
  final void Function(TrashedAccount item, int trashId) onDelete;

  const _AccountsTab({
    required this.items,
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
      itemBuilder: (ctx, sectionIdx) {
        final entry = grouped[sectionIdx];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DateHeader(label: _formatSectionDate(entry.key)),
            ...entry.value.map((item) => _AccountTile(
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

// ── Transaction tile ──────────────────────────────────────────────────────────

class _TransactionTile extends StatelessWidget {
  final TrashedTransaction item;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _TransactionTile({
    required this.item,
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

    final icon = kTransactionCategoryIcons[tx.category] ?? Icons.category;

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
                '$prefix₱${tx.amount.toStringAsFixed(2)}',
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

// ── Account tile ──────────────────────────────────────────────────────────────

class _AccountTile extends StatelessWidget {
  final TrashedAccount item;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _AccountTile({
    required this.item,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final acct = item.account;

    // Parse stored hex colour — fall back to primary
    Color acctColor;
    try {
      final hex = acct.colorHex.replaceAll('#', '');
      acctColor = Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      acctColor = cs.primary;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            // Account icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: acctColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _accountIcon(acct.icon),
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
                '₱${acct.balance.toStringAsFixed(2)}',
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

  IconData _accountIcon(String iconName) {
    switch (iconName) {
      case 'wallet':
        return Icons.account_balance_wallet;
      case 'bank':
        return Icons.account_balance;
      case 'credit_card':
        return Icons.credit_card;
      case 'savings':
        return Icons.savings;
      case 'phone':
        return Icons.phone_android;
      default:
        return Icons.account_balance_wallet;
    }
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.delete_outline,
            size: 72,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Items you delete will appear here.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
        ],
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
