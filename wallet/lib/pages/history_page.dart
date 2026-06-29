import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../currency.dart';
import '../models/transaction_model.dart';
import '../models/account_model.dart';
import '../models/category_model.dart';
import '../widgets/transaction_receipt_dialog.dart';
import '../models/reminder_model.dart';
import '../widgets/reminder_receipt_dialog.dart';

final _currencyFmt = NumberFormat('#,##0.00', 'en_PH');
String _fmt(double v) => _currencyFmt.format(v);

// ── Filter modes ───────────────────────────────────────────────────────────────
enum _FilterMode { daily, weekly, monthly, yearly, allTime, custom }

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

  // Reminders for the current period (loaded alongside transactions)
  List<ReminderTransaction> _reminders = [];

  _FilterMode _filterMode = _FilterMode.monthly;

  // The "anchor" date — we navigate around this.
  DateTime _anchor = DateTime(DateTime.now().year, DateTime.now().month);

  // Custom date range (only used when _filterMode == _FilterMode.custom)
  DateTime? _customStart;
  DateTime? _customEnd;

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
      case _FilterMode.allTime:
        return DateTime(2000); // effectively epoch
      case _FilterMode.custom:
        return _customStart ?? DateTime(2000);
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
      case _FilterMode.allTime:
        return DateTime(2100);
      case _FilterMode.custom:
        final end = _customEnd ?? DateTime.now();
        return DateTime(end.year, end.month, end.day + 1);
    }
  }

  String get _periodLabel {
    switch (_filterMode) {
      case _FilterMode.allTime:
        return 'All Time';
      case _FilterMode.custom:
        if (_customStart == null && _customEnd == null) return 'Custom Range';
        final fmt = DateFormat('MMM d, yyyy');
        final s = _customStart != null ? fmt.format(_customStart!) : '…';
        final e = _customEnd != null ? fmt.format(_customEnd!) : '…';
        return '$s – $e';
      default:
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
          default:
            return '';
        }
    }
  }

  bool get _canGoForward {
    if (_filterMode == _FilterMode.allTime || _filterMode == _FilterMode.custom)
      return false;
    return true;
  }

  void _goBack() {
    if (_filterMode == _FilterMode.allTime || _filterMode == _FilterMode.custom)
      return;
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
        default:
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
        default:
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

  List<ReminderTransaction> get _filteredReminders {
    final start = _periodStart;
    final end = _periodEnd;
    return _reminders.where((r) {
      final d = DateTime.tryParse(r.dueDate);
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
      _db.getSetting('history_filter_custom_start'),
      _db.getSetting('history_filter_custom_end'),
    ]);
    final txs = results[0] as List<WalletTransaction>;
    final accounts = results[1] as List<Account>;
    final registry = results[2] as CategoryRegistry;
    final savedFilter = results[3] as String?;
    final savedAnchor = results[4] as String?;
    final savedCustomStart = results[5] as String?;
    final savedCustomEnd = results[6] as String?;

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
      if (savedCustomStart != null) {
        _customStart = DateTime.tryParse(savedCustomStart);
      }
      if (savedCustomEnd != null) {
        _customEnd = DateTime.tryParse(savedCustomEnd);
      }
      _loading = false;
    });

    // Load reminders after state is set so _periodStart/_periodEnd are valid.
    final allReminders = await _db.getAllReminders();
    if (!mounted) return;
    setState(() {
      _reminders = allReminders;
    });
  }

  Future<void> _saveFilter() async {
    await _db.saveSetting('history_filter_mode', _filterMode.name);
    await _db.saveSetting('history_filter_anchor', _anchor.toIso8601String());
    if (_customStart != null) {
      await _db.saveSetting(
          'history_filter_custom_start', _customStart!.toIso8601String());
    }
    if (_customEnd != null) {
      await _db.saveSetting(
          'history_filter_custom_end', _customEnd!.toIso8601String());
    }
  }

  // ── Period picker (tapping the label) ───────────────────────────────────

  Future<void> _pickPeriod() async {
    final result = await showDialog<
        ({
          _FilterMode mode,
          DateTime anchor,
          DateTime? customStart,
          DateTime? customEnd
        })>(
      context: context,
      builder: (ctx) => _PeriodPickerDialog(
        currentMode: _filterMode,
        currentAnchor: _anchor,
        customStart: _customStart,
        customEnd: _customEnd,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _filterMode = result.mode;
      _anchor = result.anchor;
      _customStart = result.customStart;
      _customEnd = result.customEnd;
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
      transferTitle:
          existing.type == 'transfer_out' || existing.type == 'transfer_in'
              ? 'Transfer'
              : null,
      onEdited: (updated) async {
        await _db.updateTransaction(existing, updated);
        _load();
        return updated;
      },
      onTransferEdited: (result, outLeg, inLeg) async {
        final ref =
            result.existingRef ?? '${DateTime.now().millisecondsSinceEpoch}';
        await _db.updateTransfer(
          outLegId: outLeg.id!,
          inLegId: inLeg.id!,
          oldFromAccountId: outLeg.accountId!,
          oldToAccountId: inLeg.accountId!,
          oldAmount: outLeg.amount,
          newFromAccountId: result.fromAccountId,
          newToAccountId: result.toAccountId,
          newAmount: result.amount,
          date: result.date,
          refId: ref,
          note: result.note,
        );
        _load();
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

  Future<void> _deleteTransfer(
      WalletTransaction outTx, WalletTransaction inTx) async {
    await _db.deleteTransfer(outTx, inTx);
    _load();
  }

  Future<void> _openReminderReceipt(ReminderTransaction reminder) async {
    await showReminderReceipt(
      context,
      reminder: reminder,
      accounts: _accounts,
      txCategories: _txCategories,
      accountTypes: _accountTypes,
      accountCategories: _accountCategories,
      onEdited: (updated) async {
        await _db.updateReminder(updated);
        await _load();
        return updated;
      },
      onDone: (r) async {
        await _db.markReminderDoneAsTransaction(r);
        await _load();
      },
      onDelete: (r) async {
        await _db.deleteReminder(r);
        await _load();
      },
    );
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
      case _FilterMode.allTime:
      case _FilterMode.custom:
        // Show full date including year
        return DateFormat('MMM d, EEEE • yyyy').format(d);
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

      // ── Yearly / allTime / custom mode: inject a month header whenever the month changes ──────
      if ((_filterMode == _FilterMode.yearly ||
              _filterMode == _FilterMode.allTime ||
              _filterMode == _FilterMode.custom) &&
          d != null) {
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
              indented: _filterMode == _FilterMode.yearly ||
                  _filterMode == _FilterMode.allTime ||
                  _filterMode == _FilterMode.custom,
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
                      await _deleteTransfer(outTx, inTx);
                    },
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      onTap: () => _showTransferInfo(outTx),
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor:
                            const Color(0xFF3B82F6).withValues(alpha: 0.18),
                        child: const Icon(
                          Icons.swap_horiz_rounded,
                          size: 20,
                          color: Color(0xFF3B82F6),
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
                        '± ${currencySymbolNotifier.value}${_fmt(outTx.amount)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Color(0xFF3B82F6),
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
        final rowColor = isIncome
            ? const Color(0xFF22C55E) // green-500
            : const Color(0xFFEF4444); // red-500
        final bgColor = isIncome
            ? const Color(0xFF22C55E).withValues(alpha: 0.15)
            : const Color(0xFFEF4444).withValues(alpha: 0.15);
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
                      '$amountPrefix ${currencySymbolNotifier.value}${_fmt(tx.amount)}',
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

    // ignore: unused_local_variable
    final primary = theme.colorScheme.primary;

    final headerBgColor = theme.colorScheme.surface;
    final headerTextColor = theme.colorScheme.onSurface;
    final headerIconColor = theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Filter section (header, period nav, analytics) ─────────────────
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(16, topPadding + 70, 16, 12),
          color: headerBgColor,
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
                      fontSize: 17,
                      color: headerTextColor,
                      letterSpacing: 0.2,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Filter',
                    onPressed: _pickPeriod,
                    icon: _FunnelIcon(
                      color: headerIconColor,
                    ),
                  ),
                ],
              ),

              // ── Period navigator ─────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Opacity(
                    opacity: _filterMode == _FilterMode.allTime ? 0.0 : 1.0,
                    child: IgnorePointer(
                      ignoring: _filterMode == _FilterMode.allTime,
                      child: IconButton(
                        icon: Icon(Icons.chevron_left, color: headerIconColor),
                        onPressed: _goBack,
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickPeriod,
                      child: Center(
                        child: Text(
                          _periodLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: headerTextColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: _filterMode == _FilterMode.allTime ? 0.0 : 1.0,
                    child: IgnorePointer(
                      ignoring: _filterMode == _FilterMode.allTime,
                      child: IconButton(
                        icon: Icon(
                          Icons.chevron_right,
                          color: _canGoForward
                              ? headerIconColor
                              : headerIconColor.withValues(alpha: 0.3),
                        ),
                        onPressed: _canGoForward ? _goForward : null,
                      ),
                    ),
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
                      textColor: headerTextColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _AnalyticsTile(
                      icon: Icons.arrow_downward_rounded,
                      amount: expenses,
                      color: const Color(0xFFF87171),
                      textColor: headerTextColor,
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
                      textColor: headerTextColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        Divider(
            height: 1, thickness: 1, color: theme.colorScheme.outlineVariant),

        // ── Transaction list ───────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Column(
              children: [
                // Reminders pinned above the transaction list
                _RemindersSection(
                  reminders: _filteredReminders,
                  accounts: _accounts,
                  txCategories: _txCategories,
                  accountTypes: _accountTypes,
                  accountCategories: _accountCategories,
                  onTap: (r) => _openReminderReceipt(r),
                  onDelete: (r) async {
                    await _db.deleteReminder(r);
                    await _load();
                  },
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            _transactions.isEmpty
                                ? 'No transactions yet. Add one!'
                                : 'No transactions for this period.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        )
                      : _buildGroupedList(filtered, theme),
                ),
              ],
            ),
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
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: 2, left: indented ? 12 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Divider(
            height: 1,
            thickness: 0.5,
            indent: 0,
            endIndent: 0,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
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
            '${currencySymbolNotifier.value}${_fmt(amount.abs())}',
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

// ── Period picker dialog ───────────────────────────────────────────────────────
//
// A centred dialog that lets the user pick both a filter mode (Daily / Weekly /
// Monthly / Yearly) and an exact anchor date.  Returns a named record so the
// caller gets both values atomically.

class _PeriodPickerDialog extends StatefulWidget {
  final _FilterMode currentMode;
  final DateTime currentAnchor;
  final DateTime? customStart;
  final DateTime? customEnd;

  const _PeriodPickerDialog({
    required this.currentMode,
    required this.currentAnchor,
    this.customStart,
    this.customEnd,
  });

  @override
  State<_PeriodPickerDialog> createState() => _PeriodPickerDialogState();
}

class _PeriodPickerDialogState extends State<_PeriodPickerDialog> {
  late _FilterMode _mode;
  late DateTime _anchor;

  // For the inline calendar grid
  late DateTime _calendarMonth; // which month the mini-calendar is showing

  // Custom date range
  DateTime? _customStart;
  DateTime? _customEnd;

  static const _modes = [
    (_FilterMode.daily, 'Day'),
    (_FilterMode.weekly, 'Week'),
    (_FilterMode.monthly, 'Month'),
    (_FilterMode.yearly, 'Year'),
    (_FilterMode.allTime, 'All'),
    (_FilterMode.custom, 'Custom'),
  ];

  @override
  void initState() {
    super.initState();
    _mode = widget.currentMode;
    _anchor = widget.currentAnchor;
    _calendarMonth = DateTime(_anchor.year, _anchor.month);
    _customStart = widget.customStart;
    _customEnd = widget.customEnd;
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
      case _FilterMode.allTime:
        return false;
      case _FilterMode.custom:
        if (_customStart == null && _customEnd == null) return false;
        final day = DateTime(d.year, d.month, d.day);
        final start = _customStart != null
            ? DateTime(
                _customStart!.year, _customStart!.month, _customStart!.day)
            : null;
        final end = _customEnd != null
            ? DateTime(_customEnd!.year, _customEnd!.month, _customEnd!.day)
            : null;
        if (start != null && end != null) {
          return !day.isBefore(start) && !day.isAfter(end);
        } else if (start != null) {
          return _isSameDay(day, start);
        } else if (end != null) {
          return _isSameDay(day, end);
        }
        return false;
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
        case _FilterMode.allTime:
          break;
        case _FilterMode.custom:
          // First tap sets start, second tap sets end (if after start), third resets
          final day = DateTime(d.year, d.month, d.day);
          if (_customStart == null ||
              (_customEnd != null) ||
              day.isBefore(_customStart!)) {
            _customStart = day;
            _customEnd = null;
          } else if (_isSameDay(day, _customStart!)) {
            _customStart = null;
            _customEnd = null;
          } else {
            _customEnd = day;
          }
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
      case _FilterMode.allTime:
        return 'All Time';
      case _FilterMode.custom:
        if (_customStart == null && _customEnd == null) {
          return 'Tap to select start date';
        } else if (_customStart != null && _customEnd == null) {
          return 'From ${DateFormat('MMM d, yyyy').format(_customStart!)} — tap end date';
        } else if (_customStart != null && _customEnd != null) {
          return '${DateFormat('MMM d, yyyy').format(_customStart!)} – ${DateFormat('MMM d, yyyy').format(_customEnd!)}';
        }
        return 'Custom Range';
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

            // ── Unified nav row (always present for stable dialog height) ─
            Opacity(
              opacity: _mode == _FilterMode.allTime ? 0.0 : 1.0,
              child: IgnorePointer(
                ignoring: _mode == _FilterMode.allTime,
                child: Builder(builder: (_) {
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
                      onBack = () => setState(() => _calendarMonth = DateTime(
                          _calendarMonth.year - 1, _calendarMonth.month));
                      onForward = () => setState(() => _calendarMonth =
                          DateTime(
                              _calendarMonth.year + 1, _calendarMonth.month));
                    case _FilterMode.yearly:
                      navLabel = '$decadeStart – ${decadeStart + 9}';
                      labelFontSize = 15;
                      onBack = () => setState(() => _calendarMonth =
                          DateTime(_calendarMonth.year - 10, 1));
                      onForward = () => setState(() => _calendarMonth =
                          DateTime(_calendarMonth.year + 10, 1));
                    default:
                      // Daily / Weekly / Custom — navigate by month
                      navLabel = _calendarMonthLabel();
                      labelFontSize = 13;
                      onBack = () => setState(() => _calendarMonth = DateTime(
                          _calendarMonth.year, _calendarMonth.month - 1));
                      onForward = () => setState(() => _calendarMonth =
                          DateTime(
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
                          // ignore: unnecessary_null_comparison
                          color: onForward == null
                              ? theme.colorScheme.onSurface
                                  .withValues(alpha: 0.25)
                              : null,
                        ),
                        onPressed: onForward,
                      ),
                    ],
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),

            // ── Mode-specific picker body (fixed height = tallest mode) ────
            SizedBox(
              height: 240,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_mode == _FilterMode.allTime) ...[
                    // All Time: no date selection needed
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.all_inclusive,
                          size: 48,
                          color: primary.withValues(alpha: 0.35),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Showing all transactions',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ] else if (_mode == _FilterMode.custom) ...[
                    // Custom range: weekday header + tappable day grid
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

                              final highlighted = _isHighlighted(d);
                              final isStart = _customStart != null &&
                                  _isSameDay(d, _customStart!);
                              final isEnd = _customEnd != null &&
                                  _isSameDay(d, _customEnd!);
                              final isToday = _isSameDay(d, now);

                              Color? bgColor;
                              Color textColor = theme.colorScheme.onSurface;

                              if (isStart || isEnd) {
                                bgColor = primary.withValues(alpha: 0.85);
                                textColor = theme.colorScheme.onPrimary;
                              } else if (highlighted) {
                                bgColor = primary.withValues(alpha: 0.12);
                                textColor = primary;
                              } else if (isToday) {
                                textColor = primary;
                              }

                              return Expanded(
                                child: GestureDetector(
                                  onTap: () => _onDayTapped(d),
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
                                          fontWeight: highlighted ||
                                                  isToday ||
                                                  isStart ||
                                                  isEnd
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
                  ] else if (_mode == _FilterMode.monthly) ...[
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
                              final isSelected =
                                  _anchor.year == _calendarMonth.year &&
                                      _anchor.month == monthIdx;
                              final isCurrentMonth =
                                  _calendarMonth.year == now.year &&
                                      monthIdx == now.month;
                              Color textColor = isSelected
                                  ? primary
                                  : isCurrentMonth
                                      ? primary
                                      : theme.colorScheme.onSurface;
                              return Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _anchor =
                                        DateTime(_calendarMonth.year, monthIdx);
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
                        final isSelected = _anchor.year == yr;
                        final isCurrentYear = yr == now.year;
                        final Color textColor = isSelected
                            ? primary
                            : isCurrentYear
                                ? primary
                                : theme.colorScheme.onSurface;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _anchor = DateTime(yr)),
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

                              final highlighted = _isHighlighted(d);
                              final isToday = _isSameDay(d, now);

                              Color? bgColor;
                              Color textColor = theme.colorScheme.onSurface;

                              if (highlighted) {
                                bgColor = primary.withValues(alpha: 0.15);
                                textColor = primary;
                              } else if (isToday) {
                                textColor = primary;
                              }

                              return Expanded(
                                child: GestureDetector(
                                  onTap: () {
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
                    onPressed: () => Navigator.pop(context, (
                      mode: _mode,
                      anchor: _anchor,
                      customStart: _customStart,
                      customEnd: _customEnd,
                    )),
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

// ── Reminders section (pinned above the transaction list) ─────────────────────

class _RemindersSection extends StatelessWidget {
  final List<ReminderTransaction> reminders;
  final List<Account> accounts;
  final List<WalletCategory> txCategories;
  final List<WalletCategory> accountTypes;
  final List<WalletCategory> accountCategories;
  final void Function(ReminderTransaction) onTap;
  final void Function(ReminderTransaction) onDelete;

  const _RemindersSection({
    required this.reminders,
    required this.accounts,
    required this.txCategories,
    required this.accountTypes,
    required this.accountCategories,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (reminders.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sectionYellow = isDark
        ? const Color(0xFFFFD54F) // amber-300 for dark
        : const Color(0xFFF59E0B); // amber-500 for light

    // Sort: pending overdue first, then pending by due date, done last.
    final now = DateTime.now();
    // ignore: unused_local_variable
    final today = DateTime(now.year, now.month, now.day);

    final sorted = [...reminders]..sort((a, b) {
        if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
        final da = DateTime.tryParse(a.dueDate) ?? DateTime(2100);
        final db2 = DateTime.tryParse(b.dueDate) ?? DateTime(2100);
        return da.compareTo(db2);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: sectionYellow.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.notifications_outlined,
                    size: 14, color: sectionYellow),
              ),
              const SizedBox(width: 8),
              Text(
                'REMINDERS',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: sectionYellow,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: sectionYellow.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${sorted.length}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: sectionYellow,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Reminder cards ─────────────────────────────────────────────────
        ...() {
          final widgets = <Widget>[];
          for (int i = 0; i < sorted.length; i++) {
            final r = sorted[i];
            widgets.add(_ReminderListItem(
              reminder: r,
              accounts: accounts,
              txCategories: txCategories,
              onTap: () => onTap(r),
              onDelete: () => onDelete(r),
            ));
            if (i < sorted.length - 1) {
              widgets.add(Divider(
                height: 1,
                thickness: 0.5,
                indent: 12,
                endIndent: 12,
                color: Colors.grey.withValues(alpha: 0.25),
              ));
            }
          }
          return widgets;
        }(),

        // ── Section divider ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Divider(
            height: 1,
            thickness: 1.5,
            color: sectionYellow.withValues(alpha: 0.25),
          ),
        ),
      ],
    );
  }
}

// ── Reminder list item card ───────────────────────────────────────────────────

final _rFmt = NumberFormat('#,##0.00', 'en_PH');
String _fmtR(double v) => _rFmt.format(v);

class _ReminderListItem extends StatelessWidget {
  final ReminderTransaction reminder;
  final List<Account> accounts;
  final List<WalletCategory> txCategories;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ReminderListItem({
    required this.reminder,
    required this.accounts,
    required this.txCategories,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime.tryParse(reminder.dueDate);
    final isOverdue = !reminder.isDone && due != null && due.isBefore(today);
    final isDueToday = due != null &&
        due.year == today.year &&
        due.month == today.month &&
        due.day == today.day;
    final isIncome = reminder.type == 'income';
    final typeColor = isIncome ? Colors.green.shade600 : Colors.red.shade600;

    // Yellow palette: warmer amber in dark mode, classic amber in light
    final reminderYellow = isDark
        ? const Color(0xFFFFD54F) // amber-300 — readable on dark surfaces
        : const Color(0xFFF59E0B); // amber-500 — standard yellow-amber

    Color bgColor;
    if (reminder.isDone) {
      bgColor = cs.surfaceContainerHighest.withValues(alpha: 0.3);
    } else if (isOverdue) {
      bgColor = Colors.orange.withValues(alpha: 0.08);
    } else if (isDueToday) {
      bgColor = reminderYellow.withValues(alpha: isDark ? 0.12 : 0.06);
    } else {
      bgColor = reminderYellow.withValues(alpha: isDark ? 0.07 : 0.03);
    }

    final dueDateStr = due != null
        ? (isDueToday
            ? 'Today'
            : isOverdue
                ? 'Due ${DateFormat('MMM d, EEE').format(due)}'
                : DateFormat('MMM d, EEE').format(due))
        : '';

    final catObj = txCategories.cast<WalletCategory?>().firstWhere(
          (c) => c?.name == reminder.category,
          orElse: () => null,
        );
    final catIcon = catObj?.iconData ?? Icons.label_outline;

    final Account? account = reminder.accountId != null
        ? accounts.cast<Account?>().firstWhere(
              (a) => a?.id == reminder.accountId,
              orElse: () => null,
            )
        : null;

    return Dismissible(
      key: Key('reminder_${reminder.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async => true,
      onDismissed: (_) => onDelete(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: reminder.isDone ? 0.5 : 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  // ── Bell icon ───────────────────────────────────────────
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: reminder.isDone
                          ? cs.outlineVariant.withValues(alpha: 0.3)
                          : reminderYellow.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      reminder.isDone
                          ? Icons.notifications_off_outlined
                          : isOverdue
                              ? Icons.warning_amber_rounded
                              : Icons.notifications_active_rounded,
                      size: 20,
                      color: reminder.isDone
                          ? cs.onSurfaceVariant
                          : isOverdue
                              ? Colors.orange.shade700
                              : reminderYellow,
                    ),
                  ),
                  const SizedBox(width: 10),

                  // ── Info ────────────────────────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                reminder.title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: reminder.isDone
                                      ? cs.onSurfaceVariant
                                      : cs.onSurface,
                                  decoration: reminder.isDone
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Done badge
                            if (reminder.isDone)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Done',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(catIcon,
                                size: 11,
                                color: typeColor.withValues(alpha: 0.7)),
                            const SizedBox(width: 4),
                            Text(
                              reminder.category,
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            if (account != null) ...[
                              Text(' · ',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant)),
                              Icon(Icons.account_balance_wallet_outlined,
                                  size: 11, color: cs.onSurfaceVariant),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  account.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // ── Amount + due date ────────────────────────────────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (reminder.amount > 0)
                        Text(
                          '${isIncome ? '+' : '−'}${currencySymbolNotifier.value}${_fmtR(reminder.amount)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: reminder.isDone
                                ? cs.onSurfaceVariant
                                : typeColor,
                          ),
                        )
                      else
                        Text(
                          '—',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        dueDateStr,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: isOverdue
                              ? Colors.orange.shade700
                              : isDueToday
                                  ? reminderYellow
                                  : cs.onSurfaceVariant,
                        ),
                      ),
                      if (reminder.repeat != ReminderRepeat.none)
                        Row(
                          children: [
                            Icon(Icons.repeat,
                                size: 10, color: cs.onSurfaceVariant),
                            const SizedBox(width: 2),
                            Text(
                              reminder.repeat.label,
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ), // Padding
    ); // Dismissible
  }
}
