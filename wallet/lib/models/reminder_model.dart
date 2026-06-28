import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../currency.dart';
import 'account_model.dart';
import 'category_model.dart';

// ── Repeat frequency ──────────────────────────────────────────────────────────

enum ReminderRepeat {
  none,
  daily,
  weekly,
  monthly,
  yearly;

  String get label {
    switch (this) {
      case ReminderRepeat.none:
        return 'No repeat';
      case ReminderRepeat.daily:
        return 'Daily';
      case ReminderRepeat.weekly:
        return 'Weekly';
      case ReminderRepeat.monthly:
        return 'Monthly';
      case ReminderRepeat.yearly:
        return 'Yearly';
    }
  }

  IconData get icon {
    switch (this) {
      case ReminderRepeat.none:
        return Icons.remove_circle_outline;
      case ReminderRepeat.daily:
        return Icons.today_outlined;
      case ReminderRepeat.weekly:
        return Icons.view_week_outlined;
      case ReminderRepeat.monthly:
        return Icons.calendar_month_outlined;
      case ReminderRepeat.yearly:
        return Icons.calendar_today_outlined;
    }
  }
}

// ── Model ─────────────────────────────────────────────────────────────────────

class ReminderTransaction {
  final int? id;
  final String title;

  /// Optional expected amount (can be 0 if unknown).
  final double amount;

  /// The due date for this reminder (ISO-8601).
  final String dueDate;

  /// 'income' or 'expense'.
  final String type;
  final String category;
  final String? note;

  /// Optional linked account.
  final int? accountId;

  /// Repeat frequency.
  final ReminderRepeat repeat;

  /// Whether this reminder has been dismissed/acknowledged.
  final bool isDone;

  ReminderTransaction({
    this.id,
    required this.title,
    required this.amount,
    required this.dueDate,
    required this.type,
    required this.category,
    this.note,
    this.accountId,
    this.repeat = ReminderRepeat.none,
    this.isDone = false,
  });

  ReminderTransaction copyWith({
    int? id,
    String? title,
    double? amount,
    String? dueDate,
    String? type,
    String? category,
    Object? note = _sentinel,
    Object? accountId = _sentinel,
    ReminderRepeat? repeat,
    bool? isDone,
  }) {
    return ReminderTransaction(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      dueDate: dueDate ?? this.dueDate,
      type: type ?? this.type,
      category: category ?? this.category,
      note: note == _sentinel ? this.note : note as String?,
      accountId: accountId == _sentinel ? this.accountId : accountId as int?,
      repeat: repeat ?? this.repeat,
      isDone: isDone ?? this.isDone,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'amount': amount,
      'due_date': dueDate,
      'type': type,
      'category': category,
      'note': note ?? '',
      if (accountId != null) 'account_id': accountId,
      'repeat': repeat.name,
      'is_done': isDone ? 1 : 0,
    };
  }

  factory ReminderTransaction.fromMap(Map<String, dynamic> map) {
    return ReminderTransaction(
      id: map['id'] as int?,
      title: map['title'] as String,
      amount: (map['amount'] as num).toDouble(),
      dueDate: map['due_date'] as String,
      type: map['type'] as String,
      category: map['category'] as String,
      note: (map['note'] as String?)?.isEmpty == true
          ? null
          : map['note'] as String?,
      accountId: map['account_id'] as int?,
      repeat: ReminderRepeat.values.firstWhere(
        (r) => r.name == (map['repeat'] as String? ?? 'none'),
        orElse: () => ReminderRepeat.none,
      ),
      isDone: (map['is_done'] as int? ?? 0) == 1,
    );
  }

  // ── Dialog factory ─────────────────────────────────────────────────────────

  /// Shows the add/edit reminder modal bottom sheet.
  /// Returns a [ReminderTransaction] if the user confirmed, `null` otherwise.
  static Future<ReminderTransaction?> showDialog(
    BuildContext context, {
    required List<Account> accounts,
    required List<WalletCategory> categories,
    required List<WalletCategory> accountTypes,
    required List<WalletCategory> accountCategories,
    ReminderTransaction? existing,
    List<String>? typeOrder,
  }) {
    return showModalBottomSheet<ReminderTransaction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ReminderForm(
        accounts: accounts,
        categories: categories,
        accountTypes: accountTypes,
        accountCategories: accountCategories,
        existing: existing,
        typeOrder: typeOrder,
      ),
    );
  }
}

const Object _sentinel = Object();

// ── Bottom-sheet form ─────────────────────────────────────────────────────────

class _ReminderForm extends StatefulWidget {
  final List<Account> accounts;
  final List<WalletCategory> categories;
  final List<WalletCategory> accountTypes;
  final List<WalletCategory> accountCategories;
  final ReminderTransaction? existing;
  final List<String>? typeOrder;

