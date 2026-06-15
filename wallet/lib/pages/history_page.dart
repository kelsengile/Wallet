import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/transaction_model.dart';
import '../models/account_model.dart';
import '../models/category_model.dart';
import '../widgets/transaction_receipt_dialog.dart';

final _currencyFmt = NumberFormat('#,##0.00', 'en_PH');
String _fmt(double v) => _currencyFmt.format(v);

// ── Filter modes ───────────────────────────────────────────────────────────────
enum _FilterMode { daily, weekly, monthly, yearly }

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => HistoryPageState();
}

class HistoryPageState extends State<HistoryPage> {
  final _db = DatabaseHelper.instance;
  List<WalletTransaction> _transactions = [];
  List<Account> _accounts = [];
  List<WalletCategory> _txCategories = [];
  List<WalletCategory> _accountTypes = [];
  List<WalletCategory> _accountCategories = [];
  bool _loading = true;

  _FilterMode _filterMode = _FilterMode.monthly;

  // The "anchor" date — we navigate around this.
  DateTime _anchor = DateTime(DateTime.now().year, DateTime.now().month);

  // ── Period helpers ────────────────────────────────────────────────────────

  /// Inclusive start of the current period.
  DateTime get _periodStart {
    final now = _anchor;
    switch (_filterMode) {
      case _FilterMode.daily:
        return DateTime(now.year, now.month, now.day);
      case _FilterMode.weekly:
        // Monday of the week containing _anchor
        return now.subtract(Duration(days: now.weekday - 1));
      case _FilterMode.monthly:
        return DateTime(now.year, now.month);
      case _FilterMode.yearly:
        return DateTime(now.year);
    }
  }

  /// Exclusive end (start of next period).
  DateTime get _periodEnd {
    switch (_filterMode) {
      case _FilterMode.daily:
        return _periodStart.add(const Duration(days: 1));
      case _FilterMode.weekly:
        return _periodStart.add(const Duration(days: 7));
      case _FilterMode.monthly:
        final s = _periodStart;
        return DateTime(s.year, s.month + 1);
      case _FilterMode.yearly:
        return DateTime(_periodStart.year + 1);
    }
  }

  String get _periodLabel {
    final s = _periodStart;
    switch (_filterMode) {
      case _FilterMode.daily:
        return DateFormat('EEE, MMM d, yyyy').format(s);
      case _FilterMode.weekly:
        final e = _periodEnd.subtract(const Duration(days: 1));
        final sStr = DateFormat('MMM d').format(s);
        final eStr = DateFormat('MMM d, yyyy').format(e);
        return '$sStr – $eStr';
      case _FilterMode.monthly:
        return DateFormat('MMMM yyyy').format(s);
      case _FilterMode.yearly:
        return s.year.toString();
    }
  }

  bool get _canGoForward {
    final now = DateTime.now();
    return _periodEnd.isBefore(DateTime(now.year, now.month, now.day + 1));
  }

  void _goBack() {
    setState(() {
      switch (_filterMode) {
        case _FilterMode.daily:
          _anchor = _anchor.subtract(const Duration(days: 1));
          break;
        case _FilterMode.weekly:
          _anchor = _anchor.subtract(const Duration(days: 7));
          break;
        case _FilterMode.monthly:
          _anchor = DateTime(_anchor.year, _anchor.month - 1);
          break;
        case _FilterMode.yearly:
          _anchor = DateTime(_anchor.year - 1);
          break;
      }
    });
    _saveFilter();
  }

  void _goForward() {
    if (!_canGoForward) return;
    setState(() {
      switch (_filterMode) {
        case _FilterMode.daily:
          _anchor = _anchor.add(const Duration(days: 1));
          break;
        case _FilterMode.weekly:
          _anchor = _anchor.add(const Duration(days: 7));
          break;
        case _FilterMode.monthly:
          _anchor = DateTime(_anchor.year, _anchor.month + 1);
          break;
        case _FilterMode.yearly:
          _anchor = DateTime(_anchor.year + 1);
          break;
      }
    });
    _saveFilter();
  }

  // ── Filtered transactions ─────────────────────────────────────────────────

  List<WalletTransaction> get _filtered {
    final start = _periodStart;
    final end = _periodEnd;
    return _transactions.where((tx) {
      final d = DateTime.tryParse(tx.date);
      return d != null && !d.isBefore(start) && d.isBefore(end);
    }).toList();
  }

