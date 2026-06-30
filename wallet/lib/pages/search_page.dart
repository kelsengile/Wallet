import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wallet/database/database_helper.dart';
import 'package:wallet/currency.dart';
import 'package:wallet/models/transaction_model.dart';
import 'package:wallet/models/account_model.dart';
import 'package:wallet/models/category_model.dart';
import 'package:wallet/widgets/transaction_receipt_dialog.dart';

final _currencyFmt = NumberFormat('#,##0.00', 'en_PH');
String _fmt(double v) => _currencyFmt.format(v);

/// Full-text search over transactions: matches title, note, category name,
/// and account name (and amount, if the query parses as a number).
///
/// Opens with the keyboard already up. Results update as you type (with a
/// light debounce) and are grouped by date, newest first — same visual
/// language as [HistoryPage] so it feels like part of the same app rather
/// than a bolted-on screen.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _db = DatabaseHelper.instance;
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();

  bool _loading = true;
  List<WalletTransaction> _allTransactions = [];
  List<Account> _accounts = [];
  List<WalletCategory> _txCategories = [];
  List<WalletCategory> _accountTypes = [];
  List<WalletCategory> _accountCategories = [];

  String _query = '';
  Timer? _debounce;

  // Recent searches, kept in-memory + persisted via DatabaseHelper settings.
  List<String> _recent = [];

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_onQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onQueryChanged);
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _db.getAllTransactions(),
      _db.getAllAccounts(),
      _db.getCategoryRegistry(),
      _db.getSetting('recent_searches'),
    ]);
    final txs = results[0] as List<WalletTransaction>;
    final accounts = results[1] as List<Account>;
    final registry = results[2] as CategoryRegistry;
    final savedRecent = results[3] as String?;

    if (!mounted) return;
    setState(() {
      _allTransactions = txs;
      _accounts = accounts;
      _txCategories = registry.selectableTransactionCategories;
      _accountTypes = registry.accountTypes;
      _accountCategories = registry.accountCategories;
      _recent = (savedRecent == null || savedRecent.isEmpty)
          ? <String>[]
          : savedRecent.split('\u0001');
      _loading = false;
    });
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() => _query = _searchCtrl.text.trim());
    });
  }

  Future<void> _saveRecent(String term) async {
    if (term.isEmpty) return;
    final updated = [term, ..._recent.where((t) => t != term)];
    if (updated.length > 8) updated.removeRange(8, updated.length);
    setState(() => _recent = updated);
    await _db.saveSetting('recent_searches', updated.join('\u0001'));
  }

  Future<void> _clearRecent() async {
    setState(() => _recent = []);
    await _db.saveSetting('recent_searches', '');
  }

  String _accountName(int? accountId) {
    return _accounts
        .firstWhere(
          (a) => a.id == accountId,
          orElse: () => Account(
            name: 'Unknown',
            balance: 0,
            type: '',
            colorHex: '',
            icon: '',
          ),
        )
        .name;
  }

  IconData _categoryIcon(String category) {
    return _txCategories
            .cast<WalletCategory?>()
            .firstWhere((c) => c?.name == category, orElse: () => null)
            ?.iconData ??
        iconForKey(category);
  }

  List<WalletTransaction> get _results {
    final q = _query.toLowerCase();
    if (q.isEmpty) return const [];

    final amountQuery = double.tryParse(q.replaceAll(',', ''));

    return _allTransactions.where((tx) {
      final title = tx.title.toLowerCase();
      final note = (tx.note ?? '').toLowerCase();
      final category = tx.category.toLowerCase();
      final account = _accountName(tx.accountId).toLowerCase();

      final matchesText = title.contains(q) ||
          note.contains(q) ||
          category.contains(q) ||
          account.contains(q);

      final matchesAmount = amountQuery != null &&
          tx.amount.toStringAsFixed(2) == amountQuery.toStringAsFixed(2);

      return matchesText || matchesAmount;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  String _dateLabel(String isoDate) {
    final d = DateTime.tryParse(isoDate);
    if (d == null) return isoDate;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (d.year == now.year) return DateFormat('MMM d').format(d);
    return DateFormat('MMM d, yyyy').format(d);
  }

  Future<void> _openTransaction(WalletTransaction tx) async {
    await _saveRecent(_query);
    if (!mounted) return;
    await showTransactionReceipt(
      context,
      tx: tx,
      accounts: _accounts,
      txCategories: _txCategories,
      accountTypes: _accountTypes,
      accountCategories: _accountCategories,
      transferTitle: tx.type == 'transfer_out' || tx.type == 'transfer_in'
          ? 'Transfer'
          : null,
      onEdited: (updated) async {
        await _db.updateTransaction(tx, updated);
        await _load();
        return updated;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        titleSpacing: 0,
        title: _SearchField(
          controller: _searchCtrl,
          focusNode: _focusNode,
          onSubmitted: _saveRecent,
          onClear: () => setState(() {
            _searchCtrl.clear();
            _query = '';
          }),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _query.isEmpty
              ? _RecentSearches(
                  recent: _recent,
                  onTap: (term) {
                    _searchCtrl.text = term;
                    _searchCtrl.selection = TextSelection.fromPosition(
                      TextPosition(offset: term.length),
                    );
                    setState(() => _query = term);
                  },
                  onClearAll: _clearRecent,
                )
              : _ResultsList(
                  results: _results,
                  query: _query,
                  dateLabel: _dateLabel,
                  accountName: _accountName,
                  categoryIcon: _categoryIcon,
                  onTap: _openTransaction,
                ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(21),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: 'Search transactions, notes, categories…',
          border: InputBorder.none,
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClear,
                tooltip: 'Clear',
              );
            },
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}

class _RecentSearches extends StatelessWidget {
  final List<String> recent;
  final ValueChanged<String> onTap;
  final VoidCallback onClearAll;

  const _RecentSearches({
    required this.recent,
    required this.onTap,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (recent.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search,
                  size: 48,
                  color: theme.colorScheme.outline.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                'Search your transactions',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 4),
              Text(
                'Find by title, note, category, account, or amount.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent searches',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: onClearAll,
              style: TextButton.styleFrom(
                foregroundColor:
                    theme.brightness == Brightness.dark ? Colors.red : null,
              ),
              child: const Text('Clear all'),
            ),
          ],
        ),
        ...recent.map(
          (term) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history, size: 20),
            title: Text(term),
            trailing: const Icon(Icons.north_west, size: 16),
            onTap: () => onTap(term),
          ),
        ),
      ],
    );
  }
}

