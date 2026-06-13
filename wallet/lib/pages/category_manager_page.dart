import 'package:flutter/material.dart';
import '../models/category_model.dart';
import '../database/database_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CategoryManagerPage
//
// Two tabs:
//   • Account       → combines Account Types + Account Categories
//                      (kCategoryGroupAccountType / kCategoryGroupAccountCategory),
//                      each shown as its own section with a header.
//   • Transactions   (kCategoryGroupTransactionCategory) → split into Income
//                      and Expense sections, each with a header, followed by
//                      the system "Transfer" category (locked, shown last).
//
// Rules enforced here (mirroring the DB layer):
//   • System categories (Transfer) → shown with a lock badge; no edit/delete.
//   • Default category → shown with a star badge; cannot be deleted.
//     A different category in the same group must be starred first.
//   • Deleting a category reassigns all existing accounts/transactions that
//     used it to the group's current default (DB handles the UPDATE).
//     A snackbar confirms the fallback name.
//   • Reordering persists via [DatabaseHelper.reorderCategories].
//   • Each section has its own "Add" button placed below its list.
// ─────────────────────────────────────────────────────────────────────────────

enum _CategoryTabMode { accounts, transactions }

class CategoryManagerPage extends StatefulWidget {
  const CategoryManagerPage({super.key});

  @override
  State<CategoryManagerPage> createState() => _CategoryManagerPageState();
}

