import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/transaction_model.dart';
import '../models/account_model.dart';

final _currencyFmt = NumberFormat('#,##0.00', 'en_PH');
String _fmt(double v) => _currencyFmt.format(v);

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => HistoryPageState();
}

class HistoryPageState extends State<HistoryPage> {
  final _db = DatabaseHelper.instance;
  List<WalletTransaction> _transactions = [];
  List<Account> _accounts = [];
  bool _loading = true;

  String _filterMode = 'all';
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTimeRange? _selectedRange;

  List<WalletTransaction> get _filtered {
    if (_filterMode == 'month') {
      return _transactions.where((tx) {
        final d = DateTime.tryParse(tx.date);
        return d != null &&
            d.year == _selectedMonth.year &&
            d.month == _selectedMonth.month;
      }).toList();
    } else if (_filterMode == 'range' && _selectedRange != null) {
      final start = _selectedRange!.start;
      final end = _selectedRange!.end.add(const Duration(days: 1));
      return _transactions.where((tx) {
        final d = DateTime.tryParse(tx.date);
        return d != null &&
            d.isAfter(start.subtract(const Duration(seconds: 1))) &&
            d.isBefore(end);
      }).toList();
    }
    return _transactions;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final txs = await _db.getAllTransactions();
    final accounts = await _db.getAllAccounts();
    if (!mounted) return;
    setState(() {
      _transactions = txs;
      _accounts = accounts;
      _loading = false;
    });
  }

  Future<void> _pickMonth() async {
    int year = _selectedMonth.year;
    int month = _selectedMonth.month;
    final now = DateTime.now();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Select Month'),
          content: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => setS(() {
                        if (month == 1) {
                          month = 12;
                          year--;
                        } else {
                          month--;
                        }
                      }),
                    ),
                    Text(
                      '${_monthName(month)} $year',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: (year == now.year && month == now.month)
                          ? null
                          : () => setS(() {
                                if (month == 12) {
                                  month = 1;
                                  year++;
                                } else {
                                  month++;
                                }
                              }),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                setState(() {
                  _selectedMonth = DateTime(year, month);
                  _filterMode = 'month';
                });
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedRange,
    );
    if (range != null) {
      setState(() {
        _selectedRange = range;
        _filterMode = 'range';
      });
    }
  }

  String _monthName(int m) => const [
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
      ][m];

  String get _filterLabel {
    if (_filterMode == 'month') {
      return '${_monthName(_selectedMonth.month)} ${_selectedMonth.year}';
    } else if (_filterMode == 'range' && _selectedRange != null) {
      final s = _selectedRange!.start;
      final e = _selectedRange!.end;
      return '${s.day}/${s.month} – ${e.day}/${e.month}';
    }
    return 'All time';
  }

  /// Called by the FAB in main.dart after it inserts a transaction directly.
  Future<void> refresh() => _load();

  Future<void> addTransaction() async {
    final tx = await WalletTransaction.showDialog(
      context,
      accounts: _accounts,
    );
    if (tx == null) return;
    await _db.insertTransaction(tx);
    _load();
  }

  Future<void> _editTransaction(WalletTransaction existing) async {
    final updated = await WalletTransaction.showDialog(
      context,
      accounts: _accounts,
      existing: existing,
    );
    if (updated == null) return;
    await _db.updateTransaction(existing, updated);
    _load();
  }

  Future<void> _deleteTransaction(WalletTransaction tx) async {
    await _db.deleteTransaction(tx);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Transactions',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All time'),
                  selected: _filterMode == 'all',
                  onSelected: (_) => setState(() => _filterMode = 'all'),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: _filterMode == 'month'
                      ? null
                      : const Icon(Icons.calendar_month, size: 16),
                  label: Text(
                    _filterMode == 'month' ? _filterLabel : 'By month',
                  ),
                  selected: _filterMode == 'month',
                  onSelected: (_) => _pickMonth(),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: _filterMode == 'range'
                      ? null
                      : const Icon(Icons.date_range, size: 16),
                  label: Text(
                    _filterMode == 'range' ? _filterLabel : 'Date range',
                  ),
                  selected: _filterMode == 'range',
                  onSelected: (_) => _pickRange(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      _transactions.isEmpty
                          ? 'No transactions yet. Add one!'
                          : 'No transactions for this period.',
                    ),
                  )
                : ListView.separated(
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final tx = _filtered[i];
                      final isIncome = tx.type == 'income';
                      return Dismissible(
                        key: Key('tx_${tx.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => _deleteTransaction(tx),
                        child: Card(
                          child: ListTile(
                            onTap: () => _editTransaction(tx),
                            leading: CircleAvatar(
                              backgroundColor: isIncome
                                  ? Colors.green.shade100
                                  : Colors.red.shade100,
                              child: Icon(
                                isIncome
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                                color: isIncome ? Colors.green : Colors.red,
                              ),
                            ),
                            title: Text(
                              tx.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${tx.category} • ${tx.date.substring(0, 10)}',
                            ),
                            trailing: Text(
                              '${isIncome ? '+' : '-'} ₱${_fmt(tx.amount)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isIncome ? Colors.green : Colors.red,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