  // ── Analytics for current period ──────────────────────────────────────────

  double get _periodIncome => _filtered
      .where((tx) => tx.type == 'income')
      .fold(0.0, (sum, tx) => sum + tx.amount);

  double get _periodExpenses => _filtered
      .where((tx) => tx.type == 'expense')
      .fold(0.0, (sum, tx) => sum + tx.amount);

  double get _periodNet => _periodIncome - _periodExpenses;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _db.getAllTransactions(),
      _db.getAllAccounts(),
      _db.getCategoryRegistry(),
      _db.getSetting('history_filter_mode'),
      _db.getSetting('history_filter_anchor'),
    ]);
    final txs = results[0] as List<WalletTransaction>;
    final accounts = results[1] as List<Account>;
    final registry = results[2] as CategoryRegistry;
    final savedFilter = results[3] as String?;
    final savedAnchor = results[4] as String?;

    _FilterMode restoredMode = _filterMode;
    DateTime restoredAnchor = _anchor;

    if (savedFilter != null) {
      restoredMode = _FilterMode.values.firstWhere(
        (m) => m.name == savedFilter,
        orElse: () => _FilterMode.monthly,
      );
    }
    if (savedAnchor != null) {
      restoredAnchor = DateTime.tryParse(savedAnchor) ?? _anchor;
    }

    if (!mounted) return;
    setState(() {
      _transactions = txs;
      _accounts = accounts;
      _txCategories = registry.selectableTransactionCategories;
      _accountTypes = registry.accountTypes;
      _accountCategories = registry.accountCategories;
      _filterMode = restoredMode;
      _anchor = restoredAnchor;
      _loading = false;
    });
  }

  Future<void> _saveFilter() async {
    await _db.saveSetting('history_filter_mode', _filterMode.name);
    await _db.saveSetting('history_filter_anchor', _anchor.toIso8601String());
  }

  // ── Filter bottom-sheet ───────────────────────────────────────────────────

  Future<void> _showFilterSheet() async {
    final selected = await showModalBottomSheet<_FilterMode>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _FilterSheet(current: _filterMode),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _filterMode = selected;
      // Reset anchor to today's period when switching modes
      final now = DateTime.now();
      switch (_filterMode) {
        case _FilterMode.daily:
          _anchor = DateTime(now.year, now.month, now.day);
          break;
        case _FilterMode.weekly:
          _anchor = now.subtract(Duration(days: now.weekday - 1));
          break;
        case _FilterMode.monthly:
          _anchor = DateTime(now.year, now.month);
          break;
        case _FilterMode.yearly:
          _anchor = DateTime(now.year);
          break;
      }
    });
    _saveFilter();
  }

  // ── Period picker (tapping the label) ───────────────────────────────────

  Future<void> _pickPeriod() async {
    final result = await showDialog<({_FilterMode mode, DateTime anchor})>(
      context: context,
      builder: (ctx) => _PeriodPickerDialog(
        currentMode: _filterMode,
        currentAnchor: _anchor,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _filterMode = result.mode;
      _anchor = result.anchor;
    });
    _saveFilter();
  }

  // ── Public API (called from main.dart) ────────────────────────────────────

  Future<void> refresh() => _load();

  Future<void> addTransaction() async {
    final tx = await WalletTransaction.showDialog(
      context,
      accounts: _accounts,
      categories: _txCategories,
      accountTypes: _accountTypes,
      accountCategories: _accountCategories,
      type: 'expense',
    );
    if (tx == null) return;
    await _db.insertTransaction(tx);
    _load();
  }

  Future<void> _editTransaction(WalletTransaction existing) async {
    await showTransactionReceipt(
      context,
      tx: existing,
      accounts: _accounts,
      txCategories: _txCategories,
      accountTypes: _accountTypes,
      accountCategories: _accountCategories,
      onEdited: (updated) async {
        await _db.updateTransaction(existing, updated);
        _load();
        return updated;
      },
    );
  }

  // Transfer info is now handled by showTransactionReceipt inside _editTransaction.
  // This stub is kept so existing onTap references continue to compile.
  void _showTransferInfo(WalletTransaction tx) => _editTransaction(tx);

  Future<void> _deleteTransaction(WalletTransaction tx) async {
    await _db.deleteTransaction(tx);
    _load();
  }

  // ── Date group label ──────────────────────────────────────────────────────

  /// Returns the header string for a group of transactions sharing the same
  /// calendar day, based on the active filter mode.
  String _dateGroupLabel(DateTime d) {
    switch (_filterMode) {
      case _FilterMode.daily:
        return ''; // no header needed — date already shown in navigator
      case _FilterMode.weekly:
      case _FilterMode.monthly:
        // e.g. "Jun 9, Monday"
        return DateFormat('MMM d, EEEE').format(d);
      case _FilterMode.yearly:
        // e.g. "Jun 9 • Monday"
        return DateFormat('MMM d • EEEE').format(d);
    }
  }

  // ── Grouped list builder ──────────────────────────────────────────────────

  /// Extracts the __ref:... tag from a note, returns null if absent.
  static String? _extractRef(String? note) {
    if (note == null) return null;
    final match = RegExp(r'__ref:([^_]+)__').firstMatch(note);
    return match?.group(1);
  }

  Widget _buildGroupedList(List<WalletTransaction> txs, ThemeData theme) {
    // Group transactions by calendar date string "yyyy-MM-dd"
    final Map<String, List<WalletTransaction>> groups = {};
    for (final tx in txs) {
      final key = tx.date.length >= 10 ? tx.date.substring(0, 10) : tx.date;
      groups.putIfAbsent(key, () => []).add(tx);
    }
    // Keys are already date-DESC ordered because _transactions is sorted DESC
    final keys = groups.keys.toList();

    // Build a flat list of items: header + transactions for each group.
    // Transfer pairs (same __ref:) are collapsed into one _ListItem.transfer.
    final items = <_ListItem>[];

    // For yearly mode: track the last emitted month so we can inject separators.
    String? _lastMonthKey; // "yyyy-MM"

    for (final key in keys) {
      final d = DateTime.tryParse(key);

      // ── Yearly mode: inject a month header whenever the month changes ──────
      if (_filterMode == _FilterMode.yearly && d != null) {
        final monthKey = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        if (monthKey != _lastMonthKey) {
          _lastMonthKey = monthKey;
          final monthLabel = DateFormat('MMMM').format(d);
          items.add(_ListItem.monthHeader(monthLabel));
        }
      }

      final label = d != null ? _dateGroupLabel(d) : '';
      if (label.isNotEmpty) items.add(_ListItem.header(label));

      final dayTxs = groups[key]!;
      // Track refs already emitted so we skip the second leg.
      final emittedRefs = <String>{};

      // Pre-build index of untagged transfer_in legs for fallback pairing
      final unmatchedIns = <WalletTransaction>[
        ...dayTxs.where(
          (t) => t.type == 'transfer_in' && _extractRef(t.note) == null,
        )
      ];
      final skippedIds = <int>{};

      for (final tx in dayTxs) {
        if (skippedIds.contains(tx.id)) continue;

        if (tx.type == 'transfer_out' || tx.type == 'transfer_in') {
          final ref = _extractRef(tx.note);
          if (ref != null) {
            if (emittedRefs.contains(ref)) continue; // second leg — skip
            emittedRefs.add(ref);

            // Find the paired leg in the same day group
            final WalletTransaction outLeg;
            final WalletTransaction inLeg;
            if (tx.type == 'transfer_out') {
              outLeg = tx;
              inLeg = dayTxs.firstWhere(
                (t) => t.type == 'transfer_in' && _extractRef(t.note) == ref,
                orElse: () => tx,
              );
            } else {
              final out = dayTxs.firstWhere(
                (t) => t.type == 'transfer_out' && _extractRef(t.note) == ref,
                orElse: () => tx,
              );
              outLeg = out;
              inLeg = tx;
            }
            items.add(_ListItem.transfer(outLeg, inLeg));
          } else if (tx.type == 'transfer_out') {
            // Fallback: pair with a transfer_in of the same amount on the same day
            final matchIdx = unmatchedIns.indexWhere(
              (t) => t.amount == tx.amount && !skippedIds.contains(t.id),
            );
            if (matchIdx != -1) {
              final inLeg = unmatchedIns[matchIdx];
              skippedIds.add(inLeg.id!);
              items.add(_ListItem.transfer(tx, inLeg));
            } else {
              items.add(_ListItem.tx(tx));
            }
          } else {
            // transfer_in with no ref and no matched out leg — show individually
            items.add(_ListItem.tx(tx));
          }
        } else {
          items.add(_ListItem.tx(tx));
        }
      }
    }

    // Compute which item indices are the last transaction in their day group.
    // (i.e. the next item is a header, monthHeader, or end of list)
    final lastInGroupIndices = <int>{};
    for (int i = 0; i < items.length; i++) {
      if (items[i].isHeader || items[i].isMonthHeader) continue;
      final isLast = i == items.length - 1 ||
          items[i + 1].isHeader ||
          items[i + 1].isMonthHeader;
      if (isLast) lastInGroupIndices.add(i);
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        final showDivider = !lastInGroupIndices.contains(i);
        final isFirstHeader = i == 0;
        if (item.isHeader) {
          return Padding(
            padding: EdgeInsets.only(top: isFirstHeader ? 12.0 : 0.0),
            child: _DateHeader(
              label: item.label!,
              theme: theme,
              indented: _filterMode == _FilterMode.yearly,
            ),
          );
        }

        if (item.isMonthHeader) {
          return Padding(
            padding: EdgeInsets.only(top: isFirstHeader ? 12.0 : 0.0),
            child: _MonthHeader(label: item.label!, theme: theme),
          );
        }

        // ── Merged transfer card ─────────────────────────────────────────
        if (item.isTransfer) {
          final outTx = item.transferOut!;
          final inTx = item.transferIn!;

          final fromAccount = _accounts
              .firstWhere((a) => a.id == outTx.accountId,
                  orElse: () => Account(
                      name: 'Unknown',
                      balance: 0,
                      type: '',
                      colorHex: '',
                      icon: ''))
              .name;
          final toAccount = _accounts
              .firstWhere((a) => a.id == inTx.accountId,
                  orElse: () => Account(
                      name: 'Unknown',
                      balance: 0,
                      type: '',
                      colorHex: '',
                      icon: ''))
              .name;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                color: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Dismissible(
                    key: Key('transfer_${outTx.id}_${inTx.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    confirmDismiss: (_) async => true,
                    onDismissed: (_) async {
                      await _deleteTransaction(outTx);
                      await _deleteTransaction(inTx);
                    },
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      onTap: () => _showTransferInfo(outTx),
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFFDBEAFE),
                        child: const Icon(
                          Icons.swap_horiz_rounded,
                          size: 20,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                      title: const Text(
                        'Transfer',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      subtitle: Text(
                        '$fromAccount → $toAccount',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Text(
                        '± ₱${_fmt(outTx.amount)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (showDivider)
                Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 12,
                  endIndent: 12,
                  color: Colors.grey.withValues(alpha: 0.25),
                ),
            ],
          );
        }

        // ── Regular transaction card ──────────────────────────────────────
        final tx = item.tx!;
        final isIncome = tx.type == 'income';
        final rowColor = isIncome ? Colors.green : Colors.red;
        final bgColor = isIncome ? Colors.green.shade100 : Colors.red.shade100;
        final amountPrefix = isIncome ? '+' : '−';
        final accountName = _accounts
            .firstWhere(
              (a) => a.id == tx.accountId,
              orElse: () => Account(
                name: 'Unknown',
                balance: 0,
                type: '',
                colorHex: '',
                icon: '',
              ),
            )
            .name;
        final txCatIcon = _txCategories
                .cast<WalletCategory?>()
                .firstWhere((c) => c?.name == tx.category, orElse: () => null)
                ?.iconData ??
            iconForKey(tx.category);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Dismissible(
                  key: Key('tx_${tx.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => _deleteTransaction(tx),
                  child: ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    onTap: () => _editTransaction(tx),
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundColor: bgColor,
                      child: Icon(
                        txCatIcon,
                        size: 20,
                        color: rowColor,
                      ),
                    ),
                    title: Text(
                      tx.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    subtitle: Text(
                      accountName,
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Text(
                      '$amountPrefix ₱${_fmt(tx.amount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: rowColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (showDivider)
              Divider(
                height: 1,
                thickness: 0.5,
                indent: 12,
                endIndent: 12,
                color: Colors.grey.withValues(alpha: 0.25),
              ),
          ],
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filtered;
    final income = _periodIncome;
    final expenses = _periodExpenses;
    final net = _periodNet;

    // Extend the gradient behind the transparent top nav bar overlay,
    // matching AccountsPage's total balance hero.
    final topPadding = MediaQuery.paddingOf(context).top;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Filter section (header, period nav, analytics) ─────────────────
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(16, topPadding + 70, 16, 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.fromARGB(255, 97, 60, 27),
                Color.fromARGB(255, 144, 99, 59),
              ],
            ),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(10),
            ),
          ),
          child: Column(
            children: [
              // ── Header row ───────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Transaction History',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                      color: const Color.fromARGB(255, 219, 219, 219),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Filter',
                    onPressed: _showFilterSheet,
                    icon: const _FunnelIcon(
                      color: Colors.white,
                    ),
                  ),
                ],
              ),

              // ── Period navigator ─────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left,
                        color: Color.fromARGB(255, 219, 219, 219)),
                    onPressed: _goBack,
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickPeriod,
                      child: Center(
                        child: Text(
                          _periodLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: const Color.fromARGB(255, 219, 219, 219),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.chevron_right,
                      color: _canGoForward
                          ? const Color.fromARGB(255, 219, 219, 219)
                          : const Color.fromARGB(255, 219, 219, 219)
                              .withValues(alpha: 0.3),
                    ),
                    onPressed: _canGoForward ? _goForward : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ── Analytics strip ───────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _AnalyticsTile(
                      icon: Icons.arrow_upward_rounded,
                      amount: income,
                      color: const Color(0xFF4ADE80),
                      textColor: const Color.fromARGB(255, 219, 219, 219),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _AnalyticsTile(
                      icon: Icons.arrow_downward_rounded,
                      amount: expenses,
                      color: const Color(0xFFF87171),
                      textColor: const Color.fromARGB(255, 219, 219, 219),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _AnalyticsTile(
                      icon: Icons.account_balance_wallet_outlined,
                      amount: net,
                      color: net >= 0
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFFF87171),
                      textColor: const Color.fromARGB(255, 219, 219, 219),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── Transaction list ───────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      _transactions.isEmpty
                          ? 'No transactions yet. Add one!'
                          : 'No transactions for this period.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : _buildGroupedList(filtered, theme),
          ),
        ),
      ],
    );
  }
}