class _CategoryManagerPageState extends State<CategoryManagerPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  static const _tabs = [
    (label: 'Account', mode: _CategoryTabMode.accounts),
    (label: 'Transactions', mode: _CategoryTabMode.transactions),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Category Manager'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: _tabs
            .map((t) => _CategoryTab(
                  key: ValueKey(t.mode),
                  mode: t.mode,
                ))
            .toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CategoryTab — one tab; either the combined Account tab or the
// Transactions tab (split into Income / Expense sections).
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryTab extends StatefulWidget {
  final _CategoryTabMode mode;

  const _CategoryTab({super.key, required this.mode});

  @override
  State<_CategoryTab> createState() => _CategoryTabState();
}

class _CategoryTabState extends State<_CategoryTab>
    with AutomaticKeepAliveClientMixin {
  /// Accounts mode: account *types*. Transactions mode: all transaction
  /// categories (split into sections by sub-type for display).
  List<WalletCategory> _primary = [];

  /// Accounts mode only: account *categories*.
  List<WalletCategory> _secondary = [];

  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── data ───────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    if (widget.mode == _CategoryTabMode.accounts) {
      final types = await DatabaseHelper.instance
          .getCategories(kCategoryGroupAccountType);
      final cats = await DatabaseHelper.instance
          .getCategories(kCategoryGroupAccountCategory);
      if (!mounted) return;
      setState(() {
        _primary = types;
        _secondary = cats;
        _loading = false;
      });
    } else {
      final items = await DatabaseHelper.instance
          .getCategories(kCategoryGroupTransactionCategory);
      if (!mounted) return;
      setState(() {
        _primary = items;
        _loading = false;
      });
    }
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// All currently-loaded categories belonging to [groupType] — used to find
  /// the fallback default when deleting.
  List<WalletCategory> _listFor(String groupType) {
    if (widget.mode == _CategoryTabMode.accounts) {
      return groupType == kCategoryGroupAccountType ? _primary : _secondary;
    }
    return _primary;
  }

  // ── reorder ────────────────────────────────────────────────────────────────

  /// Reorders a flat section (used for the two Account sections, each of
  /// which maps 1:1 to a category group).
  Future<void> _reorderFlat(
    List<WalletCategory> list,
    String groupType,
    int oldIndex,
    int newIndex,
    void Function(List<WalletCategory>) commit,
  ) async {
    if (newIndex > oldIndex) newIndex--;
    final updated = List<WalletCategory>.from(list);
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    commit(updated);

    final ids = updated.where((c) => c.id != null).map((c) => c.id!).toList();
    await DatabaseHelper.instance.reorderCategories(groupType, ids);
  }

  /// Reorders one sub-type slice (Income or Expense) of the transaction
  /// categories, then persists the combined order for the whole group.
  Future<void> _reorderTransactionSubType(
    String subType,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex--;

    final slice = _primary.where((c) => c.subType == subType).toList();
    final moved = slice.removeAt(oldIndex);
    slice.insert(newIndex, moved);

    final income = subType == kSubTypeIncome
        ? slice
        : _primary.where((c) => c.subType == kSubTypeIncome).toList();
    final expense = subType == kSubTypeExpense
        ? slice
        : _primary.where((c) => c.subType == kSubTypeExpense).toList();
    final other = _primary
        .where(
            (c) => c.subType != kSubTypeIncome && c.subType != kSubTypeExpense)
        .toList();

    final updated = [...income, ...expense, ...other];
    setState(() => _primary = updated);

    final ids = updated.where((c) => c.id != null).map((c) => c.id!).toList();
    await DatabaseHelper.instance
        .reorderCategories(kCategoryGroupTransactionCategory, ids);
  }

  // ── set default ────────────────────────────────────────────────────────────

  Future<void> _setDefault(WalletCategory cat) async {
    if (cat.id == null || cat.isDefault) return;
    await DatabaseHelper.instance.setDefaultCategory(cat.groupType, cat.id!);
    await _load();
    _showSnack('"${cat.name}" is now the default.');
  }

  // ── add ────────────────────────────────────────────────────────────────────

  Future<void> _showAddDialog(String groupType, {String subType = ''}) async {
    final result = await showDialog<WalletCategory>(
      context: context,
      builder: (ctx) => _CategoryFormDialog(
        groupType: groupType,
        showColorPicker: groupType == kCategoryGroupAccountType,
        existing: null,
        subType: subType,
      ),
    );
    if (result == null) return;
    try {
      await DatabaseHelper.instance.addCategory(result);
      await _load();
    } catch (_) {
      _showSnack('A category with that name already exists.');
    }
  }

  // ── edit ───────────────────────────────────────────────────────────────────

  Future<void> _showEditDialog(WalletCategory cat) async {
    if (cat.isSystem) return;
    final result = await showDialog<WalletCategory>(
      context: context,
      builder: (ctx) => _CategoryFormDialog(
        groupType: cat.groupType,
        showColorPicker: cat.groupType == kCategoryGroupAccountType,
        existing: cat,
      ),
    );
    if (result == null) return;
    try {
      await DatabaseHelper.instance.updateCategory(cat, result);
      await _load();
    } catch (_) {
      _showSnack('A category with that name already exists.');
    }
  }

  // ── delete ─────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete(WalletCategory cat) async {
    if (cat.isSystem) return;
    if (cat.isDefault) {
      _showSnack(
          'Cannot delete the default category. Set another as default first.');
      return;
    }
    final fallback =
        firstWhereOrNull(_listFor(cat.groupType), (c) => c.isDefault)?.name ??
            '(default)';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to Trash'),
        content: Text(
          'Move "${cat.name}" to trash?\n\n'
          'All accounts / transactions using this will be reassigned '
          'to "$fallback". You can restore this category from the trash '
          'bin later.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Move to Trash'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final reassignedTo = await DatabaseHelper.instance.deleteCategory(cat);
    if (reassignedTo != null) {
      await _load();
      _showSnack(
          '"${cat.name}" moved to trash. Items reassigned to "$reassignedTo".');
    } else {
      _showSnack('Could not delete — make sure a default category is set.');
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final sections = widget.mode == _CategoryTabMode.accounts
        ? _buildAccountSections()
        : _buildTransactionSections();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: sections,
    );
  }

  List<Widget> _buildAccountSections() {
    return [
      _CategorySection(
        title: 'Types',
        items: _primary,
        showColor: true,
        emptyLabel: 'No account types yet. Tap "Add" to create one.',
        onReorder: (o, n) => _reorderFlat(
          _primary,
          kCategoryGroupAccountType,
          o,
          n,
          (u) => setState(() => _primary = u),
        ),
        onEdit: _showEditDialog,
        onDelete: _confirmDelete,
        onSetDefault: _setDefault,
        addLabel: 'Add Type',
        onAdd: () => _showAddDialog(kCategoryGroupAccountType),
      ),
      const SizedBox(height: 24),
      _CategorySection(
        title: 'Categories',
        items: _secondary,
        showColor: false,
        emptyLabel: 'No account categories yet. Tap "Add" to create one.',
        onReorder: (o, n) => _reorderFlat(
          _secondary,
          kCategoryGroupAccountCategory,
          o,
          n,
          (u) => setState(() => _secondary = u),
        ),
        onEdit: _showEditDialog,
        onDelete: _confirmDelete,
        onSetDefault: _setDefault,
        addLabel: 'Add Category',
        onAdd: () => _showAddDialog(kCategoryGroupAccountCategory),
      ),
    ];
  }

  List<Widget> _buildTransactionSections() {
    final income = _primary.where((c) => c.subType == kSubTypeIncome).toList();
    final expense =
        _primary.where((c) => c.subType == kSubTypeExpense).toList();
    final transfer = _primary.where((c) => c.isSystem).toList();

    return [
      _CategorySection(
        title: 'Income',
        items: income,
        showColor: false,
        emptyLabel: 'No income categories yet. Tap "Add" to create one.',
        onReorder: (o, n) => _reorderTransactionSubType(kSubTypeIncome, o, n),
        onEdit: _showEditDialog,
        onDelete: _confirmDelete,
        onSetDefault: _setDefault,
        addLabel: 'Add Income Category',
        onAdd: () => _showAddDialog(
          kCategoryGroupTransactionCategory,
          subType: kSubTypeIncome,
        ),
      ),
      const SizedBox(height: 24),
      _CategorySection(
        title: 'Expense',
        items: expense,
        showColor: false,
        emptyLabel: 'No expense categories yet. Tap "Add" to create one.',
        onReorder: (o, n) => _reorderTransactionSubType(kSubTypeExpense, o, n),
        onEdit: _showEditDialog,
        onDelete: _confirmDelete,
        onSetDefault: _setDefault,
        addLabel: 'Add Expense Category',
        onAdd: () => _showAddDialog(
          kCategoryGroupTransactionCategory,
          subType: kSubTypeExpense,
        ),
      ),
      const SizedBox(height: 24),
      // Locked system "Transfer" category — used internally for the two
      // legs of a transfer and not editable/deletable/reorderable.
      _CategorySection(
        title: 'Transfer',
        items: transfer,
        showColor: false,
        emptyLabel: '',
        onReorder: (_, __) {},
        onEdit: (_) {},
        onDelete: (_) {},
        onSetDefault: (_) {},
      ),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CategorySection — header + reorderable list + "Add" button below it.
// ─────────────────────────────────────────────────────────────────────────────

class _CategorySection extends StatelessWidget {
  final String title;
  final List<WalletCategory> items;
  final bool showColor;
  final String emptyLabel;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(WalletCategory) onEdit;
  final void Function(WalletCategory) onDelete;
  final void Function(WalletCategory) onSetDefault;
  final String? addLabel;
  final VoidCallback? onAdd;

  const _CategorySection({
    required this.title,
    required this.items,
    required this.showColor,
    required this.emptyLabel,
    required this.onReorder,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
    this.addLabel,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── section header ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ),

        // ── list ─────────────────────────────────────────────────────────
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              emptyLabel,
              style: TextStyle(color: theme.colorScheme.outline),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: items.length,
            onReorder: onReorder,
            proxyDecorator: (child, _, __) => Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: child,
            ),
            itemBuilder: (_, i) {
              final cat = items[i];
              return _CategoryTile(
                key: ValueKey('cat_${cat.id}_${cat.name}'),
                category: cat,
                showColor: showColor,
                onEdit: cat.isSystem ? null : () => onEdit(cat),
                onDelete: (cat.isSystem || cat.isDefault)
                    ? null
                    : () => onDelete(cat),
                onSetDefault: (cat.isDefault || cat.isSystem)
                    ? null
                    : () => onSetDefault(cat),
                onDismiss: (cat.isSystem || cat.isDefault)
                    ? null
                    : () => onDelete(cat),
              );
            },
          ),

        // ── add button ──────────────────────────────────────────────────
        if (onAdd != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(addLabel ?? 'Add'),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CategoryTile
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryTile extends StatelessWidget {
  final WalletCategory category;
  final bool showColor;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onSetDefault;
  final VoidCallback? onDismiss;

  const _CategoryTile({
    super.key,
    required this.category,
    required this.showColor,
    this.onEdit,
    this.onDelete,
    this.onSetDefault,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent =
        showColor ? colorFromHex(category.colorHex) : theme.colorScheme.primary;

    Widget card = Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.15),
          child: Icon(category.iconData, size: 20, color: accent),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                capitalizeWords(category.name),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (category.isDefault) ...[
              const SizedBox(width: 6),
              _Badge(
                  label: 'Default',
                  color: theme.colorScheme.primary,
                  icon: Icons.star),
            ],
            if (category.isSystem) ...[
              const SizedBox(width: 6),
              _Badge(
                  label: 'System',
                  color: theme.colorScheme.outline,
                  icon: Icons.lock_outline),
            ],
          ],
        ),
        subtitle: showColor
            ? Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 4),
                    decoration:
                        BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                  Text(
                    category.colorHex.toUpperCase(),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onSetDefault != null)
              IconButton(
                icon: const Icon(Icons.star_border_outlined, size: 20),
                tooltip: 'Set as default',
                onPressed: onSetDefault,
              ),
            if (onEdit != null)
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Edit',
                onPressed: onEdit,
              ),
            if (onDelete != null)
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 20, color: theme.colorScheme.error),
                tooltip: 'Delete',
                onPressed: onDelete,
              ),
            const Padding(
              padding: EdgeInsets.only(left: 2),
              child: Icon(Icons.drag_handle_outlined,
                  color: Colors.grey, size: 20),
            ),
          ],
        ),
      ),
    );

    if (onDismiss != null) {
      card = Dismissible(
        key: ValueKey('dismiss_${category.id}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          onDismiss!();
          return false;
        },
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        child: card,
      );
    }

    return card;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Badge
