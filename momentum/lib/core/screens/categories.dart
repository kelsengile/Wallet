import 'package:flutter/material.dart';

import '../../database/helper.dart';
import '../constants.dart';
import '../failures.dart';
import '../themes.dart';

/// Categories, split into sections: Finance | Schedule | Health.
/// Only Finance is built for now. It has two headers:
///  - Accounts: Types and Categories
///  - Transactions: Income, Expense and Transfer
/// Tap an item to rename or delete it. Use + to add one.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final Map<CategoryGroup, List<CategoryItem>> _items = {
    for (final g in CategoryGroup.values) g: const <CategoryItem>[],
  };
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    DatabaseHelper.instance.changes.addListener(_load);
  }

  @override
  void dispose() {
    DatabaseHelper.instance.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final groups = CategoryGroup.values;
      final results = await Future.wait(
        groups.map(DatabaseHelper.instance.getCategoryItems),
      );
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < groups.length; i++) {
          _items[groups[i]] = results[i];
        }
        _error = null;
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _error = f.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = const UnknownFailure().message);
    }
  }

  String _singular(CategoryGroup g) {
    switch (g) {
      case CategoryGroup.accountType:
        return 'type';
      case CategoryGroup.accountCategory:
        return 'category';
      case CategoryGroup.income:
        return 'income category';
      case CategoryGroup.expense:
        return 'expense category';
      case CategoryGroup.transfer:
        return 'transfer category';
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Asks the person to confirm before an item is removed.
  Future<bool> _confirmDelete(CategoryGroup group, CategoryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: Text('Delete ${_singular(group)}?'),
        content: Text('"${item.name}" will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _openEditor(CategoryGroup group, {CategoryItem? item}) async {
    final result = await showDialog<_NameResult>(
      context: context,
      builder: (_) => _NameDialog(
        title: item == null
            ? 'Add ${_singular(group)}'
            : 'Edit ${_singular(group)}',
        initial: item?.name ?? '',
        canDelete: item != null,
      ),
    );
    if (result == null || !mounted) return;

    final db = DatabaseHelper.instance;
    try {
      if (result.delete) {
        if (!await _confirmDelete(group, item!)) return;
        await db.deleteCategoryItem(group, item.id);
      } else if (item == null) {
        await db.addCategoryItem(group, result.name);
      } else if (result.name != item.name) {
        await db.renameCategoryItem(group, item.id, result.name);
      }
    } on Failure catch (f) {
      _snack(f.message);
    } catch (_) {
      _snack(const UnknownFailure().message);
    }
  }

  Widget _group(String title, CategoryGroup group, {bool editable = true}) {
    return _CategoryGroupCard(
      title: title,
      items: _items[group] ?? const [],
      editable: editable,
      onAdd: () => _openEditor(group),
      onTapItem: (item) => _openEditor(group, item: item),
    );
  }

  Widget _financeTab(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceLg),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(AppConstants.spaceMd),
            child: Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        const _SectionHeader('Accounts'),
        _group('Types', CategoryGroup.accountType),
        _group('Categories', CategoryGroup.accountCategory),
        const SizedBox(height: AppConstants.spaceSm),
        const _SectionHeader('Transactions'),
        _group('Income', CategoryGroup.income),
        _group('Expense', CategoryGroup.expense),
        _group('Transfer', CategoryGroup.transfer, editable: false),
      ],
    );
  }

  Widget _comingSoon(String name) =>
      Center(child: Text('$name categories coming soon'));

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.category_outlined),
              SizedBox(width: 8),
              Text('Categories'),
            ],
          ),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Finance'),
              Tab(text: 'Schedule'),
              Tab(text: 'Health'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _financeTab(context),
            _comingSoon('Schedule'),
            _comingSoon('Health'),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMd + AppConstants.spaceXs,
        AppConstants.spaceMd,
        AppConstants.spaceMd,
        AppConstants.spaceSm,
      ),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// A rounded card (accent color) with a title, a + button and its items.
class _CategoryGroupCard extends StatelessWidget {
  final String title;
  final List<CategoryItem> items;
  final bool editable;
  final VoidCallback onAdd;
  final ValueChanged<CategoryItem> onTapItem;

  const _CategoryGroupCard({
    required this.title,
    required this.items,
    required this.editable,
    required this.onAdd,
    required this.onTapItem,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final divider = Color.lerp(accent.background, fg, 0.18)!;

    Widget dividerLine() => Divider(
          height: 1,
          thickness: 1,
          indent: AppConstants.spaceMd,
          endIndent: AppConstants.spaceMd,
          color: divider,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMd,
        vertical: AppConstants.spaceXs,
      ),
      child: Material(
        color: accent.background,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spaceMd,
                AppConstants.spaceXs,
                AppConstants.spaceXs,
                AppConstants.spaceXs,
              ),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                    ),
                    if (editable)
                      IconButton(
                        icon: Icon(Icons.add, color: fg),
                        tooltip: 'Add',
                        onPressed: onAdd,
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.all(AppConstants.spaceSm),
                        child: Icon(
                          Icons.lock_outline,
                          size: 18,
                          color: fg.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (items.isEmpty && editable) ...[
              dividerLine(),
              ListTile(
                dense: true,
                title: Text(
                  'Nothing yet. Tap + to add.',
                  style: TextStyle(color: fg.withValues(alpha: 0.7)),
                ),
              ),
            ],
            for (final item in items) ...[
              dividerLine(),
              ListTile(
                dense: true,
                title: Text(item.name, style: TextStyle(color: fg)),
                trailing: editable
                    ? Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: fg.withValues(alpha: 0.7),
                      )
                    : null,
                onTap: editable ? () => onTapItem(item) : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NameResult {
  final String name;
  final bool delete;
  const _NameResult(this.name, {this.delete = false});
}

/// Small pop-up to add, rename or delete one item.
class _NameDialog extends StatefulWidget {
  final String title;
  final String initial;
  final bool canDelete;

  const _NameDialog({
    required this.title,
    required this.initial,
    required this.canDelete,
  });

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Enter a name');
      return;
    }
    Navigator.of(context).pop(_NameResult(name));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(hintText: 'Name', errorText: _errorText),
        onChanged: (_) {
          if (_errorText != null) setState(() => _errorText = null);
        },
        onSubmitted: (_) => _save(),
      ),
      actions: [
        if (widget.canDelete)
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              const _NameResult('', delete: true),
            ),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}