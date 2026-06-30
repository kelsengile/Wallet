import 'package:flutter/material.dart';
import '../currency.dart';
import 'category_model.dart';

/// A monthly spending limit set against a single expense category.
///
/// Budgets are recurring by design — the same [monthlyLimit] applies every
/// calendar month. "Spent so far" is computed by the caller (BudgetPage)
/// from that month's transactions; it isn't stored here.
class Budget {
  final int? id;
  final String category;
  final double monthlyLimit;

  Budget({
    this.id,
    required this.category,
    required this.monthlyLimit,
  });

  Budget copyWith({
    int? id,
    String? category,
    double? monthlyLimit,
  }) {
    return Budget(
      id: id ?? this.id,
      category: category ?? this.category,
      monthlyLimit: monthlyLimit ?? this.monthlyLimit,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'category': category,
      'monthly_limit': monthlyLimit,
    };
  }

  factory Budget.fromMap(Map<String, dynamic> map) {
    return Budget(
      id: map['id'] as int?,
      category: map['category'] as String,
      monthlyLimit: (map['monthly_limit'] as num).toDouble(),
    );
  }

  // ── Dialog factory — mirrors the Account/Transaction bottom-sheet pattern ──

  /// Shows an add/edit budget modal bottom sheet.
  ///
  /// [categories] should be the user's selectable expense categories.
  /// [takenCategories] are categories that already have a budget — they're
  /// disabled in the picker unless they match [existing]'s category (so
  /// editing a budget doesn't lock you out of your own category).
  static Future<Budget?> showDialog(
    BuildContext context, {
    required List<WalletCategory> categories,
    required Set<String> takenCategories,
    Budget? existing,
  }) {
    return showModalBottomSheet<Budget>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _BudgetForm(
        categories: categories,
        takenCategories: takenCategories,
        existing: existing,
      ),
    );
  }
}

// ── Bottom-sheet form ────────────────────────────────────────────────────────

class _BudgetForm extends StatefulWidget {
  final List<WalletCategory> categories;
  final Set<String> takenCategories;
  final Budget? existing;

  const _BudgetForm({
    required this.categories,
    required this.takenCategories,
    this.existing,
  });

  @override
  State<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends State<_BudgetForm> {
  late final TextEditingController _limitCtrl;
  String? _category;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _limitCtrl = TextEditingController(
      text: e != null ? _trimZeros(e.monthlyLimit) : '',
    );
    _category = e?.category;
  }

  String _trimZeros(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  @override
  void dispose() {
    _limitCtrl.dispose();
    super.dispose();
  }

  Color? _parseHex(String hex) {
    try {
      final cleaned = hex.replaceFirst('#', '');
      return Color(int.parse('FF$cleaned', radix: 16));
    } catch (_) {
      return null;
    }
  }

  void _submit() {
    if (_category == null) {
      setState(() => _error = 'Pick a category');
      return;
    }
    final amount = double.tryParse(_limitCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid monthly limit');
      return;
    }
    Navigator.pop(
      context,
      Budget(
        id: widget.existing?.id,
        category: _category!,
        monthlyLimit: amount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;
    final catObj = widget.categories.cast<WalletCategory?>().firstWhere(
          (c) => c?.name == _category,
          orElse: () => null,
        );
    final accent = catObj != null
        ? (_parseHex(catObj.colorHex) ?? theme.colorScheme.primary)
        : theme.colorScheme.primary;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isEditing ? 'Edit Budget' : 'New Budget',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),

              // ── Category picker ─────────────────────────────────────────
              Text(
                'Category',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.categories.map((c) {
                  final selected = c.name == _category;
                  final taken = widget.takenCategories.contains(c.name) &&
                      c.name != widget.existing?.category;
                  final color =
                      _parseHex(c.colorHex) ?? theme.colorScheme.primary;
                  return Opacity(
                    opacity: taken ? 0.35 : 1,
                    child: ChoiceChip(
                      avatar: Icon(c.iconData, size: 16, color: color),
                      label: Text(c.name),
                      selected: selected,
                      onSelected: taken
                          ? null
                          : (_) => setState(() {
                                _category = c.name;
                                _error = null;
                              }),
                      selectedColor: color.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        color: selected ? color : theme.colorScheme.onSurface,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      side: BorderSide(
                        color:
                            selected ? color : theme.colorScheme.outlineVariant,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // ── Monthly limit field ─────────────────────────────────────
              TextField(
                controller: _limitCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Monthly Limit (${currencySymbolNotifier.value})',
                  prefixIcon: const Icon(Icons.savings_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style:
                      TextStyle(color: theme.colorScheme.error, fontSize: 12),
                ),
              ],

              const SizedBox(height: 24),
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
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _submit,
                      child: Text(isEditing ? 'Save' : 'Add Budget'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