// ─────────────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _Badge({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CategoryFormDialog — Add / Edit dialog
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryFormDialog extends StatefulWidget {
  final String groupType;
  final bool showColorPicker;
  final WalletCategory? existing;

  /// Sub-type to assign to a *new* transaction category (income/expense).
  /// Ignored when [existing] is non-null (the existing sub-type is kept).
  final String subType;

  const _CategoryFormDialog({
    required this.groupType,
    required this.showColorPicker,
    this.existing,
    this.subType = '',
  });

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  late final TextEditingController _nameCtrl;
  late String _selectedIcon;
  late String _selectedColor;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _selectedIcon = e?.icon ?? 'label';
    _selectedColor = e?.colorHex ?? kCategoryColorPalette.first;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final base = widget.existing ??
        WalletCategory(
          name: name,
          groupType: widget.groupType,
          icon: _selectedIcon,
          colorHex: _selectedColor,
          subType: widget.subType,
        );

    Navigator.pop(
      context,
      base.copyWith(
        name: name,
        icon: _selectedIcon,
        colorHex: _selectedColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Category' : 'New Category'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Name ──────────────────────────────────────────────────────
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),

            // ── Icon picker ───────────────────────────────────────────────
            Text('Icon', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            _IconPicker(
              selected: _selectedIcon,
              onChanged: (k) => setState(() => _selectedIcon = k),
            ),

            // ── Color picker (Account Types only) ─────────────────────────
            if (widget.showColorPicker) ...[
              const SizedBox(height: 16),
              Text('Color', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              _ColorPicker(
                selected: _selectedColor,
                onChanged: (h) => setState(() => _selectedColor = h),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _submit,
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _IconPicker
// ─────────────────────────────────────────────────────────────────────────────

class _IconPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _IconPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kCategoryIcons.entries.map((e) {
        final isSelected = e.key == selected;
        return GestureDetector(
          onTap: () => onChanged(e.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color:
                    isSelected ? theme.colorScheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Icon(
              e.value,
              size: 20,
              color: isSelected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ColorPicker
// ─────────────────────────────────────────────────────────────────────────────

class _ColorPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _ColorPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: kCategoryColorPalette.map((hex) {
        final isSelected = hex == selected;
        final color = colorFromHex(hex);
        return GestureDetector(
          onTap: () => onChanged(hex),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 3,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                          color: color.withValues(alpha: 0.6), blurRadius: 6)
                    ]
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : null,
          ),
        );
      }).toList(),
    );
  }
}