class _ResultsList extends StatelessWidget {
  final List<WalletTransaction> results;
  final String query;
  final String Function(String isoDate) dateLabel;
  final String Function(int? accountId) accountName;
  final IconData Function(String category) categoryIcon;
  final ValueChanged<WalletTransaction> onTap;

  const _ResultsList({
    required this.results,
    required this.query,
    required this.dateLabel,
    required this.accountName,
    required this.categoryIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off,
                  size: 48,
                  color: theme.colorScheme.outline.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                'No results for "$query"',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 4),
              Text(
                'Try a different title, note, category, or amount.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final tx = results[i];
        final showHeader = i == 0 ||
            results[i - 1].date.substring(0, 10) != tx.date.substring(0, 10);
        final isIncome = tx.type == 'income';
        final rowColor =
            isIncome ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
        final bgColor = rowColor.withValues(alpha: 0.15);
        final amountPrefix = isIncome ? '+' : '−';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader)
              Padding(
                padding: EdgeInsets.fromLTRB(4, i == 0 ? 4 : 16, 4, 8),
                child: Text(
                  dateLabel(tx.date),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              color: theme.colorScheme.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                dense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                onTap: () => onTap(tx),
                leading: CircleAvatar(
                  radius: 22,
                  backgroundColor: bgColor,
                  child: Icon(categoryIcon(tx.category),
                      size: 20, color: rowColor),
                ),
                title: Text(
                  tx.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                subtitle: Text(
                  [
                    accountName(tx.accountId),
                    tx.category,
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  '$amountPrefix ${currencySymbolNotifier.value}${_fmt(tx.amount)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: rowColor,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
