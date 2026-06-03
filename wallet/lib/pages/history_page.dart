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
    setState(() {
      _transactions = txs;
      _accounts = accounts;
      _loading = false;
    });
  }

  void _showAddTransactionDialog() {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String type = 'expense';
    String category = 'Food';
    int? accountId = _accounts.isNotEmpty ? _accounts.first.id : null;

    const categories = [
      'Food',
      'Transport',
      'Shopping',
      'Bills',
      'Health',
      'Entertainment',
      'Salary',
      'Other',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Add Transaction'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Type toggle
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'expense', label: Text('Expense')),
                    ButtonSegment(value: 'income', label: Text('Income')),
                  ],
                  selected: {type},
                  onSelectionChanged: (v) => setS(() => type = v.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  decoration: const InputDecoration(labelText: 'Amount'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  items: categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setS(() => category = v ?? 'Other'),
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                const SizedBox(height: 8),
                if (_accounts.isNotEmpty)
                  DropdownButtonFormField<int>(
                    initialValue: accountId,
                    items: _accounts
                        .map(
                          (a) => DropdownMenuItem(
                            value: a.id,
                            child: Text(a.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setS(() => accountId = v),
                    decoration: const InputDecoration(labelText: 'Account'),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty ||
                    amountCtrl.text.trim().isEmpty) {
                  return;
                }
                final tx = WalletTransaction(
                  title: titleCtrl.text.trim(),
                  amount: double.tryParse(amountCtrl.text.trim()) ?? 0.0,
                  date: DateTime.now().toIso8601String(),
                  type: type,
                  category: category,
                  note: noteCtrl.text.trim(),
                );
                // Attach account_id via toMap override below
                final map = tx.toMap();
                if (accountId != null) map['account_id'] = accountId;
                final db = await _db.database;
                await db.insert('transactions', map);
                await _db.adjustAccountBalance(
                  accountId ?? 1,
                  type == 'income' ? tx.amount : -tx.amount,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
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
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton.filled(
                onPressed: _showAddTransactionDialog,
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
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