// ── List item discriminated union ──────────────────────────────────────────────

class _ListItem {
  final bool isHeader;
  final bool isMonthHeader;
  final bool isTransfer;
  final String? label;
  final WalletTransaction? tx;
  final WalletTransaction? transferOut;
  final WalletTransaction? transferIn;

  const _ListItem.header(this.label)
      : isHeader = true,
        isMonthHeader = false,
        isTransfer = false,
        tx = null,
        transferOut = null,
        transferIn = null;

  const _ListItem.monthHeader(this.label)
      : isHeader = false,
        isMonthHeader = true,
        isTransfer = false,
        tx = null,
        transferOut = null,
        transferIn = null;

  const _ListItem.tx(this.tx)
      : isHeader = false,
        isMonthHeader = false,
        isTransfer = false,
        label = null,
        transferOut = null,
        transferIn = null;

  const _ListItem.transfer(this.transferOut, this.transferIn)
      : isHeader = false,
        isMonthHeader = false,
        isTransfer = true,
        label = null,
        tx = null;
}

// ── Date group header widget ───────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  final String label;
  final ThemeData theme;
  final bool indented;

  const _DateHeader(
      {required this.label, required this.theme, this.indented = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: 2, left: indented ? 12 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 4),
          Divider(
            height: 1,
            thickness: 1,
            indent: 0,
            endIndent: 0,
            color: theme.colorScheme.outlineVariant,
          ),
        ],
      ),
    );
  }
}

