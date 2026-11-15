import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../database/helper.dart';
import '../constants.dart';
import '../failures.dart';
import '../themes.dart';
import 'settings.dart'; // ColorPickerDialog

/// The icons a category can use, and the default icon of each seed item.
/// The key is what gets saved in the database.
class _CategoryIcons {
  _CategoryIcons._();

  /// Shown in this order in the picker (8 per row).
  static const Map<String, IconData> all = {
    'wallet': Icons.account_balance_wallet_outlined,
    'cash': Icons.payments_outlined,
    'bank': Icons.account_balance,
    'phone': Icons.smartphone,
    'card': Icons.credit_card,
    'handshake': Icons.handshake_outlined,
    'trending': Icons.trending_up,
    'savings': Icons.savings_outlined,
    'food': Icons.restaurant,
    'car': Icons.directions_car,
    'shopping': Icons.shopping_bag,
    'receipt': Icons.receipt_long,
    'heart': Icons.favorite,
    'movie': Icons.movie,
    'work': Icons.work,
    'swap': Icons.swap_horiz,
    'home': Icons.home,
    'gift': Icons.card_giftcard,
    'pets': Icons.pets,
    'school': Icons.school,
    'fitness': Icons.fitness_center,
    'flight': Icons.flight,
    'family': Icons.family_restroom,
    'business': Icons.business_center,
    'flag': Icons.flag,
    'medical': Icons.medical_services,
    'star': Icons.star,
    'shapes': Icons.category,
    'label': Icons.label_outline,
  };

  static const String fallback = 'label';

  /// Used for new items and for anything not listed below.
  static const Map<CategoryGroup, String> _groupDefault = {
    CategoryGroup.accountType: 'wallet',
    CategoryGroup.accountCategory: 'label',
    CategoryGroup.income: 'cash',
    CategoryGroup.expense: 'shopping',
    CategoryGroup.transfer: 'swap',
  };

  /// Default icon of each seed item, by name.
  static const Map<CategoryGroup, Map<String, String>> _nameDefaults = {
    CategoryGroup.accountType: {
      'Cash': 'cash',
      'Bank': 'bank',
      'Digital Bank': 'phone',
      'Credit': 'card',
      'E-Wallet': 'wallet',
      'Investment': 'trending',
      'Assets': 'home',
      'Debt': 'handshake',
      'Business': 'business',
    },
    CategoryGroup.accountCategory: {
      'Personal': 'star',
      'Family': 'family',
      'Savings': 'savings',
      'Future': 'flag',
      'Work': 'work',
      'Travel': 'flight',
      'Health': 'medical',
      'Investment': 'trending',
      'Debt': 'card',
      'Emergency': 'heart',
      'Spending': 'shopping',
    },
    CategoryGroup.income: {
      'Salary': 'cash',
      'Bonus': 'gift',
      'Commission': 'handshake',
      'Allowance': 'wallet',
      'Freelance': 'work',
      'Business': 'business',
      'Investment': 'trending',
      'Gift': 'gift',
      'Scholarship': 'school',
      'Refund': 'receipt',
      'Loan': 'bank',
      'Miscellaneous': 'shapes',
    },
    CategoryGroup.expense: {
      'Food': 'food',
      'Transportation': 'car',
      'Shopping': 'shopping',
      'Bills': 'receipt',
      'Health': 'medical',
      'Education': 'school',
      'Entertainment': 'movie',
      'Tax': 'bank',
      'Debt': 'card',
      'Gift': 'gift',
      'Travel': 'flight',
      'Sports': 'fitness',
      'Miscellaneous': 'shapes',
    },
    CategoryGroup.transfer: {'Transfer': 'swap'},
  };

  static String defaultKey(CategoryGroup group, String name) =>
      _nameDefaults[group]?[name] ?? _groupDefault[group] ?? fallback;

  static bool isImage(String key) =>
      key.startsWith(AppConstants.iconImagePrefix);

  static String? imagePath(String key) {
    if (!isImage(key)) return null;
    final path = key.substring(AppConstants.iconImagePrefix.length);
    return path.isEmpty ? null : path;
  }

  /// The saved icon key, or the default one when nothing is saved.
  static String keyOf(CategoryGroup group, CategoryItem item) {
    final saved = item.icon;
    if (saved != null && (all.containsKey(saved) || isImage(saved))) {
      return saved;
    }
    return defaultKey(group, item.name);
  }

