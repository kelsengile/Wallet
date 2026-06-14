import 'package:flutter/material.dart';
import 'account_model.dart';
import 'category_model.dart';

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
  ///
  /// [categories] should be the user's current transaction categories
  /// (excluding the system "Transfer" category — see
  /// [CategoryRegistry.selectableTransactionCategories]).
  ///
  /// Returns a [WalletTransaction] if the user confirmed, `null` otherwise.
  static Future<WalletTransaction?> showDialog(
    BuildContext context, {
    required List<Account> accounts,
    required List<WalletCategory> categories,
    required List<WalletCategory> accountTypes,
    WalletTransaction? existing,
    required String type,
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
        categories: categories,
        accountTypes: accountTypes,
        existing: existing,
        type: type,
      ),
    );
  }
}

// ── Transfer result ───────────────────────────────────────────────────────────

/// Holds the two legs of a transfer so the caller can persist them atomically.
class TransferResult {
  final int fromAccountId;
  final int toAccountId;
  final double amount;
  final String note;
  final String date;

  const TransferResult({
    required this.fromAccountId,
    required this.toAccountId,
    required this.amount,
    required this.note,
    required this.date,
  });
}

// ── Transfer dialog factory ───────────────────────────────────────────────────

extension WalletTransactionTransfer on WalletTransaction {
  /// Shows a transfer modal bottom sheet.
  /// Returns a [TransferResult] if the user confirmed, `null` otherwise.
  static Future<TransferResult?> showTransferDialog(
    BuildContext context, {
    required List<Account> accounts,
    required List<WalletCategory> accountTypes,
    int? preselectedFromId,
  }) {
    return showModalBottomSheet<TransferResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _TransferForm(
        accounts: accounts,
        accountTypes: accountTypes,
        preselectedFromId: preselectedFromId,
      ),
    );
  }
}

// ── Bottom-sheet form ─────────────────────────────────────────────────────────

class _TransactionForm extends StatefulWidget {
  final List<Account> accounts;
  final List<WalletCategory> categories;
  final List<WalletCategory> accountTypes;
  final WalletTransaction? existing;
  final String type;

  const _TransactionForm({
    required this.accounts,
    required this.categories,
    required this.accountTypes,
    this.existing,
    required this.type,
  });

  @override
  State<_TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<_TransactionForm> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  late final String _type;
  String? _category;
  int? _accountId;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _amountCtrl = TextEditingController(
      text: e != null ? e.amount.toStringAsFixed(2) : '',
    );
    _noteCtrl = TextEditingController(text: e?.note ?? '');
    _type = widget.type;

    if (e != null) {
      // Editing: restore saved values
      final inType =
          widget.categories.where((c) => c.subType == _type).toList();
      final categoryNames = inType.map((c) => c.name).toSet();
      _category = categoryNames.contains(e.category) ? e.category : null;
      _accountId = e.accountId;
    } else {
      // New transaction: leave pickers empty
      _category = null;
      _accountId = null;
    }
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
    if (_category == null) return;

    final tx = WalletTransaction(
      id: widget.existing?.id,
      title: _titleCtrl.text.trim(),
      amount: amount,
      date: widget.existing?.date ?? DateTime.now().toIso8601String(),
      type: _type,
      category: _category!,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      accountId: _accountId,
    );
    Navigator.pop(context, tx);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Color get _accentColor =>
      _type == 'income' ? Colors.green : Colors.red.shade600;

