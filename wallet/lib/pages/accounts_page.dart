import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/account_model.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  final _db = DatabaseHelper.instance;
  List<Account> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accounts = await _db.getAllAccounts();
    setState(() {
      _accounts = accounts;
      _loading = false;
    });
  }

  double get _totalBalance => _accounts.fold(0.0, (sum, a) => sum + a.balance);

  void _showAddAccountDialog() {
    final nameCtrl = TextEditingController();
    final balanceCtrl = TextEditingController();
    String selectedType = 'cash';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Account Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: balanceCtrl,
              decoration: const InputDecoration(labelText: 'Initial Balance'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedType,
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'bank', child: Text('Bank')),
                DropdownMenuItem(value: 'e-wallet', child: Text('E-Wallet')),
              ],
              onChanged: (v) => selectedType = v ?? 'cash',
              decoration: const InputDecoration(labelText: 'Type'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await _db.insertAccount(
                Account(
                  name: nameCtrl.text.trim(),
                  balance: double.tryParse(balanceCtrl.text.trim()) ?? 0.0,
                  type: selectedType,
                  colorHex: '#6366F1',
                  icon: 'wallet',
                ),
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _loadAccounts();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
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
          // Total balance card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.colorScheme.primary, theme.colorScheme.tertiary],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Balance',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₱ ${_totalBalance.toStringAsFixed(2)}',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'My Accounts',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton.filled(
                onPressed: _showAddAccountDialog,
                icon: const Icon(Icons.add),
                tooltip: 'Add account',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _accounts.isEmpty
                ? const Center(child: Text('No accounts yet. Add one!'))
                : ListView.separated(
                    itemCount: _accounts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final a = _accounts[i];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Icon(
                              Icons.account_balance_wallet,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          title: Text(
                            a.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            a.type.toUpperCase(),
                            style: theme.textTheme.labelSmall,
                          ),
                          trailing: Text(
                            '₱ ${a.balance.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: a.balance >= 0 ? Colors.green : Colors.red,
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