  static IconData of(String key) => all[key] ?? all[fallback]!;

  /// The icon as a widget: a picture for imported icons, else the glyph.
  static Widget view(String key, {required double size, required Color color}) {
    final path = imagePath(key);
    if (path != null) {
      return Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            Icon(all[fallback], size: size * 0.5, color: color),
      );
    }
    return Icon(of(key), size: size, color: color);
  }
}

/// Copies a picked picture into the app's own icon folder.
Future<String> _storeIconImage(String source) async {
  final dir = await getApplicationDocumentsDirectory();
  final folder = Directory(p.join(dir.path, AppConstants.iconImageFolder));
  if (!await folder.exists()) await folder.create(recursive: true);
  final target = p.join(
    folder.path,
    '${DateTime.now().microsecondsSinceEpoch}${p.extension(source)}',
  );
  await File(source).copy(target);
  return target;
}

Future<void> _deleteIconFile(String? key) async {
  final path = key == null ? null : _CategoryIcons.imagePath(key);
  if (path == null) return;
  try {
    await File(path).delete();
  } catch (_) {}
}

/// Colors a pop-up: [background] behind, [foreground] for text, buttons and
/// fields. Both default to the theme's accent colors.
ThemeData _popupTheme(
  BuildContext context, {
  Color? background,
  Color? foreground,
}) {
  final theme = Theme.of(context);
  final accent = AppTheme.accentOf(context);
  final bg = background ?? accent.background;
  final fg = foreground ?? accent.foreground;
  return theme.copyWith(
    colorScheme: theme.colorScheme.copyWith(
      primary: fg,
      onPrimary: bg,
      onSurface: fg,
      onSurfaceVariant: fg.withValues(alpha: AppConstants.mutedAlpha),
    ),
  );
}

/// The one pop-up design used by the edit and the delete pop-ups:
/// same corners, same spacing, same buttons.
/// [background] / [foreground] default to the accent colors.
/// [compact] makes it shorter (used by the delete pop-up).
Widget _accentDialog(
  BuildContext context, {
  required String title,
  required Widget content,
  required List<Widget> actions,
  Color? background,
  Color? foreground,
  bool compact = false,
}) {
  final accent = AppTheme.accentOf(context);
  final bg = background ?? accent.background;
  final fg = foreground ?? accent.foreground;
  final theme = _popupTheme(context, background: bg, foreground: fg);

  return Theme(
    data: theme,
    child: AlertDialog(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.popupRadius),
      ),
      insetPadding: AppConstants.popupInsetPadding,
      titlePadding: compact
          ? AppConstants.popupTitlePaddingCompact
          : AppConstants.popupTitlePadding,
      contentPadding: compact
          ? AppConstants.popupContentPaddingCompact
          : AppConstants.popupContentPadding,
      actionsPadding: compact
          ? AppConstants.popupActionsPaddingCompact
          : AppConstants.popupActionsPadding,
      titleTextStyle: compact
          ? theme.textTheme.titleLarge?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            )
          : null,
      title: Text(title),
      content: SizedBox(width: double.maxFinite, child: content),
      actions: actions,
    ),
  );
}