// ── Month section header widget (yearly view) ─────────────────────────────────

class _MonthHeader extends StatelessWidget {
  final String label;
  final ThemeData theme;

  const _MonthHeader({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Divider(
            height: 1,
            thickness: 1.5,
            color: theme.colorScheme.outlineVariant,
          ),
        ],
      ),
    );
  }
}

// ── Analytics tile ─────────────────────────────────────────────────────────────

class _AnalyticsTile extends StatelessWidget {
  final IconData icon;
  final double amount;
  final Color color;
  final Color? textColor;

  const _AnalyticsTile({
    required this.icon,
    required this.amount,
    required this.color,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '₱${_fmt(amount.abs())}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: textColor ?? theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Custom funnel / filter icon ────────────────────────────────────────────────

class _FunnelIcon extends StatelessWidget {
  final Color color;

  const _FunnelIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(20, 20),
      painter: _FunnelPainter(color: color),
    );
  }
}

class _FunnelPainter extends CustomPainter {
  final Color color;
  _FunnelPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final w = size.width;
    final h = size.height;

    // Three horizontal lines, each shorter than the last (funnel / filter look)
    final lines = [
      // (startX, endX, y)
      (0.0, w, h * 0.22),
      (w * 0.18, w * 0.82, h * 0.50),
      (w * 0.36, w * 0.64, h * 0.78),
    ];

