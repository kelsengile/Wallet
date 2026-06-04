import 'package:flutter/material.dart';
import 'account_model.dart';

// ── Category metadata (single source of truth) ────────────────────────────────

const kTransactionCategories = [
  'Food',
  'Transport',
  'Shopping',
  'Bills',
  'Health',
  'Entertainment',
  'Salary',
  'Savings',
  'Other',
];

const kTransactionCategoryIcons = <String, IconData>{
  'Food': Icons.restaurant,
  'Transport': Icons.directions_car,
  'Shopping': Icons.shopping_bag,
  'Bills': Icons.receipt_long,
  'Health': Icons.favorite,
  'Entertainment': Icons.movie,
  'Salary': Icons.work,
  'Savings': Icons.savings,
  'Other': Icons.category,
};

// ── Model ─────────────────────────────────────────────────────────────────────

class WalletTransaction {
  final int? id;
  final String title;
  final double amount;
  final String date;
  final String type; // 'income' or 'expense'
  final String category;
  final String? note;
  final int? accountId;

  WalletTransaction({
    this.id,
    required this.title,
    required this.amount,
    required this.date,
    required this.type,
    required this.category,
    this.note,
    this.accountId,
  });

  WalletTransaction copyWith({
    int? id,
    String? title,
    double? amount,
    String? date,
    String? type,
    String? category,
    String? note,
    int? accountId,
  }) {
    return WalletTransaction(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      type: type ?? this.type,
      category: category ?? this.category,
      note: note ?? this.note,
      accountId: accountId ?? this.accountId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'amount': amount,
      'date': date,
      'type': type,
      'category': category,
      'note': note ?? '',
      if (accountId != null) 'account_id': accountId,
    };
  }

  factory WalletTransaction.fromMap(Map<String, dynamic> map) {
    return WalletTransaction(
      id: map['id'] as int?,
      title: map['title'] as String,
      amount: (map['amount'] as num).toDouble(),
      date: map['date'] as String,
      type: map['type'] as String,
      category: map['category'] as String,
      note: map['note'] as String?,
      accountId: map['account_id'] as int?,
    );
  }

  // ── Dialog factory — mirrors the Account bottom-sheet pattern ─────────────

  /// Shows an add/edit transaction modal bottom sheet.
  /// Returns a [WalletTransaction] if the user confirmed, `null` otherwise.
  static Future<WalletTransaction?> showDialog(
    BuildContext context, {
    required List<Account> accounts,
    WalletTransaction? existing,
  }) {
    return showModalBottomSheet<WalletTransaction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _TransactionForm(
        accounts: accounts,
        existing: existing,
      ),
    );
  }
}

// ── Bottom-sheet form ─────────────────────────────────────────────────────────

class _TransactionForm extends StatefulWidget {
  final List<Account> accounts;
  final WalletTransaction? existing;

  const _TransactionForm({required this.accounts, this.existing});

  @override
  State<_TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<_TransactionForm> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  late String _type;
  late String _category;
  late int? _accountId;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _amountCtrl = TextEditingController(
      text: e != null ? e.amount.toStringAsFixed(2) : '',
    );
    _noteCtrl = TextEditingController(text: e?.note ?? '');
    _type = e?.type ?? 'expense';
    _category = e?.category ?? 'Food';
    _accountId = e?.accountId ??
        (widget.accounts.isNotEmpty ? widget.accounts.first.id : null);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_titleCtrl.text.trim().isEmpty) return;
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) return;

    final tx = WalletTransaction(
      id: widget.existing?.id,
      title: _titleCtrl.text.trim(),
      amount: amount,
      date: widget.existing?.date ?? DateTime.now().toIso8601String(),
      type: _type,
      category: _category,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      accountId: _accountId,
    );
    Navigator.pop(context, tx);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            isEdit ? 'Edit Transaction' : 'New Transaction',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // Type toggle
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'expense',
                label: Text('Expense'),
                icon: Icon(Icons.arrow_upward, size: 16),
              ),
              ButtonSegment(
                value: 'income',
                label: Text('Income'),
                icon: Icon(Icons.arrow_downward, size: 16),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() => _type = v.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return _type == 'income' ? Colors.green : Colors.red;
                }
                return null;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return Colors.white;
                return null;
              }),
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _titleCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.title),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount (₱)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 12),

          // Category picker — icon grid (mirrors account type picker style)
          Text('Category', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kTransactionCategories.map((cat) {
              final selected = _category == cat;
              final color = selected
                  ? (_type == 'income'
                      ? Colors.green
                      : theme.colorScheme.primary)
                  : theme.colorScheme.outline;
              return GestureDetector(
                onTap: () => setState(() => _category = cat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: 0.12)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? color : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        kTransactionCategoryIcons[cat] ?? Icons.category,
                        size: 15,
                        color: selected ? color : null,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        cat,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected ? color : null,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          if (widget.accounts.isNotEmpty)
            DropdownButtonFormField<int>(
              value: _accountId,
              items: widget.accounts
                  .map((a) => DropdownMenuItem(
                        value: a.id,
                        child: Text(a.name),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _accountId = v),
              decoration: const InputDecoration(
                labelText: 'Account',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
            ),
          const SizedBox(height: 12),

          TextField(
            controller: _noteCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.note_outlined),
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submit,
              icon: Icon(isEdit ? Icons.save : Icons.add),
              label: Text(isEdit ? 'Save Changes' : 'Add Transaction'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: _type == 'income'
                    ? Colors.green
                    : theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