/// Red delete confirm pop-up. Same size and shape as the date pop-up.
/// Red top with a trash icon, accent-colored body, a chip with the item's
/// icon and name, a message, then Cancel (outlined) and Delete (red).
/// Returns true only when Delete is tapped.
Future<bool> _confirmDeleteDialog(
  BuildContext context, {
  required String title,
  required String name,
  required Widget icon,
  required String message,
}) async {
  final accent = AppTheme.accentOf(context);
  final fg = accent.foreground;
  final bg = accent.background;
  final red = AppSettings.instance.deleteColor;

  final ok = await showDialog<bool>(
    context: context,
    barrierColor: AppConstants.popupBarrier,
    builder: (ctx) => Dialog(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ----- Red top -----
            Container(
              color: red,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
              child: Column(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                    child: const Icon(
                      Icons.delete_forever,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceMd),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            // ----- Body -----
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: red.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: icon,
                        ),
                        const SizedBox(width: AppConstants.spaceSm),
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceMd),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: fg.withValues(alpha: AppConstants.mutedAlpha),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceLg),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: const StadiumBorder(),
                            foregroundColor: fg,
                            side: BorderSide(color: fg.withValues(alpha: 0.5)),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: const StadiumBorder(),
                            backgroundColor: red,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => Navigator.of(ctx).pop(true),
                          icon: const Icon(Icons.delete, size: 20),
                          label: const Text(
                            'Delete',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}

/// Categories, split into sections: Finance | Schedule | Health.
/// Only Finance is built for now. It has two headers:
///  - Accounts: Types and Categories
///  - Transactions: Income, Expense and Transfer
/// Tap the pen (or the bar) to rename it or change its icon and color.
/// Swipe a bar left to delete it. Drag the 3-line handle to change the
/// order. Use + to add one.
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

  // ---------- Saved order ----------

  Future<void> _load() async {
    try {
      final groups = CategoryGroup.values;
      // getCategoryItems already returns each list in its saved order.
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

  /// Moves one bar to a new place and saves the new order.
  Future<void> _reorder(CategoryGroup group, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    final list = [...(_items[group] ?? const <CategoryItem>[])];
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    setState(() => _items[group] = list);
    try {
      await DatabaseHelper.instance.saveCategoryOrder(
        group,
        [for (final item in list) item.id],
      );
    } catch (_) {
      _snack('Couldn\'t save the new order.');
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
  Future<bool> _confirmDelete(CategoryGroup group, CategoryItem item) {
    final kind = _singular(group)
        .split(' ')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
    return _confirmDeleteDialog(
      context,
      title: 'Delete $kind',
      name: item.name,
            icon: _CategoryIcons.view(
        _CategoryIcons.keyOf(group, item),
        size: 20,
        color: AppSettings.instance.deleteColor,
      ),
      message: 'This ${_singular(group)} will be removed. '
          'This action cannot be undone.',
    );
  }

  /// Called when a bar is swiped. Confirms, deletes the category and returns
  /// true only when it was really deleted (so the bar slides away).
  Future<bool> _deleteItem(CategoryGroup group, CategoryItem item) async {
    if (!await _confirmDelete(group, item)) return false;
    try {
      await DatabaseHelper.instance.deleteCategoryItem(group, item.id);
      return true;
    } on Failure catch (f) {
      _snack(f.message);
    } catch (_) {
      _snack(const UnknownFailure().message);
    }
    return false;
  }

  Future<void> _openEditor(CategoryGroup group, {CategoryItem? item}) async {
    final startIcon = item == null
        ? _CategoryIcons.defaultKey(group, '')
        : _CategoryIcons.keyOf(group, item);
        final showColor =
        group == CategoryGroup.income || group == CategoryGroup.expense;
    final startColor = showColor ? item?.color : null;
    final kindTitle = _singular(group)
        .split(' ')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
    final result = await showDialog<_NameResult>(
      context: context,
      barrierColor: AppConstants.popupBarrier,
      builder: (_) => _NameDialog(
        title: item == null
            ? 'Add ${_singular(group)}'
            : 'Edit ${_singular(group)}',
        initial: item?.name ?? '',
        initialIcon: startIcon,
        showColor: showColor,
        initialColor: startColor,
        colorTitle: '$kindTitle Color', // <- header text of the color picker
      ),
    );
    if (result == null || !mounted) return;

    final db = DatabaseHelper.instance;
    try {
      if (item == null) {
        await db.addCategoryItem(
          group,
          result.name,
          icon: result.icon,
          color: result.color,
        );
      } else if (result.name != item.name ||
          result.icon != startIcon ||
          result.color != startColor) {
        await db.renameCategoryItem(
          group,
          item.id,
          result.name,
          icon: result.icon,
          color: result.color,
        );
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
      useColor:
          group == CategoryGroup.income || group == CategoryGroup.expense,
      iconKeyFor: (item) => _CategoryIcons.keyOf(group, item),
        iconFor: (item) =>
          _CategoryIcons.of(_CategoryIcons.keyOf(group, item)),
      onAdd: () => _openEditor(group),
      onTapItem: (item) => _openEditor(group, item: item),
      onDeleteItem: (item) => _deleteItem(group, item),
      onDeleted: (item) => setState(() {
        _items[group] = [
          for (final i in _items[group] ?? const <CategoryItem>[])
            if (i.id != item.id) i,
        ];
      }),
      onReorder: (oldIndex, newIndex) => _reorder(group, oldIndex, newIndex),
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
              SizedBox(width: AppConstants.spaceSm),
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

/// Biggest text on the screen: "Accounts" and "Transactions".
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
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// A rounded card (accent color) with a title, a + button, a divider line
/// and its items. Each item is its own rounded bar (a lighter shade of the
/// accent) with its icon, name, a pen button and a 3-line drag handle.
/// Tap the pen to edit, swipe a bar left to delete, drag the handle to
/// change the order.
///
/// Text sizes, big to small: section header > card title > category name.
class _CategoryGroupCard extends StatelessWidget {
  final bool useColor;
  final String Function(CategoryItem item) iconKeyFor;
  final String title;
  final List<CategoryItem> items;
  final bool editable;
  final IconData Function(CategoryItem item) iconFor;
  final VoidCallback onAdd;
  final ValueChanged<CategoryItem> onTapItem;
  final Future<bool> Function(CategoryItem item) onDeleteItem;
  final ValueChanged<CategoryItem> onDeleted;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _CategoryGroupCard({
    required this.useColor,
    required this.iconKeyFor,
    required this.title,
    required this.items,
    required this.editable,
    required this.iconFor,
    required this.onAdd,
    required this.onTapItem,
    required this.onDeleteItem,
    required this.onDeleted,
    required this.onReorder,
  });

  /// One category as a bar. Swipe right-to-left to delete.
  /// [index] is its place in the list (used by the drag handle).
  Widget _bar(
    BuildContext context,
    CategoryItem item,
    int index,
    Color fg,
    Color barColor,
  ) {
    final theme = Theme.of(context);
    final tint =
        (useColor && item.color != null) ? Color(item.color!) : null;
    final iconKey = iconKeyFor(item);
    final isImg = _CategoryIcons.isImage(iconKey);

    final bar = Material(
      color: barColor,
      borderRadius: BorderRadius.circular(AppConstants.categoryBarRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: editable ? () => onTapItem(item) : null,
        child: Padding(
          padding: EdgeInsets.only(
            left: AppConstants.spaceSmMd,
            right: editable ? AppConstants.spaceXs : AppConstants.spaceSmMd,
            top: AppConstants.spaceSm,
            bottom: AppConstants.spaceSm,
          ),
          child: Row(
            children: [
              // The circle is filled with the chosen color.
              Container(
                width: 44,
                height: 44,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isImg
                      ? null
                      : (tint ??
                          fg.withValues(
                              alpha: AppConstants.categoryAvatarAlpha)),
                ),
                child: _CategoryIcons.view(
                  iconKey,
                  size: isImg ? 44 : 22,
                  color: tint == null ? fg : AppTheme.onColor(tint),
                ),
              ),
              const SizedBox(width: AppConstants.spaceMd),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
              if (editable) ...[
                // Pen: edit name, icon and color.
                IconButton(
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 22,
                    color: fg.withValues(alpha: AppConstants.mutedAlpha),
                  ),
                  tooltip: 'Edit',
                  onPressed: () => onTapItem(item),
                ),
                // 3 lines: press and drag to change the order.
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spaceSm),
                    child: Icon(
                      Icons.drag_handle,
                      size: 24,
                      color: fg.withValues(alpha: AppConstants.mutedAlpha),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    // The locked Transfer category can't be deleted, so no swiping.
    if (!editable) return bar;

    return Dismissible(
      key: ValueKey('$title-${item.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => onDeleteItem(item),
      onDismissed: (_) => onDeleted(item),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppConstants.spaceLg),
        decoration: BoxDecoration(
          color: AppSettings.instance.deleteColor,
          borderRadius: BorderRadius.circular(AppConstants.categoryBarRadius),
        ),
        child: Icon(Icons.delete_outline, color: fg),
      ),
      child: bar,
    );
  }

  /// Space around a bar (also the gap between two bars).
  Widget _spaced(Widget child, {Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceSmMd,
        0,
        AppConstants.spaceSmMd,
        AppConstants.spaceSm,
      ),
      child: child,
    );
  }

  Widget _bars(BuildContext context, Color fg, Color barColor) {
    // Locked list (Transfer): plain bars, nothing to drag.
    if (!editable) {
      return Column(
        children: [
          for (var i = 0; i < items.length; i++)
            _spaced(_bar(context, items[i], i, fg, barColor)),
        ],
      );
    }

    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      // ignore: deprecated_member_use
      onReorder: onReorder,
      // While dragging: no background box or shadow behind the bar, so only
      // the bar itself is seen moving over the card.
      proxyDecorator: (child, index, animation) => Material(
        type: MaterialType.transparency,
        child: child,
      ),
      children: [
        for (var i = 0; i < items.length; i++)
          _spaced(
            _bar(context, items[i], i, fg, barColor),
            key: ValueKey('row-$title-${items[i].id}'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    // A lighter version of the accent color for the category bars.
    final barColor = Color.lerp(
      accent.background,
      Colors.white,
      AppConstants.categoryBarLighten,
    )!;

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
                height: AppConstants.categoryCardHeaderHeight,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
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
                          color: fg.withValues(alpha: AppConstants.mutedAlpha),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Line between the header and the categories.
            Divider(
              height: 1,
              thickness: 1,
              indent: AppConstants.spaceMd,
              endIndent: AppConstants.spaceMd,
              color: fg.withValues(alpha: AppConstants.dividerAlpha),
            ),
            const SizedBox(height: AppConstants.spaceSm),
            if (items.isEmpty && editable)
              ListTile(
                dense: true,
                title: Text(
                  'Nothing yet. Tap + to add.',
                  style: TextStyle(
                    color: fg.withValues(alpha: AppConstants.mutedAlpha),
                  ),
                ),
              ),
            _bars(context, fg, barColor),
            const SizedBox(height: AppConstants.spaceXs),
          ],
        ),
      ),
    );
  }
}

class _NameResult {
  final String name;
  final String icon;
  final int? color; // null = automatic
  const _NameResult(this.name, this.icon, this.color);
}

/// Pop-up to add or edit one item: a Name field, an icon grid and a color
/// bar that opens the same color picker as Settings > General Color.
/// Drawn on the accent color, with Glyph-colored text and buttons.
/// (Deleting is done by swiping the bar, not here.)
class _NameDialog extends StatefulWidget {
  final String title;
  final String initial;
  final String initialIcon;
  final bool showColor;
  final int? initialColor;
  final String colorTitle;

  const _NameDialog({
    required this.title,
    required this.initial,
    required this.initialIcon,
    this.showColor = false,
    this.initialColor,
    this.colorTitle = 'Color',
  });

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller;
  late String _icon;
  int? _color;
  String? _errorText;
  String? _iconError;
  String? _pickedKey; // picture imported in THIS dialog
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _icon = widget.initialIcon;
    _color = widget.initialColor;
  }

  @override
  void dispose() {
    // A picture imported but never saved is not kept.
    final picked = _pickedKey;
    if (picked != null && !(_saved && _icon == picked)) {
      _deleteIconFile(picked);
    }
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Enter a name');
      return;
    }
    _saved = true;
    Navigator.of(context).pop(
      _NameResult(name, _icon, widget.showColor ? _color : null),
    );
  }

  Future<void> _importIcon() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 256,
        maxHeight: 256,
      );
      if (file == null) return;
      final saved = await _storeIconImage(file.path);
      final key = '${AppConstants.iconImagePrefix}$saved';
      if (!mounted) {
        _deleteIconFile(key);
        return;
      }
      _deleteIconFile(_pickedKey); // the one imported before this
      setState(() {
        _icon = key;
        _pickedKey = key;
        _iconError = null;
      });
    } catch (_) {
      if (mounted) setState(() => _iconError = 'Couldn\'t get that image.');
    }
  }

  Widget _iconTile(String key, IconData icon, Color fg, double size) {
    final selected = key == _icon;
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: fg.withValues(
          alpha: selected
              ? AppConstants.iconTileSelectedAlpha
              : AppConstants.iconTileAlpha,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.iconTileRadius),
          side: selected ? BorderSide(color: fg, width: 2) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _icon = key),
          child: Center(child: Icon(icon, size: 18, color: fg)),
        ),
      ),
    );
  }

  /// Import button: 2 icon blocks wide, 1 block high. Shows the imported
  /// picture once one is chosen.
  Widget _importTile(Color fg, double size) {
    final hasImage = _CategoryIcons.isImage(_icon);
    final path = _CategoryIcons.imagePath(_icon);
    return SizedBox(
      width: size * 2 + AppConstants.iconGridGap,
      height: size,
      child: Material(
        color: fg.withValues(alpha: AppConstants.iconTileAlpha),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.iconTileRadius),
          side: hasImage ? BorderSide(color: fg, width: 2) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _importIcon,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage && path != null)
                Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              Center(
                child: hasImage
                    ? Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.file_upload_outlined,
                            size: 14, color: Colors.white),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.file_upload_outlined,
                                  size: 14, color: fg),
                              const SizedBox(width: 3),
                              Text('Import',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: fg)),
                            ],
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

  /// The icon grid: [AppConstants.iconGridColumns] blocks per row, and the
  /// Import block (1 x 2) right after the last icon.
  Widget _iconGrid(Color fg) {
    const columns = AppConstants.iconGridColumns;
    const gap = AppConstants.iconGridGap;
    final entries = _CategoryIcons.all.entries.toList();
    return LayoutBuilder(
      builder: (context, c) {
        final size = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final e in entries) _iconTile(e.key, e.value, fg, size),
            _importTile(fg, size),
          ],
        );
      },
    );
  }
  

  /// Opens the same color picker as Settings > General Color.
  Future<void> _pickColor() async {
    final start = _color != null
        ? Color(_color!)
        : AppTheme.accentOf(context).foreground;
    final picked = await showDialog<Color>(
      context: context,
      barrierColor: AppConstants.popupBarrier,
      builder: (_) => ColorPickerDialog(
        title: widget.colorTitle,
        icon: Icons.palette_outlined,
        initial: start,
      ),
    );
    if (picked != null) setState(() => _color = picked.toARGB32());
  }

  /// A bar that opens the color picker, plus a reset-to-automatic button.
  Widget _colorField(Color fg) {
    final c = _color == null ? null : Color(_color!);
    final label = c == null
        ? 'Automatic'
        : '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    return Row(
      children: [
        Expanded(
          child: Material(
            color: fg.withValues(alpha: AppConstants.tintAlpha),
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _pickColor,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceSmMd,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c ??
                            fg.withValues(alpha: AppConstants.iconTileAlpha),
                        border: Border.all(
                          color: fg.withValues(alpha: AppConstants.borderAlpha),
                        ),
                      ),
                      child: c == null
                          ? Icon(Icons.auto_awesome, size: 16, color: fg)
                          : null,
                    ),
                    const SizedBox(width: AppConstants.spaceSmMd),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: fg),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (c != null)
          IconButton(
            tooltip: 'Automatic',
            icon: Icon(Icons.restart_alt, color: fg),
            onPressed: () => setState(() => _color = null),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final popupTheme = _popupTheme(context);

    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusSm),
          borderSide: BorderSide(color: color, width: width),
        );

    return _accentDialog(
      context,
      title: widget.title,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              cursorColor: fg,
              style: TextStyle(color: fg),
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(
                  color: fg.withValues(alpha: AppConstants.mutedAlpha),
                ),
                floatingLabelStyle: TextStyle(color: fg),
                errorText: _errorText,
                isDense: true,
                border: border(fg.withValues(alpha: AppConstants.borderAlpha), 1),
                enabledBorder:
                    border(fg.withValues(alpha: AppConstants.borderAlpha), 1),
                focusedBorder: border(fg, 2),
              ),
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: AppConstants.spaceMd),
            Text(
              'Icon',
              style: popupTheme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            const SizedBox(height: AppConstants.spaceSm),
            _iconGrid(fg),
            if (_iconError != null) ...[
              const SizedBox(height: AppConstants.spaceXs),
              Text(_iconError!, style: TextStyle(fontSize: 13, color: fg)),
            ],
            if (widget.showColor) ...[
              const SizedBox(height: AppConstants.spaceMd),
              Text(
                'Color',
                style: popupTheme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              const SizedBox(height: AppConstants.spaceSm),
              _colorField(fg),
            ],
            const SizedBox(height: AppConstants.spaceSm),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}