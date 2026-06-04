import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/transaction_model.dart';
import '../models/account_model.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _db = DatabaseHelper.instance;
  List<WalletTransaction> _transactions = [];
  List<Account> _accounts = [];
  bool _loading = true;

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

  /// Opens the shared bottom-sheet form from [WalletTransaction.showDialog]
  /// and persists the result via [DatabaseHelper.insertTransaction].
  Future<void> _addTransaction() async {
    final tx = await WalletTransaction.showDialog(
      context,
      accounts: _accounts,
    );
    if (tx == null) return;
    await _db.insertTransaction(tx);
    _load();
  }

  /// Opens the form pre-populated for editing.
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
              IconButton.filled(
                onPressed: _addTransaction,
                icon: const Icon(Icons.add),
                tooltip: 'Add transaction',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _transactions.isEmpty
                ? const Center(child: Text('No transactions yet. Add one!'))
                : ListView.separated(
                    itemCount: _transactions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final tx = _transactions[i];
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
                              '${isIncome ? '+' : '-'} ₱${tx.amount.toStringAsFixed(2)}',
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