    for (final (x1, x2, y) in lines) {
      canvas.drawLine(Offset(x1, y), Offset(x2, y), paint);
    }
  }

  @override
  bool shouldRepaint(_FunnelPainter old) => old.color != color;
}

// ── Filter bottom-sheet ────────────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  final _FilterMode current;
  const _FilterSheet({required this.current});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late _FilterMode _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
  }

  static const _options = [
    (_FilterMode.daily, 'Daily', Icons.today_outlined),
    (_FilterMode.weekly, 'Weekly', Icons.view_week_outlined),
    (_FilterMode.monthly, 'Monthly', Icons.calendar_month_outlined),
    (_FilterMode.yearly, 'Yearly', Icons.calendar_today_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Filter by Period',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ..._options.map((opt) {
            final (mode, label, icon) = opt;
            final isSelected = _selected == mode;
            return RadioListTile<_FilterMode>(
              value: mode,
              groupValue: _selected,
              onChanged: (v) => setState(() => _selected = v!),
              secondary: Icon(
                icon,
                color: isSelected ? theme.colorScheme.primary : null,
              ),
              title: Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? theme.colorScheme.primary : null,
                ),
              ),
              contentPadding: EdgeInsets.zero,
            );
          }),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _selected),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Apply'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Period picker dialog ───────────────────────────────────────────────────────