  const _ReminderForm({
    required this.accounts,
    required this.categories,
    required this.accountTypes,
    required this.accountCategories,
    this.existing,
    this.typeOrder,
  });

  @override
  State<_ReminderForm> createState() => _ReminderFormState();
}

class _ReminderFormState extends State<_ReminderForm> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  late String _type; // 'income' or 'expense'
  String? _category;
  int? _accountId;
  late DateTime? _dueDate;
  late ReminderRepeat _repeat;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _amountCtrl = TextEditingController(
        text: e != null && e.amount > 0 ? e.amount.toStringAsFixed(2) : '');
    _noteCtrl = TextEditingController(text: e?.note ?? '');
    _type = e?.type ?? 'expense';
    _repeat = e?.repeat ?? ReminderRepeat.none;
    _dueDate = e != null ? DateTime.tryParse(e.dueDate) : null;

    if (e != null) {
      final inType =
          widget.categories.where((c) => c.subType == _type).toList();
      final names = inType.map((c) => c.name).toSet();
      _category = names.contains(e.category) ? e.category : null;
      _accountId = e.accountId;
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
    if (_category == null) return;
    if (_dueDate == null) return;

    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;

    Navigator.pop(
      context,
      ReminderTransaction(
        id: widget.existing?.id,
        title: _titleCtrl.text.trim(),
        amount: amount,
        dueDate: _dueDate!.toIso8601String(),
        type: _type,
        category: _category!,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        accountId: _accountId,
        repeat: _repeat,
        isDone: widget.existing?.isDone ?? false,
      ),
    );
  }

  Color get _accentColor =>
      _type == 'income' ? Colors.green : Colors.red.shade600;

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ── Date picker ────────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => _ReminderCalendarDatePickerDialog(
        initialDate: _dueDate ?? DateTime.now(),
        accentColor: _accentColor,
      ),
    );
    if (picked != null) {
      setState(() {
        _dueDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _dueDate?.hour ?? 0,
          _dueDate?.minute ?? 0,
        );
      });
    }
  }

  // ── Category picker ────────────────────────────────────────────────────────

  Future<void> _pickCategory() async {
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

  // ── Account picker ─────────────────────────────────────────────────────────

  Future<void> _pickAccount() async {
    final theme = Theme.of(context);
    if (widget.accounts.isEmpty) return;

    final typeIconMap = {for (final t in widget.accountTypes) t.name: t};
    final catIconMap = {for (final c in widget.accountCategories) c.name: c};

    final Map<String, List<Account>> grouped = {};
    for (final a in widget.accounts) {
      (grouped[a.type] ??= []).add(a);
    }

    final savedOrder = widget.typeOrder;
    final typeIndexMap = {
      for (int i = 0; i < widget.accountTypes.length; i++)
        widget.accountTypes[i].name: i,
    };
    final sortedGroupEntries = grouped.entries.toList()
      ..sort((a, b) {
        if (savedOrder != null) {
          final ai = savedOrder.indexOf(a.key);
          final bi = savedOrder.indexOf(b.key);
          final ai2 = ai < 0 ? 9999 : ai;
          final bi2 = bi < 0 ? 9999 : bi;
          if (ai2 != bi2) return ai2.compareTo(bi2);
        }
        final ai = typeIndexMap[a.key] ?? 9999;
        final bi = typeIndexMap[b.key] ?? 9999;
        return ai.compareTo(bi);
      });

    final picked = await showModalBottomSheet<int?>(
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
              Text('Account (optional)',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'Link a target account for this reminder.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              // "None" chip
              GestureDetector(
                onTap: () => Navigator.pop(ctx, -1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _accountId == null
                        ? theme.colorScheme.primary.withValues(alpha: 0.12)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _accountId == null
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.remove_circle_outline,
                          size: 18,
                          color: _accountId == null
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text('None',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _accountId == null
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          )),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...sortedGroupEntries.map((entry) {
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
                          Text(typeName,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              )),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: accs.map((a) {
                        final isSelected = a.id == _accountId;
                        final Color accColor =
                            _parseHex(a.colorHex) ?? theme.colorScheme.primary;
                        final catIcon = catIconMap[a.category]?.iconData ??
                            Icons.folder_outlined;
                        return GestureDetector(
                          onTap: () => Navigator.pop(ctx, a.id),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? accColor.withValues(alpha: 0.15)
                                  : theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color:
                                    isSelected ? accColor : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(catIcon,
                                    size: 16,
                                    color: isSelected
                                        ? accColor
                                        : theme.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 8),
                                Text(a.name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? accColor
                                          : theme.colorScheme.onSurface,
                                    )),
                                if (isSelected) ...[
                                  const SizedBox(width: 6),
                                  Icon(Icons.check_circle_rounded,
                                      size: 15, color: accColor),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );

    if (picked != null) {
      setState(() => _accountId = picked == -1 ? null : picked);
    }
  }

  // ── Repeat picker ──────────────────────────────────────────────────────────

  Future<void> _pickRepeat() async {
    final theme = Theme.of(context);
    final picked = await showModalBottomSheet<ReminderRepeat>(
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
              Text('Repeat',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...ReminderRepeat.values.map((r) {
                final isSelected = r == _repeat;
                return ListTile(
                  leading: Icon(r.icon,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant),
                  title: Text(r.label,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      )),
                  trailing: isSelected
                      ? Icon(Icons.check_circle_rounded,
                          color: theme.colorScheme.primary)
                      : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onTap: () => Navigator.pop(ctx, r),
                );
              }),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _repeat = picked);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isEditing = widget.existing != null;
    final accent = _accentColor;

    // Resolve category display name and icon
    final inType = widget.categories.where((c) => c.subType == _type).toList();
    final catObj = inType.cast<WalletCategory?>().firstWhere(
          (c) => c?.name == _category,
          orElse: () => null,
        );
    final categoryIcon = catObj?.iconData ?? Icons.label_outline;

    // Resolve account name
    final Account? account = _accountId != null
        ? widget.accounts.cast<Account?>().firstWhere(
              (a) => a?.id == _accountId,
              orElse: () => null,
            )
        : null;

    // Resolve account category icon (mirrors transaction form)
    final catIconMap = {for (final c in widget.accountCategories) c.name: c};
    final accountCatIcon = account != null
        ? (catIconMap[account.category]?.iconData ?? Icons.folder_outlined)
        : Icons.touch_app_outlined;
    final accountColor = account != null
        ? (_parseHex(account.colorHex) ?? cs.primary)
        : cs.onSurfaceVariant;

    final dateStr = _dueDate != null
        ? DateFormat('EEE, MMM d, yyyy').format(_dueDate!)
        : '';
    final isOverdue = _dueDate != null &&
        _dueDate!.isBefore(DateTime.now()) &&
        !_isSameDay(_dueDate!, DateTime.now());

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Handle ──────────────────────────────────────────────────
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Header ──────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.notifications_outlined,
                        color: Color(0xFFF59E0B), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEditing ? 'Edit Reminder' : 'New Reminder',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Type toggle ──────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: _TypeChip(
                      label: 'Expense',
                      icon: Icons.arrow_upward_rounded,
                      color: Colors.red.shade600,
                      selected: _type == 'expense',
                      onTap: () => setState(() {
                        _type = 'expense';
                        _category = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TypeChip(
                      label: 'Income',
                      icon: Icons.arrow_downward_rounded,
                      color: Colors.green.shade600,
                      selected: _type == 'income',
                      onTap: () => setState(() {
                        _type = 'income';
                        _category = null;
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Title ────────────────────────────────────────────────────
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

              // ── Amount (optional) ────────────────────────────────────────
              RepaintBoundary(
                child: TextField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount (${currencySymbolNotifier.value})',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(Icons.payments_outlined, color: accent),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Category & Due date — side-by-side ───────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category picker
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickCategory,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Category',
                          border: const OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: cs.outline),
                          ),
                          prefixIcon: Icon(
                            categoryIcon,
                            color: _category != null
                                ? accent
                                : cs.onSurfaceVariant,
                            size: 18,
                          ),
                          suffixIcon: Icon(Icons.expand_more_rounded,
                              size: 20, color: cs.onSurfaceVariant),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 16),
                        ),
                        isEmpty: _category == null,
                        child: _category != null
                            ? Text(
                                _capitalize(_category!),
                                style: theme.textTheme.bodyLarge
                                    ?.copyWith(color: cs.onSurface),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Due date picker
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Due date',
                          border: const OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                                color: isOverdue ? Colors.orange : cs.outline),
                          ),
                          prefixIcon: Icon(
                            isOverdue
                                ? Icons.warning_amber_rounded
                                : Icons.calendar_today_outlined,
                            color: isOverdue ? Colors.orange : accent,
                            size: 18,
                          ),
                          suffixIcon: Icon(Icons.expand_more_rounded,
                              size: 20, color: cs.onSurfaceVariant),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 16),
                        ),
                        isEmpty: _dueDate == null,
                        child: _dueDate != null
                            ? Text(
                                dateStr,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: isOverdue
                                      ? Colors.orange.shade700
                                      : cs.onSurface,
                                ),
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

              // ── Repeat & Account — side-by-side ──────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Repeat picker
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickRepeat,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Repeat',
                          border: const OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: cs.outline),
                          ),
                          prefixIcon: Icon(
                            _repeat.icon,
                            color: _repeat == ReminderRepeat.none
                                ? cs.onSurfaceVariant
                                : accent,
                            size: 18,
                          ),
                          suffixIcon: Icon(Icons.expand_more_rounded,
                              size: 20, color: cs.onSurfaceVariant),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 16),
                        ),
                        isEmpty: false,
                        child: Text(
                          _repeat.label,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: cs.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Account picker
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.accounts.isNotEmpty ? _pickAccount : null,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Account',
                          border: const OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: cs.outline),
                          ),
                          prefixIcon: Icon(
                            accountCatIcon,
                            color: accountColor,
                            size: 18,
                          ),
                          suffixIcon: Icon(Icons.expand_more_rounded,
                              size: 20, color: cs.onSurfaceVariant),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 16),
                        ),
                        isEmpty: account == null,
                        child: account != null
                            ? Text(
                                account.name,
                                style: theme.textTheme.bodyLarge
                                    ?.copyWith(color: cs.onSurface),
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

              // ── Note ─────────────────────────────────────────────────────
              TextField(
                controller: _noteCtrl,
                maxLines: 3,
                minLines: 3,
                textCapitalization: TextCapitalization.sentences,
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
              const SizedBox(height: 24),

              // ── Save button ──────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submit,
                  icon:
                      const Icon(Icons.notifications_active_rounded, size: 20),
                  label: Text(isEditing ? 'Save Changes' : 'Add Reminder'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Color? _parseHex(String hex) {
  try {
    final clean = hex.replaceAll('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  } catch (_) {
    return null;
  }
}

// ignore: unused_element
String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ── Calendar-style date picker for reminders (allows future dates) ────────────

class _ReminderCalendarDatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final Color accentColor;

  const _ReminderCalendarDatePickerDialog({
    required this.initialDate,
    required this.accentColor,
  });

  @override
  State<_ReminderCalendarDatePickerDialog> createState() =>
      _ReminderCalendarDatePickerDialogState();
}

class _ReminderCalendarDatePickerDialogState
    extends State<_ReminderCalendarDatePickerDialog> {
  late DateTime _selected;
  late DateTime _calendarMonth;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
    _calendarMonth = DateTime(_selected.year, _selected.month);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _calendarMonthLabel() =>
      DateFormat('MMMM yyyy').format(_calendarMonth);

  List<DateTime?> _calendarDays() {
    final firstDay = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final daysInMonth =
        DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    final leadingBlanks = firstDay.weekday - 1;
    return [
      ...List<DateTime?>.filled(leadingBlanks, null),
      ...List.generate(daysInMonth,
          (i) => DateTime(_calendarMonth.year, _calendarMonth.month, i + 1)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = widget.accentColor;
    final now = DateTime.now();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Month nav row ──────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() => _calendarMonth =
                      DateTime(_calendarMonth.year, _calendarMonth.month - 1)),
                ),
                Text(
                  _calendarMonthLabel(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() => _calendarMonth =
                      DateTime(_calendarMonth.year, _calendarMonth.month + 1)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Weekday header ─────────────────────────────────────────────
            Row(
              children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((d) {
                return Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 4),

            // ── Day grid ───────────────────────────────────────────────────
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
                        return const Expanded(child: SizedBox(height: 36));
                      }

                      final isSelected = _isSameDay(d, _selected);
                      final isToday = _isSameDay(d, now);

                      Color? bgColor;
                      Color textColor = theme.colorScheme.onSurface;

                      if (isSelected) {
                        bgColor = primary.withValues(alpha: 0.15);
                        textColor = primary;
                      } else if (isToday) {
                        textColor = primary;
                      }

                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selected = d),
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
                                  fontWeight: isSelected || isToday
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
            const SizedBox(height: 12),

            // ── Selected date label ───────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                DateFormat('EEE, MMM d, yyyy').format(_selected),
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
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primary,
                      side: BorderSide(color: primary.withValues(alpha: 0.5)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context, _selected),
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

// ── Type chip ─────────────────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.15)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: selected ? color : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? color : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Picker tile ───────────────────────────────────────────────────────────────

// ignore: unused_element
class _PickerTile extends StatelessWidget {
  final String label;
  final bool required;
  final String value;
  final IconData icon;
  final Color color;
  final bool hasValue;
  final VoidCallback onTap;
  final ThemeData theme;
  final Widget? trailing;

  const _PickerTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.hasValue,
    required this.onTap,
    required this.theme,
    // ignore: unused_element_parameter
    this.required = false,
    // ignore: unused_element_parameter
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(
            color: hasValue ? color.withValues(alpha: 0.5) : cs.outline,
            width: hasValue ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
          color: hasValue
              ? color.withValues(alpha: 0.04)
              : cs.surfaceContainerHighest.withValues(alpha: 0.4),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label + (required ? ' *' : ''),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: hasValue ? cs.onSurface : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