  /// Opens the category picker modal (mirrors _TypePickerSheet from accounts_page).
  Future<void> _pickCategory(BuildContext context) async {
    final theme = Theme.of(context);
    final inType = widget.categories.where((c) => c.subType == _type).toList();
    if (inType.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              Text('Category',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: inType.map((cat) {
                  final isSelected = cat.name == _category;
                  final color = _accentColor;
                  return GestureDetector(
                    onTap: () => Navigator.pop(ctx, cat.name),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? color.withValues(alpha: 0.15)
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? color : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(cat.iconData,
                              color: isSelected
                                  ? color
                                  : theme.colorScheme.onSurfaceVariant,
                              size: 18),
                          const SizedBox(width: 8),
                          Text(
                            _capitalize(cat.name),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? color
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.check_circle_rounded,
                                size: 15, color: color),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _category = picked);
  }

  /// Opens the account picker modal with accounts grouped by account type.
  Future<void> _pickAccount(BuildContext context) async {
    final theme = Theme.of(context);
    if (widget.accounts.isEmpty) return;

    // Build a map from type name → WalletCategory for icon lookup
    final typeIconMap = {
      for (final t in widget.accountTypes) t.name: t,
    };

    // Group accounts by their type
    final Map<String, List<Account>> grouped = {};
    for (final a in widget.accounts) {
      (grouped[a.type] ??= []).add(a);
    }

    final picked = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              Text('Account',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ...grouped.entries.map((entry) {
                final typeName = entry.key;
                final accs = entry.value;
                final typeCategory = typeIconMap[typeName];
                final typeIcon = typeCategory?.iconData ??
                    Icons.account_balance_wallet_outlined;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section header
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Icon(typeIcon,
                              size: 15,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(
                            typeName,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: accs.map((a) {
                        final isSelected = a.id == _accountId;
                        final color = theme.colorScheme.primary;
                        return GestureDetector(
                          onTap: () => Navigator.pop(ctx, a.id),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? color.withValues(alpha: 0.12)
                                  : theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? color : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(typeIcon,
                                    color: isSelected
                                        ? color
                                        : theme.colorScheme.onSurfaceVariant,
                                    size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  a.name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? color
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 6),
                                  Icon(Icons.check_circle_rounded,
                                      size: 15, color: color),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _accountId = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;
    final accent = _accentColor;

    // Resolve display names for picker buttons
    final inType = widget.categories.where((c) => c.subType == _type).toList();
    final selectedCat = _category != null
        ? firstWhereOrNull(inType, (c) => c.name == _category)
        : null;
    final selectedAcc = _accountId != null
        ? widget.accounts
            .cast<Account?>()
            .firstWhere((a) => a?.id == _accountId, orElse: () => null)
        : null;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
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
            isEdit
                ? 'Edit ${_type == 'income' ? 'Income' : 'Expense'}'
                : 'New ${_type == 'income' ? 'Income' : 'Expense'}',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // ── Title ────────────────────────────────────────────────────────
          RepaintBoundary(
            child: TextField(
              controller: _titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.title),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Amount ───────────────────────────────────────────────────────
          RepaintBoundary(
            child: TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount (₱)',
                border: const OutlineInputBorder(),
                prefixIcon: Icon(Icons.payments_outlined, color: accent),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Category & Account — side-by-side picker buttons ─────────────
          Row(
            children: [
              // Category picker button
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickCategory(context),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Category',
                      border: const OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(
                        borderSide:
                            BorderSide(color: theme.colorScheme.outline),
                      ),
                      prefixIcon: Icon(
                        selectedCat != null
                            ? selectedCat.iconData
                            : Icons.touch_app_outlined,
                        color: selectedCat != null
                            ? accent
                            : theme.colorScheme.onSurfaceVariant,
                        size: 18,
                      ),
                      suffixIcon: Icon(Icons.expand_more_rounded,
                          size: 20, color: theme.colorScheme.onSurfaceVariant),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 16),
                    ),
                    isEmpty: selectedCat == null,
                    child: selectedCat != null
                        ? Text(
                            _capitalize(selectedCat.name),
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(color: theme.colorScheme.onSurface),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Account picker button
              Expanded(
                child: GestureDetector(
                  onTap: widget.accounts.isNotEmpty
                      ? () => _pickAccount(context)
                      : null,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Account',
                      border: const OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(
                        borderSide:
                            BorderSide(color: theme.colorScheme.outline),
                      ),
                      prefixIcon: Icon(
                        selectedAcc != null
                            ? (firstWhereOrNull(widget.accountTypes,
                                        (t) => t.name == selectedAcc.type)
                                    ?.iconData ??
                                Icons.account_balance_wallet)
                            : Icons.touch_app_outlined,
                        color: selectedAcc != null
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        size: 18,
                      ),
                      suffixIcon: Icon(Icons.expand_more_rounded,
                          size: 20, color: theme.colorScheme.onSurfaceVariant),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 16),
                    ),
                    isEmpty: selectedAcc == null,
                    child: selectedAcc != null
                        ? Text(
                            selectedAcc.name,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(color: theme.colorScheme.onSurface),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Note — taller box ─────────────────────────────────────────────
          RepaintBoundary(
            child: TextField(
              controller: _noteCtrl,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              minLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: Icon(Icons.note_outlined),
                ),
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Submit ────────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submit,
              icon: Icon(isEdit ? Icons.save : Icons.add),
              label: Text(isEdit ? 'Save Changes' : 'Add Transaction'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Transfer form ─────────────────────────────────────────────────────────────

class _TransferForm extends StatefulWidget {
  final List<Account> accounts;
  final List<WalletCategory> accountTypes;
  final int? preselectedFromId;

  const _TransferForm({
    required this.accounts,
    required this.accountTypes,
    this.preselectedFromId,
  });

  @override
  State<_TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends State<_TransferForm> {
  late int? _fromId;
  late int? _toId;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Start with empty pickers; user must explicitly choose
    _fromId = widget.preselectedFromId;
    _toId = null;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_fromId == null || _toId == null) return;
    if (_fromId == _toId) return;
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) return;

    Navigator.pop(
      context,
      TransferResult(
        fromAccountId: _fromId!,
        toAccountId: _toId!,
        amount: amount,
        note: _noteCtrl.text.trim(),
        date: DateTime.now().toIso8601String(),
      ),
    );
  }

  /// Opens a modal sheet to pick an account (grouped by type), excluding [excludeId].
  Future<int?> _pickTransferAccount(
    BuildContext context, {
    required String label,
    required int? current,
    int? excludeId,
  }) {
    final theme = Theme.of(context);
    const teal = Color(0xFF0D9488);

    final typeIconMap = {
      for (final t in widget.accountTypes) t.name: t,
    };

    final Map<String, List<Account>> grouped = {};
    for (final a in widget.accounts) {
      (grouped[a.type] ??= []).add(a);
    }

    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              Text(label,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ...grouped.entries.map((entry) {
                final typeName = entry.key;
                final accs = entry.value;
                final typeCategory = typeIconMap[typeName];
                final typeIcon = typeCategory?.iconData ??
                    Icons.account_balance_wallet_outlined;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Icon(typeIcon,
                              size: 15,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(
                            typeName,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: accs.map((a) {
                        final isExcluded = a.id == excludeId;
                        final isSelected = a.id == current;
                        return GestureDetector(
                          onTap: isExcluded
                              ? null
                              : () => Navigator.pop(ctx, a.id),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? teal.withValues(alpha: 0.12)
                                  : isExcluded
                                      ? theme
                                          .colorScheme.surfaceContainerHighest
                                          .withValues(alpha: 0.4)
                                      : theme
                                          .colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? teal : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(typeIcon,
                                    color: isExcluded
                                        ? theme.colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.35)
                                        : isSelected
                                            ? teal
                                            : theme
                                                .colorScheme.onSurfaceVariant,
                                    size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  a.name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isExcluded
                                        ? theme.colorScheme.onSurface
                                            .withValues(alpha: 0.35)
                                        : isSelected
                                            ? teal
                                            : theme.colorScheme.onSurface,
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.check_circle_rounded,
                                      size: 15, color: teal),
                                ],
                                if (isExcluded) ...[
                                  const SizedBox(width: 6),
                                  Icon(Icons.block_rounded,
                                      size: 13,
                                      color: theme.colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.35)),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const teal = Color(0xFF0D9488);

    final fromAcc = widget.accounts
        .cast<Account?>()
        .firstWhere((a) => a?.id == _fromId, orElse: () => null);
    final toAcc = widget.accounts
        .cast<Account?>()
        .firstWhere((a) => a?.id == _toId, orElse: () => null);

    // Helper: builds a teal-accented picker button for From/To
    Widget accountPickerButton({
      required String label,
      required Account? selected,
      required VoidCallback onTap,
    }) {
      final isSet = selected != null;
      final typeIcon = isSet
          ? (firstWhereOrNull(
                      widget.accountTypes, (t) => t.name == selected.type)
                  ?.iconData ??
              Icons.account_balance_wallet)
          : Icons.touch_app_outlined;
      return GestureDetector(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: theme.colorScheme.outline),
            ),
            prefixIcon: Icon(
              typeIcon,
              color: isSet ? teal : theme.colorScheme.onSurfaceVariant,
              size: 18,
            ),
            suffixIcon: Icon(Icons.expand_more_rounded,
                size: 20, color: theme.colorScheme.onSurfaceVariant),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          ),
          isEmpty: !isSet,
          child: isSet
              ? Text(
                  selected.name,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : const SizedBox.shrink(),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.swap_horiz, color: teal, size: 22),
              ),
              const SizedBox(width: 10),
              Text(
                'Transfer Funds',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── From / swap / To — same row ───────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: accountPickerButton(
                  label: 'From',
                  selected: fromAcc,
                  onTap: () async {
                    final picked = await _pickTransferAccount(
                      context,
                      label: 'From Account',
                      current: _fromId,
                      excludeId: _toId,
                    );
                    if (picked != null) setState(() => _fromId = picked);
                  },
                ),
              ),
              // Swap button between From and To
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: GestureDetector(
                  onTap: () => setState(() {
                    final tmp = _fromId;
                    _fromId = _toId;
                    _toId = tmp;
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: teal.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                      border: Border.all(color: teal.withValues(alpha: 0.35)),
                    ),
                    child: const Icon(Icons.swap_horiz, color: teal, size: 18),
                  ),
                ),
              ),
              Expanded(
                child: accountPickerButton(
                  label: 'To',
                  selected: toAcc,
                  onTap: () async {
                    final picked = await _pickTransferAccount(
                      context,
                      label: 'To Account',
                      current: _toId,
                      excludeId: _fromId,
                    );
                    if (picked != null) setState(() => _toId = picked);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Amount ────────────────────────────────────────────────────────
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

          // ── Note — taller box ─────────────────────────────────────────────
          TextField(
            controller: _noteCtrl,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 3,
            minLines: 3,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              border: OutlineInputBorder(),
              prefixIcon: Padding(
                padding: EdgeInsets.only(bottom: 40),
                child: Icon(Icons.note_outlined),
              ),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),

          // Validation hint
          if (_fromId != null && _toId != null && _fromId == _toId)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Source and destination accounts must be different.',
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Transfer'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: teal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