//
// A centred dialog that lets the user pick both a filter mode (Daily / Weekly /
// Monthly / Yearly) and an exact anchor date.  Returns a named record so the
// caller gets both values atomically.

class _PeriodPickerDialog extends StatefulWidget {
  final _FilterMode currentMode;
  final DateTime currentAnchor;

  const _PeriodPickerDialog({
    required this.currentMode,
    required this.currentAnchor,
  });

  @override
  State<_PeriodPickerDialog> createState() => _PeriodPickerDialogState();
}

class _PeriodPickerDialogState extends State<_PeriodPickerDialog> {
  late _FilterMode _mode;
  late DateTime _anchor;

  // For the inline calendar grid
  late DateTime _calendarMonth; // which month the mini-calendar is showing

  static const _modes = [
    (_FilterMode.daily, 'Day'),
    (_FilterMode.weekly, 'Week'),
    (_FilterMode.monthly, 'Month'),
    (_FilterMode.yearly, 'Year'),
  ];

  @override
  void initState() {
    super.initState();
    _mode = widget.currentMode;
    _anchor = widget.currentAnchor;
    _calendarMonth = DateTime(_anchor.year, _anchor.month);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isInSameWeek(DateTime d) {
    final weekStart = _anchor.subtract(Duration(days: _anchor.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(
            DateTime(weekStart.year, weekStart.month, weekStart.day)) &&
        !day.isAfter(DateTime(weekEnd.year, weekEnd.month, weekEnd.day));
  }

  bool _isHighlighted(DateTime d) {
    switch (_mode) {
      case _FilterMode.daily:
        return _isSameDay(d, _anchor);
      case _FilterMode.weekly:
        return _isInSameWeek(d);
      case _FilterMode.monthly:
        return d.year == _anchor.year && d.month == _anchor.month;
      case _FilterMode.yearly:
        return d.year == _anchor.year;
    }
  }

  void _onDayTapped(DateTime d) {
    setState(() {
      switch (_mode) {
        case _FilterMode.daily:
          _anchor = DateTime(d.year, d.month, d.day);
          break;
        case _FilterMode.weekly:
          // snap anchor to Monday of tapped week
          _anchor = d.subtract(Duration(days: d.weekday - 1));
          break;
        case _FilterMode.monthly:
          _anchor = DateTime(d.year, d.month);
          break;
        case _FilterMode.yearly:
          _anchor = DateTime(d.year);
          break;
      }
    });
  }

  String _calendarMonthLabel() =>
      DateFormat('MMMM yyyy').format(_calendarMonth);

  // Days to display: leading blanks + days of the month
  List<DateTime?> _calendarDays() {
    final firstDay = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final daysInMonth =
        DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    final leadingBlanks = firstDay.weekday - 1; // Monday = 1
    return [
      ...List<DateTime?>.filled(leadingBlanks, null),
      ...List.generate(daysInMonth,
          (i) => DateTime(_calendarMonth.year, _calendarMonth.month, i + 1)),
    ];
  }

  // ── Selected period label shown at bottom ─────────────────────────────────

  String get _selectedLabel {
    switch (_mode) {
      case _FilterMode.daily:
        return DateFormat('EEE, MMM d, yyyy').format(_anchor);
      case _FilterMode.weekly:
        final start = _anchor.subtract(Duration(days: _anchor.weekday - 1));
        final end = start.add(const Duration(days: 6));
        return '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, yyyy').format(end)}';
      case _FilterMode.monthly:
        return DateFormat('MMMM yyyy').format(_anchor);
      case _FilterMode.yearly:
        return _anchor.year.toString();
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final now = DateTime.now();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Mode tabs ──────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(3),
              child: Row(
                children: _modes.map((opt) {
                  final (mode, label) = opt;
                  final sel = _mode == mode;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _mode = mode;
                        // re-snap anchor to the same date under the new mode
                        _onDayTapped(_anchor);
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: sel
                              ? theme.colorScheme.surface
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: sel
                              ? [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 4)
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  sel ? FontWeight.w700 : FontWeight.w400,
                              color: sel
                                  ? primary
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // ── Unified nav row (shared across all modes) ──────────────────
            Builder(builder: (_) {
              // Compute label, back handler, and forward-disabled state
              // once, based on the active mode.
              final decadeStart = (_calendarMonth.year - 1) ~/ 10 * 10 + 1;

              final String navLabel;
              final VoidCallback onBack;
              final VoidCallback? onForward;
              final double labelFontSize;

              switch (_mode) {
                case _FilterMode.monthly:
                  navLabel = '${_calendarMonth.year}';
                  labelFontSize = 15;
                  onBack = () => setState(() => _calendarMonth =
                      DateTime(_calendarMonth.year - 1, _calendarMonth.month));
                  onForward = _calendarMonth.year >= now.year
                      ? null
                      : () => setState(() => _calendarMonth = DateTime(
                          _calendarMonth.year + 1, _calendarMonth.month));
                case _FilterMode.yearly:
                  navLabel = '$decadeStart – ${decadeStart + 9}';
                  labelFontSize = 15;
                  onBack = () => setState(() =>
                      _calendarMonth = DateTime(_calendarMonth.year - 10, 1));
                  onForward = decadeStart + 9 >= now.year
                      ? null
                      : () => setState(() => _calendarMonth =
                          DateTime(_calendarMonth.year + 10, 1));
                default:
                  // Daily / Weekly — navigate by month
                  navLabel = _calendarMonthLabel();
                  labelFontSize = 13;
                  onBack = () => setState(() => _calendarMonth =
                      DateTime(_calendarMonth.year, _calendarMonth.month - 1));
                  onForward = (_calendarMonth.year > now.year ||
                          (_calendarMonth.year == now.year &&
                              _calendarMonth.month >= now.month))
                      ? null
                      : () => setState(() => _calendarMonth = DateTime(
                          _calendarMonth.year, _calendarMonth.month + 1));
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.chevron_left),
                    onPressed: onBack,
                  ),
                  Text(
                    navLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: labelFontSize,
                    ),
                  ),
                  IconButton(
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.chevron_right,
                      color: onForward == null
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.25)
                          : null,
                    ),
                    onPressed: onForward,
                  ),
                ],
              );
            }),
            const SizedBox(height: 8),

            // ── Mode-specific picker body (fixed height = tallest mode) ────
            SizedBox(
              height: 240,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_mode == _FilterMode.monthly) ...[
                    // Monthly: 3×4 month grid
                    Builder(builder: (_) {
                      const monthNames = [
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
                      return Column(
                        children: List.generate(3, (row) {
                          return Row(
                            children: List.generate(4, (col) {
                              final monthIdx = row * 4 + col + 1;
                              final isFuture = _calendarMonth.year > now.year ||
                                  (_calendarMonth.year == now.year &&
                                      monthIdx > now.month);
                              final isSelected =
                                  _anchor.year == _calendarMonth.year &&
                                      _anchor.month == monthIdx;
                              final isCurrentMonth =
                                  _calendarMonth.year == now.year &&
                                      monthIdx == now.month;
                              Color textColor = isFuture
                                  ? theme.colorScheme.onSurface
                                      .withValues(alpha: 0.25)
                                  : isSelected
                                      ? primary
                                      : isCurrentMonth
                                          ? primary
                                          : theme.colorScheme.onSurface;
                              return Expanded(
                                child: GestureDetector(
                                  onTap: isFuture
                                      ? null
                                      : () => setState(() {
                                            _anchor = DateTime(
                                                _calendarMonth.year, monthIdx);
                                          }),
                                  child: Container(
                                    height: 56,
                                    margin: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? primary.withValues(alpha: 0.15)
                                          : null,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        monthNames[monthIdx - 1],
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight:
                                              isSelected || isCurrentMonth
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                          color: textColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          );
                        }),
                      );
                    }),
                  ] else if (_mode == _FilterMode.yearly) ...[
                    // Yearly: 4 + 4 + 2 year grid
                    Builder(builder: (_) {
                      final decadeStart =
                          (_calendarMonth.year - 1) ~/ 10 * 10 + 1;
                      // Row sizes: [4, 4, 2]
                      const rowSizes = [4, 4, 2];

                      Widget yearCell(int yr) {
                        final isFuture = yr > now.year;
                        final isSelected = _anchor.year == yr;
                        final isCurrentYear = yr == now.year;
                        final Color textColor = isFuture
                            ? theme.colorScheme.onSurface
                                .withValues(alpha: 0.25)
                            : isSelected
                                ? primary
                                : isCurrentYear
                                    ? primary
                                    : theme.colorScheme.onSurface;
                        return Expanded(
                          child: GestureDetector(
                            onTap: isFuture
                                ? null
                                : () => setState(() => _anchor = DateTime(yr)),
                            child: Container(
                              height: 56,
                              margin: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? primary.withValues(alpha: 0.15)
                                    : null,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  '$yr',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected || isCurrentYear
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: textColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      int offset = 0;
                      return Column(
                        children: rowSizes.map((count) {
                          final start = offset;
                          offset += count;
                          if (count < 4) {
                            // Last row: one spacer on each side to centre the 2 cells
                            return Row(
                              children: [
                                const Expanded(child: SizedBox()),
                                ...List.generate(count,
                                    (i) => yearCell(decadeStart + start + i)),
                                const Expanded(child: SizedBox()),
                              ],
                            );
                          }
                          return Row(
                            children: List.generate(count,
                                (i) => yearCell(decadeStart + start + i)),
                          );
                        }).toList(),
                      );
                    }),
                  ] else ...[
                    // Daily / Weekly: weekday header + day grid
                    Row(
                      children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((d) {
                        return Expanded(
                          child: Center(
                            child: Text(
                              d,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 4),
                    Builder(builder: (_) {
                      final days = _calendarDays();
                      while (days.length % 7 != 0) days.add(null);
                      final rows = days.length ~/ 7;

                      return Column(
                        children: List.generate(rows, (row) {
                          return Row(
                            children: List.generate(7, (col) {
                              final d = days[row * 7 + col];
                              if (d == null) {
                                return const Expanded(
                                    child: SizedBox(height: 36));
                              }

                              final isFuture = d.isAfter(now);
                              final highlighted =
                                  !isFuture && _isHighlighted(d);
                              final isToday = _isSameDay(d, now);

                              Color? bgColor;
                              Color textColor = theme.colorScheme.onSurface;

                              if (highlighted) {
                                bgColor = primary.withValues(alpha: 0.15);
                                textColor = primary;
                              } else if (isToday) {
                                textColor = primary;
                              }

                              if (isFuture) {
                                textColor = theme.colorScheme.onSurface
                                    .withValues(alpha: 0.25);
                              }

                              return Expanded(
                                child: GestureDetector(
                                  onTap: isFuture
                                      ? null
                                      : () {
                                          _onDayTapped(d);
                                        },
                                  child: Container(
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: bgColor,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${d.day}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: highlighted || isToday
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                          color: textColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          );
                        }),
                      );
                    }),
                  ], // end else (daily/weekly)
                ], // end Column.children
              ),
            ), // end SizedBox
            const SizedBox(height: 12),

            // ── Selected period label ──────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _selectedLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: primary,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Actions ────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, (mode: _mode, anchor: _anchor)),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
