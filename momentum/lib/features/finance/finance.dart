import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/failures.dart';
import '../../core/screens/settings.dart';
import '../../core/themes.dart';
import '../../core/utils.dart';
import '../../database/helper.dart';

/// One account as shown on a card.
class _AccountCardData {
  final int id;
  final String name;
  final int typeId;
  final String typeName;
  final String? typeIcon;
  final String category;
  final String? categoryIcon;
  final double balance;
  final String? noteTitle;
  final String? noteBody;

  const _AccountCardData({
    required this.id,
    required this.name,
    required this.typeId,
    required this.typeName,
    required this.typeIcon,
    required this.category,
    required this.categoryIcon,
    required this.balance,
    this.noteTitle,
    this.noteBody,
  });
}

/// Icons an account type can use (same keys as the Categories screen).
const Map<String, IconData> _typeIcons = {
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

/// Default icon of each seed account type, used when none is saved.
const Map<String, String> _typeIconDefaults = {
  'Cash': 'cash',
  'Bank': 'bank',
  'Digital Bank': 'phone',
  'Credit': 'card',
  'E-Wallet': 'wallet',
  'Investment': 'trending',
  'Assets': 'home',
  'Debt': 'handshake',
  'Business': 'business',
};

IconData _iconForType(String name, String? saved) {
  if (saved != null && _typeIcons.containsKey(saved)) return _typeIcons[saved]!;
  return _typeIcons[_typeIconDefaults[name] ?? 'wallet']!;
}

/// Account category icon: the saved one, or a plain label.
IconData _iconForCategory(String? saved) {
  if (saved != null && _typeIcons.containsKey(saved)) return _typeIcons[saved]!;
  return _typeIcons['label']!;
}

// ------------------------------------------------------------------
// Account card size.
// The values that tune it (card ratio, sample width, how much the card
// and its text follow the font size) are in AppConstants:
//   cardSampleWidth, cardRatio, bigTextScale, baseCardWidth,
//   cardFollow, textFollow.
// Every size inside the card (icon, spacing, corners) is a multiple of
// "u" = card width / cardSampleWidth.
// ------------------------------------------------------------------

double _fontScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(AppConstants.baseFontSize) /
    AppConstants.baseFontSize;

/// Card width: slightly smaller or bigger than the "Big" size.
double _cardWidthFor(BuildContext context) =>
    AppConstants.baseCardWidth *
    (1 +
        (_fontScale(context) - AppConstants.bigTextScale) *
            AppConstants.cardFollow);

/// Text size multiplier inside the card (1.0 at "Big").
double _textFactorFor(BuildContext context) =>
    1 +
    (_fontScale(context) - AppConstants.bigTextScale) * AppConstants.textFollow;

double _cardHeightFor(double width) => width / AppConstants.cardRatio;

/// Empty space left under the lists so the floating + button
/// (56 button + 8 ring, scaled with the font) never covers the last card.
double _addButtonClearanceOf(BuildContext context) =>
    (56 + 8) * _fontScale(context) * AppConstants.addButtonScale +
    AppConstants.spaceMd * 2;

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  /// Where the order of the account types is saved on the phone.
  static const String _orderPref = 'finance.typeOrder';

  AccountsSummary _summary = AccountsSummary.empty;
  List<_AccountCardData> _accounts = const [];
  String? _error;

  // true = amounts are hidden (eye closed), false = amounts are shown.
  bool _hideAmounts = false;

  // false = sideways cards, true = list of rows.
  bool _listView = false;

  // true while the user is dragging account types to reorder them.
  bool _rearranging = false;

  // saved order of the account type ids.
  List<int> _typeOrder = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadOrder();
    // Reload whenever the database reports a change.
    DatabaseHelper.instance.changes.addListener(_load);
  }

  @override
  void dispose() {
    DatabaseHelper.instance.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _loadOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_orderPref) ?? const <String>[];
      if (!mounted) return;
      setState(() {
        _typeOrder = [
          for (final id in saved)
            if (int.tryParse(id) != null) int.parse(id),
        ];
      });
    } catch (_) {
      // No saved order: the normal (id) order is used.
    }
  }

  Future<void> _saveOrder(List<int> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_orderPref, [for (final id in ids) '$id']);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Couldn\'t save the new order.')),
        );
    }
  }

  /// Active accounts with their type, category and current balance.
  Future<List<_AccountCardData>> _loadAccounts() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('''
      SELECT a.id, a.name, a.type_id, a.note_title, a.note_body,
             t.name AS type_name, t.icon AS type_icon,
             c.name AS category_name, c.icon AS category_icon,
             b.balance AS balance
      FROM accounts a
      JOIN account_types t ON t.id = a.type_id
      JOIN account_categories c ON c.id = a.category_id
      JOIN account_balances b ON b.account_id = a.id
      WHERE a.deleted_at IS NULL
      ORDER BY t.id, a.id
    ''');
    return [
      for (final row in rows)
        _AccountCardData(
          id: (row['id'] as num).toInt(),
          name: row['name'] as String,
          typeId: (row['type_id'] as num).toInt(),
          typeName: row['type_name'] as String,
          typeIcon: row['type_icon'] as String?,
          category: row['category_name'] as String,
          categoryIcon: row['category_icon'] as String?,
          balance:
              (row['balance'] as num).toInt() / AppConstants.centavosPerPeso,
          noteTitle: row['note_title'] as String?,
          noteBody: row['note_body'] as String?,
        ),
    ];
  }

  Future<void> _load() async {
    try {
      final summary = await DatabaseHelper.instance.getAccountsSummary();
      final accounts = await _loadAccounts();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _accounts = accounts;
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

  /// Accounts grouped by account type, in the saved order.
  /// Types that are not in the saved order yet go to the end (by id).
  List<List<_AccountCardData>> get _groups {
    final groups = <int, List<_AccountCardData>>{};
    for (final account in _accounts) {
      groups.putIfAbsent(account.typeId, () => []).add(account);
    }
    final ids = groups.keys.toList();
    final rank = {for (var i = 0; i < _typeOrder.length; i++) _typeOrder[i]: i};
    const last = 1 << 30;
    ids.sort((a, b) {
      final ra = rank[a] ?? last;
      final rb = rank[b] ?? last;
      if (ra != rb) return ra.compareTo(rb);
      return a.compareTo(b);
    });
    return [for (final id in ids) groups[id]!];
  }

  /// Tap. Finishes rearranging, or switches card view <-> list view.
  void _onViewButtonTap() {
    setState(() {
      if (_rearranging) {
        _rearranging = false;
      } else {
        _listView = !_listView;
      }
    });
  }

  /// Long press. Starts rearranging the account types.
  void _onViewButtonLongPress() {
    if (_rearranging) return;
    HapticFeedback.mediumImpact();
    setState(() => _rearranging = true);
  }

  /// Moves one account type to a new place and saves the order.
  void _reorderTypes(
    List<List<_AccountCardData>> groups,
    int oldIndex,
    int newIndex,
  ) {
    if (newIndex == oldIndex) return;
    final ids = [for (final g in groups) g.first.typeId];
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    setState(() => _typeOrder = ids);
    _saveOrder(ids);
  }

  /// Pops the "New Account" sheet up from the bottom.
  Future<void> _addAccount() {
    final accent = AppTheme.accentOf(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: accent.background,
      barrierColor: AppConstants.popupBarrier,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _AddAccountSheet(),
    );
  }

  /// The Rearrange button. Tap = view, long press = reorder types.
  Widget _viewButton() {
    final IconData icon;
    final String label;
    if (_rearranging) {
      icon = Icons.check;
      label = 'Done';
    } else if (_listView) {
      icon = Icons.view_agenda_outlined;
      label = 'Card view';
    } else {
      icon = Icons.view_headline;
      label = 'List view';
    }
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: _onViewButtonTap,
        onLongPress: _onViewButtonLongPress,
        radius: 24,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(child: Icon(icon)),
        ),
      ),
    );
  }

  /// One bar per account type that can be dragged.
  Widget _rearrangeList(
    BuildContext context,
    List<List<_AccountCardData>> groups,
  ) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceMd + AppConstants.spaceXs,
            AppConstants.spaceSm,
            AppConstants.spaceMd,
            AppConstants.spaceXs,
          ),
        ),
        Expanded(
          child: ReorderableListView(
            padding: EdgeInsets.fromLTRB(
              AppConstants.spaceMd,
              AppConstants.spaceSm,
              AppConstants.spaceMd,
              _addButtonClearanceOf(context),
            ),
            buildDefaultDragHandles: false,
            onReorderItem: (oldIndex, newIndex) =>
                _reorderTypes(groups, oldIndex, newIndex),
            // While dragging: no extra box or shadow, only the bar moves.
            proxyDecorator: (child, index, animation) => Material(
              type: MaterialType.transparency,
              child: child,
            ),
            children: [
              for (var i = 0; i < groups.length; i++)
                Padding(
                  key: ValueKey('type-${groups[i].first.typeId}'),
                  padding: const EdgeInsets.only(bottom: AppConstants.spaceSm),
                  child: Material(
                    color: accent.background,
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spaceSmMd,
                        vertical: AppConstants.spaceSm,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: fg.withValues(
                                alpha: AppConstants.tintAlpha,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusSm,
                              ),
                            ),
                            child: Icon(
                              _iconForType(
                                groups[i].first.typeName,
                                groups[i].first.typeIcon,
                              ),
                              size: 22,
                              color: fg,
                            ),
                          ),
                          const SizedBox(width: AppConstants.spaceSmMd),
                          Expanded(
                            child: Text(
                              groups[i].first.typeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: fg,
                              ),
                            ),
                          ),
                          Text(
                            '${groups[i].length}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: fg.withValues(
                                alpha: AppConstants.mutedAlpha,
                              ),
                            ),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.all(
                                AppConstants.spaceSm,
                              ),
                              child: Icon(
                                Icons.drag_handle,
                                size: 24,
                                color: fg.withValues(
                                  alpha: AppConstants.mutedAlpha,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = _groups;

    // Column: the top part stays fixed, only the Expanded part scrolls.
    // Nothing is padded at the top so the card still starts behind the
    // status bar and the transparent app bar.
    return Column(
      children: [
        // ----- Fixed part -----
        TotalBalanceCard(summary: _summary, hidden: _hideAmounts),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceMd + AppConstants.spaceXs,
            AppConstants.spaceMd,
            AppConstants.spaceSm,
            0,
          ),
          child: Row(
            children: [
              Text(
                'My Accounts',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add Account',
                onPressed: _addAccount,
              ),
              // Eye button. Open eye = amounts shown, closed = hidden.
              IconButton(
                icon: Icon(
                  _hideAmounts
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                tooltip: _hideAmounts ? 'Show amounts' : 'Hide amounts',
                onPressed: () => setState(() => _hideAmounts = !_hideAmounts),
              ),
              // Tap = card / list view, long press = reorder types.
              _viewButton(),
            ],
          ),
        ),

        // ----- Scrolling part: starts right below the My Accounts row -----
        Expanded(
          child: _rearranging
              ? _rearrangeList(context, groups)
              : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // One section per account type.
                    for (final group in groups)
                      _AccountTypeSection(
                        accounts: group,
                        hidden: _hideAmounts,
                        listView: _listView,
                      ),
                    // Room for the floating + button.
                    SizedBox(height: _addButtonClearanceOf(context)),
                  ],
                ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------
// New Account bottom sheet
// ------------------------------------------------------------------

/// Bottom sheet that opens from the "+" button next to "My Accounts".
/// Background = accent color, text / icons / outlines = glyph color.
/// Types and categories come from the app's own database lists.
class _AddAccountSheet extends StatefulWidget {
  const _AddAccountSheet();

  @override
  State<_AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<_AddAccountSheet> {
  static const int _noteTitleMax = 30;
  static const int _noteBodyMax = 120;
  static const double _fieldRadius = 4;
  static const double _sidePad = 20;
  static const double _gap = 12; // space between fields
  static const double _fieldVPad = 15; // text field height
  static const double _selectorVPad = 12; // Type / Category height

  // Balance text: normal size, and the smallest it shrinks to.
  static const double _balanceMaxFont = 16;
  static const double _balanceMinFont = 8;

  final _name = TextEditingController();
  final _balance = TextEditingController();
  final _noteTitle = TextEditingController();
  final _noteBody = TextEditingController();

  List<CategoryItem> _types = const [];
  List<CategoryItem> _categories = const [];
  CategoryItem? _type;
  CategoryItem? _category;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _balance, _noteTitle, _noteBody]) {
      c.addListener(_refresh);
    }
    _loadLists();
  }

  @override
  void dispose() {
    for (final c in [_name, _balance, _noteTitle, _noteBody]) {
      c.removeListener(_refresh);
      c.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadLists() async {
    try {
      final db = DatabaseHelper.instance;
      final types = await db.getCategoryItems(CategoryGroup.accountType);
      final categories = await db.getCategoryItems(
        CategoryGroup.accountCategory,
      );
      if (!mounted) return;
      setState(() {
        _types = types;
        _categories = categories;
      });
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  bool get _canSave =>
      !_saving &&
      _name.text.trim().isNotEmpty &&
      _type != null &&
      _category != null;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DatabaseHelper.instance.addAccount(
        name: _name.text,
        typeId: _type!.id,
        categoryId: _category!.id,
        initialBalance: double.tryParse(_balance.text.trim()) ?? 0,
        noteTitle: _noteTitle.text,
        noteBody: _noteBody.text,
      );
      if (mounted) Navigator.of(context).pop();
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      if (mounted) setState(() => _error = const UnknownFailure().message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickType() async {
    final picked = await _pickItem(
      context,
      title: 'Type',
      items: _types,
      selected: _type,
      iconFor: (item) => _iconForType(item.name, item.icon),
    );
    if (picked != null) setState(() => _type = picked);
  }

  Future<void> _pickCategory() async {
    final picked = await _pickItem(
      context,
      title: 'Category',
      items: _categories,
      selected: _category,
      iconFor: (item) => _iconForCategory(item.icon),
    );
    if (picked != null) setState(() => _category = picked);
  }

  /// The biggest font size (down to the minimum) at which the typed
  /// balance still fits inside the field. No limit on how long it can be.
  double _balanceFontSize(double fieldWidth) {
    final text = _balance.text;
    if (text.isEmpty) return _balanceMaxFont;

    // Space left for the text: minus the prefix icon (48) and the padding.
    final available = fieldWidth - 48 - AppConstants.spaceMd * 2;

    var size = _balanceMaxFont;
    while (size > _balanceMinFont) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: TextStyle(fontSize: size)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (painter.width <= available) break;
      size -= 0.5;
    }
    return size;
  }

  /// Outlined box look shared by every field (glyph-colored outline).
  InputDecoration _decoration(
    Color fg, {
    required String label,
    required Widget icon,
    Widget? suffix,
    FloatingLabelBehavior? floating,
    double vPad = _fieldVPad,
  }) {
    OutlineInputBorder border(double alpha, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(_fieldRadius),
      borderSide: BorderSide(
        color: fg.withValues(alpha: alpha),
        width: width,
      ),
    );
    return InputDecoration(
      isDense: true, // icons no longer force a 48px minimum height
      labelText: label,
      labelStyle: TextStyle(
        color: fg.withValues(alpha: AppConstants.mutedAlpha),
      ),
      floatingLabelStyle: TextStyle(color: fg),
      floatingLabelBehavior: floating,
      prefixIcon: icon,
      suffixIcon: suffix,
      contentPadding: EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMd,
        vertical: vPad,
      ),
      border: border(AppConstants.borderAlpha, 1),
      enabledBorder: border(AppConstants.borderAlpha, 1),
      focusedBorder: border(1, 2),
    );
  }

  /// A tappable box that looks like the other fields (Type / Category).
  Widget _selector({
    required Color fg,
    required String label,
    required CategoryItem? value,
    required IconData Function(CategoryItem) iconFor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(_fieldRadius),
      child: InputDecorator(
        isEmpty: value == null,
        decoration: _decoration(
          fg,
          label: label,
          vPad: _selectorVPad,
          icon: Icon(
            value == null ? Icons.touch_app_outlined : iconFor(value),
            color: fg,
          ),
          suffix: Icon(Icons.expand_more, color: fg),
        ),
        child: Text(
          value?.name ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: fg, fontSize: 16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);

    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          primary: fg,
          onPrimary: bg,
          onSurface: fg,
          onSurfaceVariant: muted,
        ),
        textSelectionTheme: TextSelectionThemeData(cursorColor: fg),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            _sidePad,
            AppConstants.spaceSmMd,
            _sidePad,
            AppConstants.spaceMd,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: AppConstants.borderAlpha),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceSmMd),

              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: AppConstants.tintAlpha),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet_outlined,
                      color: fg,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceMd),
                  Text(
                    'New Account',
                    style: base.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceMd),

              // Account name
              TextField(
                controller: _name,
                style: TextStyle(color: fg, fontSize: 16),
                cursorColor: fg,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: _decoration(
                  fg,
                  label: 'Account Name',
                  icon: Icon(Icons.label_outline, color: fg),
                ),
              ),
              const SizedBox(height: _gap),

              // Initial balance: no length limit, the text shrinks to fit.
              LayoutBuilder(
                builder: (context, constraints) {
                  final size = _balanceFontSize(constraints.maxWidth);
                  return TextField(
                    controller: _balance,
                    style: TextStyle(color: fg, fontSize: size),
                    cursorColor: fg,
                    maxLines: 1,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    decoration: _decoration(
                      fg,
                      label: 'Initial Balance (${AppConstants.currencySymbol})',
                      icon: Icon(Icons.payments_outlined, color: fg),
                    ),
                  );
                },
              ),
              const SizedBox(height: _gap),

              // Type + Category side by side
              Row(
                children: [
                  Expanded(
                    child: _selector(
                      fg: fg,
                      label: 'Type',
                      value: _type,
                      iconFor: (item) => _iconForType(item.name, item.icon),
                      onTap: _pickType,
                    ),
                  ),
                  const SizedBox(width: _gap),
                  Expanded(
                    child: _selector(
                      fg: fg,
                      label: 'Category',
                      value: _category,
                      iconFor: (item) => _iconForCategory(item.icon),
                      onTap: _pickCategory,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: _gap),

              // Card theme (empty for now)
              InkWell(
                onTap: () {}, // TODO: card theme picker
                borderRadius: BorderRadius.circular(_fieldRadius),
                child: InputDecorator(
                  decoration: _decoration(
                    fg,
                    label: 'Card Theme',
                    vPad: _selectorVPad,
                    floating: FloatingLabelBehavior.always,
                    icon: Icon(Icons.style_outlined, color: fg),
                    suffix: Icon(Icons.chevron_right, color: fg),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 24,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: LinearGradient(
                            colors: [
                              fg.withValues(alpha: 0.35),
                              fg.withValues(alpha: 0.15),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: AppConstants.spaceSmMd),
                      Text(
                        'Classic',
                        style: TextStyle(color: fg, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: _gap),

              // Note: a short title (30) and a longer body (120)
              Container(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spaceMd,
                  AppConstants.spaceXs,
                  AppConstants.spaceMd,
                  AppConstants.spaceXs,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_fieldRadius),
                  border: Border.all(
                    color: fg.withValues(alpha: AppConstants.borderAlpha),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.notes, color: fg),
                        const SizedBox(width: AppConstants.spaceMd),
                        Expanded(
                          child: TextField(
                            controller: _noteTitle,
                            maxLength: _noteTitleMax,
                            style: TextStyle(color: fg, fontSize: 16),
                            cursorColor: fg,
                            decoration: InputDecoration(
                              hintText: 'Note',
                              hintStyle: TextStyle(color: muted),
                              counterText: '',
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: AppConstants.spaceSm,
                              ),
                            ),
                          ),
                        ),
                        Text(
                          '${_noteTitle.text.length} / $_noteTitleMax',
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                      ],
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: fg.withValues(alpha: AppConstants.dividerAlpha),
                    ),
                    TextField(
                      controller: _noteBody,
                      maxLength: _noteBodyMax,
                      minLines: 2,
                      maxLines: 2,
                      style: TextStyle(color: fg, fontSize: 16),
                      cursorColor: fg,
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: AppConstants.spaceSm,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${_noteBody.text.length} / $_noteBodyMax',
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: AppConstants.spaceSm),
                Text(
                  _error!,
                  style: base.textTheme.bodySmall?.copyWith(color: fg),
                ),
              ],
              const SizedBox(height: AppConstants.spaceMd),

              // Add button (greyed out until name, type and category are set)
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _canSave ? _save : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Second bottom sheet: a wrap of chips (icon + name) to pick one item.
Future<CategoryItem?> _pickItem(
  BuildContext context, {
  required String title,
  required List<CategoryItem> items,
  required IconData Function(CategoryItem) iconFor,
  CategoryItem? selected,
}) {
  final base = Theme.of(context);
  final accent = AppTheme.accentOf(context);
  final fg = accent.foreground;

  return showModalBottomSheet<CategoryItem>(
    context: context,
    backgroundColor: accent.background,
    barrierColor: AppConstants.popupBarrier,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceLg,
        AppConstants.spaceSmMd,
        AppConstants.spaceLg,
        AppConstants.spaceLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: AppConstants.borderAlpha),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spaceLg),
          Text(
            title,
            style: base.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          const SizedBox(height: AppConstants.spaceMd),
          Wrap(
            spacing: AppConstants.spaceSm,
            runSpacing: AppConstants.spaceSm,
            children: [
              for (final item in items)
                Material(
                  color: fg.withValues(
                    alpha: item.id == selected?.id
                        ? AppConstants.iconTileSelectedAlpha
                        : AppConstants.tintAlpha,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(sheetContext).pop(item),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spaceMd,
                        vertical: AppConstants.spaceSmMd + 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(iconFor(item), size: 15, color: fg),
                          const SizedBox(width: AppConstants.spaceSm),
                          Text(
                            item.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: fg,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// A header (type icon + type name) with either a sideways list of its
/// cards or, in list view, a column of rows.
class _AccountTypeSection extends StatelessWidget {
  final List<_AccountCardData> accounts;
  final bool hidden;
  final bool listView;

  const _AccountTypeSection({
    required this.accounts,
    required this.hidden,
    required this.listView,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final first = accounts.first;

    // The card follows the font size, but only a little.
    final cardWidth = _cardWidthFor(context);
    final cardHeight = _cardHeightFor(cardWidth);

    // The icon box follows the size of the type name text.
    // At the default size (16) this gives a 36 box and a 20 icon.
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final textSize = MediaQuery.textScalerOf(
      context,
    ).scale(titleStyle?.fontSize ?? 16);
    final boxSize = textSize * 2.25;
    final iconSize = textSize * 1.25;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceMd,
            AppConstants.spaceMd,
            AppConstants.spaceMd,
            AppConstants.spaceSmMd,
          ),
          child: Row(
            children: [
              Container(
                width: boxSize,
                height: boxSize,
                decoration: BoxDecoration(
                  color: accent.background,
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Icon(
                  _iconForType(first.typeName, first.typeIcon),
                  size: iconSize,
                  color: accent.foreground,
                ),
              ),
              const SizedBox(width: AppConstants.spaceSmMd),
              Text(first.typeName, style: titleStyle),
            ],
          ),
        ),
        if (listView)
          // List view, one row per account.
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spaceMd,
            ),
            child: Column(
              children: [
                for (final account in accounts)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: AppConstants.spaceSm,
                    ),
                    child: _AccountListTile(account: account, hidden: hidden),
                  ),
              ],
            ),
          )
        else
          SizedBox(
            height: cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceMd,
              ),
              itemCount: accounts.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: AppConstants.spaceSmMd),
              itemBuilder: (context, i) => SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: _FlipAccountCard(
                  account: accounts[i],
                  hidden: hidden,
                  width: cardWidth,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One account as a row (list view). It has everything the front of
/// the card has: category icon, name, balance and category.
class _AccountListTile extends StatelessWidget {
  final _AccountCardData account;
  final bool hidden;

  const _AccountListTile({required this.account, required this.hidden});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;

    final balanceText = hidden
        ? '${AppConstants.currencySymbol} ${AppConstants.maskText}'
        : Utils.formatCurrency(
            account.balance,
            symbol: AppConstants.currencyPrefix,
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMd,
        vertical: AppConstants.spaceSmMd,
      ),
      decoration: BoxDecoration(
        color: accent.background,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Row(
        children: [
          // Text first (left side)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: fg.withValues(alpha: AppConstants.mutedAlpha),
                  ),
                ),
                const SizedBox(height: 2),
                // Balance shrinks to fit, however long it is.
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      balanceText,
                      maxLines: 1,
                      softWrap: false,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spaceXs),
                // Smaller tag (smaller than the account name)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spaceSm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: AppConstants.tintAlpha),
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  ),
                  child: Text(
                    account.category.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppConstants.spaceMd),
          // Category icon on the right side
          Container(
            width: 33,
            height: 33,
            decoration: BoxDecoration(
              color: fg.withValues(alpha: AppConstants.tintAlpha),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Icon(
              _iconForCategory(account.categoryIcon),
              size: 26,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// An account card that flips over when tapped (front <-> back).
class _FlipAccountCard extends StatefulWidget {
  final _AccountCardData account;
  final bool hidden;
  final double width;

  const _FlipAccountCard({
    required this.account,
    required this.hidden,
    required this.width,
  });

  @override
  State<_FlipAccountCard> createState() => _FlipAccountCardState();
}

class _FlipAccountCardState extends State<_FlipAccountCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppConstants.cardFlipDuration,
  );
  bool _showBack = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _flip() {
    if (_showBack) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    _showBack = !_showBack;
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);

    // The text size is worked out here (a small adjustment around the
    // "Big" size), so the full font size scaling is switched off inside
    // the card to avoid scaling the text twice.
    final textFactor = _textFactorFor(context);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: GestureDetector(
        onTap: _flip,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final curved = Curves.easeInOut.transform(_controller.value);
            final angle = curved * math.pi;
            final isFront = angle < math.pi / 2;

            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(angle),
              child: isFront
                  ? _CardFront(
                      account: widget.account,
                      hidden: widget.hidden,
                      accent: accent,
                      width: widget.width,
                      textFactor: textFactor,
                    )
                  // The back is turned around so its text isn't mirrored.
                  : Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(math.pi),
                      child: _CardBack(
                        account: widget.account,
                        accent: accent,
                        width: widget.width,
                        textFactor: textFactor,
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// Front: category icon on the top right, then name, balance and category
/// at the bottom left. Sizes are measured from the sample (u = width / 612).
/// Text sizes use k = u * textFactor, so at the Big font size they match
/// the sample and change only slightly at other sizes.
/// The name and the balance shrink to fit the card, however long they are.
class _CardFront extends StatelessWidget {
  final _AccountCardData account;
  final bool hidden;
  final AppAccent accent;
  final double width;
  final double textFactor;

  const _CardFront({
    required this.account,
    required this.hidden,
    required this.accent,
    required this.width,
    required this.textFactor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = accent.foreground;
    final u = width / AppConstants.cardSampleWidth;
    final k = u * textFactor; // text size unit

    final balanceText = hidden
        ? '${AppConstants.currencySymbol} ${AppConstants.maskText}'
        : Utils.formatCurrency(
            account.balance,
            symbol: AppConstants.currencyPrefix,
          );

    return Container(
      width: width,
      height: _cardHeightFor(width),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: accent.background,
        borderRadius: BorderRadius.circular(40 * u),
      ),
      child: Stack(
        children: [
          // Icon, top right (the account's category icon)
          Positioned(
            top: 29 * u,
            right: 28 * u,
            child: Container(
              width: 62 * u,
              height: 62 * u,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: AppConstants.tintAlpha),
                borderRadius: BorderRadius.circular(16 * u),
              ),
              child: Icon(
                _iconForCategory(account.categoryIcon),
                size: 32 * u,
                color: fg,
              ),
            ),
          ),
          // Name, balance and category, bottom left
          Positioned(
            left: 40 * u,
            right: 40 * u,
            bottom: 39 * u,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    account.name,
                    maxLines: 1,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 26 * k,
                      height: 1.2,
                      fontWeight: FontWeight.w400,
                      color: fg.withValues(alpha: AppConstants.mutedAlpha),
                    ),
                  ),
                ),
                SizedBox(height: 14 * u),
                // Balance: shrinks to fit the card width (no size limit).
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      balanceText,
                      maxLines: 1,
                      softWrap: false,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 52 * k,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 17 * u),
                // Category: only under the balance, as small as its text.
                // It grows with the text instead of having a fixed height.
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 18 * u,
                    vertical: 7 * u,
                  ),
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: AppConstants.tintAlpha),
                    borderRadius: BorderRadius.circular(17 * u),
                  ),
                  child: Text(
                    account.category.toUpperCase(),
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 19 * k,
                      height: 1.0,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.5 * u,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Back: a dark band (the same on every card), a small notes box under it,
/// then a bigger notes area with no box. Sizes are measured from the sample
/// (u = width / 612) and fitted to the real card height. Text changes
/// slightly with the font size like the front.
class _CardBack extends StatelessWidget {
  final _AccountCardData account;
  final AppAccent accent;
  final double width;
  final double textFactor;

  const _CardBack({
    required this.account,
    required this.accent,
    required this.width,
    required this.textFactor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = accent.foreground;
    final u = width / AppConstants.cardSampleWidth;
    final k = u * textFactor; // text size unit

    final title = account.noteTitle?.trim() ?? '';
    final body = account.noteBody?.trim() ?? '';

    return Container(
      width: width,
      height: _cardHeightFor(width),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: accent.background,
        borderRadius: BorderRadius.circular(40 * u),
      ),
      child: Stack(
        children: [
          // The black band, the same on every card.
          Positioned(
            top: 58 * u,
            left: 0,
            right: 0,
            height: 70 * u,
            child: Container(
              color: Colors.black.withValues(alpha: AppConstants.cardBandAlpha),
            ),
          ),
          // First notes section: the small one, with a box.
          Positioned(
            top: 160 * u,
            left: 38 * u,
            right: 39 * u,
            height: 53 * u,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20 * u),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: AppConstants.tintAlpha),
                borderRadius: BorderRadius.circular(14 * u),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  title.isEmpty ? 'Notes' : title,
                  maxLines: 1,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 24 * k,
                    height: 1.0,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ),
          ),
          // Second notes section: the bigger one, no box.
          Positioned(
            top: 228 * u,
            left: 58 * u,
            right: 58 * u,
            bottom: 82 * u,
            child: Text(
              body.isEmpty ? 'Notes' : body,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 24 * k,
                height: 1.2,
                fontWeight: FontWeight.w400,
                color: fg.withValues(alpha: AppConstants.mutedAlpha),
              ),
            ),
          ),
          // Type icon, bottom left
          Positioned(
            left: 40 * u,
            bottom: 34 * u,
            child: Icon(
              _iconForType(account.typeName, account.typeIcon),
              size: 34 * u,
              color: fg.withValues(alpha: AppConstants.mutedAlpha),
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel at the top of the Finance page.
/// It draws behind the status bar and the (transparent) app bar.
/// Its margins, radius, balance weight and mask settings are in
/// AppConstants (totalCard*, balanceWeight, balanceFontSize, maskDrop,
/// maskText).
class TotalBalanceCard extends StatelessWidget {
  final AccountsSummary summary;

  /// When true, the balance, income and expense are masked with asterisks.
  final bool hidden;

  const TotalBalanceCard({
    super.key,
    required this.summary,
    this.hidden = false,
  });

  static String _plain(double v) => Utils.formatCurrency(v, symbol: '');

  /// Draws the asterisks vertically centered on the text line.
  /// The `*` glyph normally sits high, so it is shifted down.
  /// [prefix] (for example the peso sign) stays on the normal baseline.
  static Widget _maskedText(
    BuildContext context,
    TextStyle? style, {
    String prefix = '',
  }) {
    final size = style?.fontSize ?? AppConstants.baseFontSize;
    final drop =
        MediaQuery.textScalerOf(context).scale(size) * AppConstants.maskDrop;
    return Text.rich(
      TextSpan(
        children: [
          if (prefix.isNotEmpty) TextSpan(text: prefix),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Transform.translate(
              offset: Offset(0, drop),
              child: Text(AppConstants.maskText, style: style),
            ),
          ),
        ],
      ),
      style: style,
    );
  }

  // Rebuilds the card when a setting (like a transaction color) changes.
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) => _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);

    // Colors picked in Settings > Theme > Specific Color
    final incomeColor = AppSettings.instance.incomeColor;
    final expenseColor = AppSettings.instance.expenseColor;

    // Space taken by the status bar + app bar, so content starts below them.
    final topInset = MediaQuery.viewPaddingOf(context).top + kToolbarHeight;

    final balanceStyle = theme.textTheme.headlineLarge?.copyWith(
      fontSize: AppConstants.balanceFontSize,
      fontWeight: AppConstants.balanceWeight,
      color: fg,
      height: 1.0, // removes the font's extra line spacing
    );
    final incomeStyle = theme.textTheme.labelSmall?.copyWith(
      color: incomeColor,
      fontWeight: FontWeight.w600,
    );
    final expenseStyle = theme.textTheme.labelSmall?.copyWith(
      color: expenseColor,
      fontWeight: FontWeight.w600,
    );

    final card = Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppConstants.totalCardSideMargin,
        topInset + AppConstants.totalCardTopMargin,
        AppConstants.totalCardSideMargin,
        AppConstants.totalCardBottomMargin,
      ),
      decoration: BoxDecoration(
        color: accent.background,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppConstants.totalCardRadius),
        ),
      ),
      child: Column(
        // Shrinks to the content when the ratio is off.
        mainAxisSize: AppConstants.totalCardUseRatio
            ? MainAxisSize.max
            : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // "Total Balance" on the left, account count on the right
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Balance',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
              Text(
                '${summary.accountCount} '
                '${summary.accountCount == 1 ? 'Account' : 'Accounts'}',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.totalCardLabelGap),
          // Big balance (left) and analytics (right) on one row.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Big balance takes the leftover space and shrinks if needed.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: hidden
                      ? _maskedText(
                          context,
                          balanceStyle,
                          prefix: AppConstants.currencyPrefix,
                        )
                      : Text(
                          Utils.formatCurrency(
                            summary.totalBalance,
                            symbol: AppConstants.currencyPrefix,
                          ),
                          maxLines: 1,
                          softWrap: false,
                          style: balanceStyle,
                        ),
                ),
              ),
              const SizedBox(width: AppConstants.spaceSm),
              // Analytics: income | expense (right side), colors come from
              // Settings > Theme > Specific Color.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_upward,
                    size: 11,
                    color: incomeColor,
                  ),
                  const SizedBox(width: 2),
                  hidden
                      ? _maskedText(context, incomeStyle)
                      : Text(_plain(summary.income), style: incomeStyle),
                  const SizedBox(width: AppConstants.spaceSm),
                  Container(
                    width: 1,
                    height: 12,
                    color: fg.withValues(alpha: AppConstants.separatorAlpha),
                  ),
                  const SizedBox(width: AppConstants.spaceSm),
                  Icon(
                    Icons.arrow_downward,
                    size: 11,
                    color: expenseColor,
                  ),
                  const SizedBox(width: 2),
                  hidden
                      ? _maskedText(context, expenseStyle)
                      : Text(_plain(summary.expense), style: expenseStyle),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return AppConstants.totalCardUseRatio
        ? AspectRatio(aspectRatio: AppConstants.cardRatio, child: card)
        : card;
  }
}

// ------------------------------------------------------------------
// Transaction pop-ups: Income, Expense, Transfer and Reminder
// ------------------------------------------------------------------

/// Opens the pop-up for [type] (called by the + button in main.dart).
Future<void> showTransactionSheet(
  BuildContext context,
  TransactionColorType type,
) {
  final accent = AppTheme.accentOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: accent.background,
    barrierColor: AppConstants.popupBarrier,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _TransactionSheet(type: type),
  );
}

const double _sheetRadius = 4;
const double _sheetGap = 12;
const List<String> _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const List<String> _weekdayShort = [
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
];

String _two(int n) => n.toString().padLeft(2, '0');
String _fmtDate(DateTime d) => '${_two(d.month)}/${_two(d.day)}/${d.year}';

/// An account type with its accounts, for the grouped account picker.
class _AccountGroup {
  final int typeId;
  final String typeName;
  final String? typeIcon;
  final List<CategoryItem> items;
  const _AccountGroup(this.typeId, this.typeName, this.typeIcon, this.items);
}

/// Account picker: accounts grouped under their type. The types follow the
/// order of the Finance screen. [disabledId] is shown crossed out and can't
/// be tapped (used on a transfer for the account already chosen on the
/// other side).
Future<CategoryItem?> _pickGroupedAccount(
  BuildContext context, {
  required String title,
  required List<_AccountGroup> groups,
  CategoryItem? selected,
  int? disabledId,
}) {
  final base = Theme.of(context);
  final accent = AppTheme.accentOf(context);
  final fg = accent.foreground;

  return showModalBottomSheet<CategoryItem>(
    context: context,
    backgroundColor: accent.background,
    barrierColor: AppConstants.popupBarrier,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceLg,
        AppConstants.spaceSmMd,
        AppConstants.spaceLg,
        AppConstants.spaceLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: AppConstants.borderAlpha),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spaceLg),
          Text(
            title,
            style: base.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          const SizedBox(height: AppConstants.spaceMd),
          for (final group in groups) ...[
            // Type header
            Row(
              children: [
                Icon(
                  _iconForType(group.typeName, group.typeIcon),
                  size: 18,
                  color: fg.withValues(alpha: AppConstants.mutedAlpha),
                ),
                const SizedBox(width: AppConstants.spaceSm),
                Text(
                  group.typeName,
                  style: base.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: fg.withValues(alpha: AppConstants.mutedAlpha),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceSm),
            Wrap(
              spacing: AppConstants.spaceSm,
              runSpacing: AppConstants.spaceSm,
              children: [
                for (final item in group.items)
                  Opacity(
                    opacity: item.id == disabledId ? 0.4 : 1,
                    child: Material(
                      color: fg.withValues(
                        alpha: item.id == selected?.id
                            ? AppConstants.iconTileSelectedAlpha
                            : AppConstants.tintAlpha,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: item.id == disabledId
                            ? null
                            : () => Navigator.of(sheetContext).pop(item),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppConstants.spaceMd,
                            vertical: AppConstants.spaceSmMd + 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _iconForType(group.typeName, group.typeIcon),
                                size: 15,
                                color: fg,
                              ),
                              const SizedBox(width: AppConstants.spaceSm),
                              Text(
                                item.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: fg,
                                  decoration: item.id == disabledId
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: fg,
                                  decorationThickness: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceMd),
          ],
        ],
      ),
    ),
  );
}

/// Outlined field look shared by every field of the pop-ups.
InputDecoration _sheetDecoration(
  Color fg, {
  required String label,
  Widget? icon,
  Widget? suffix,
  FloatingLabelBehavior? floating,
  double vPad = 15,
  bool alignLabelWithHint = false,
  EdgeInsets? contentPadding,
}) {
  OutlineInputBorder border(double alpha, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(_sheetRadius),
        borderSide: BorderSide(
          color: fg.withValues(alpha: alpha),
          width: width,
        ),
      );
  return InputDecoration(
    isDense: true,
    labelText: label,
    alignLabelWithHint: alignLabelWithHint,
    labelStyle: TextStyle(color: fg.withValues(alpha: AppConstants.mutedAlpha)),
    floatingLabelStyle: TextStyle(color: fg),
    floatingLabelBehavior: floating,
    prefixIcon: icon,
    suffixIcon: suffix,
    contentPadding: contentPadding ??
        EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMd,
          vertical: vPad,
        ),
    border: border(AppConstants.borderAlpha, 1),
    enabledBorder: border(AppConstants.borderAlpha, 1),
    focusedBorder: border(1, 2),
  );
}

/// A tappable box that looks like the other fields.
Widget _sheetSelector({
  required Color fg,
  required String label,
  required Widget icon,
  required VoidCallback onTap,
  String? value,
  bool chevron = true,
  bool alwaysFloat = false,
  bool shrink = false,
  double vPad = 12,
}) {
  final style = TextStyle(color: fg, fontSize: 16);
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(_sheetRadius),
    child: InputDecorator(
      isEmpty: value == null,
      decoration: _sheetDecoration(
        fg,
        label: label,
        vPad: vPad,
        icon: icon,
        floating: alwaysFloat ? FloatingLabelBehavior.always : null,
        suffix: chevron ? Icon(Icons.expand_more, color: fg) : null,
      ),
      child: shrink
          ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value ?? '', maxLines: 1, style: style),
            )
          : Text(
              value ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
    ),
  );
}

class _TransactionSheet extends StatefulWidget {
  final TransactionColorType type;
  const _TransactionSheet({required this.type});

  @override
  State<_TransactionSheet> createState() => _TransactionSheetState();
}

class _TransactionSheetState extends State<_TransactionSheet> {
  static const _repeatOptions = <CategoryItem>[
    CategoryItem(0, 'No repeat'),
    CategoryItem(1, 'Daily'),
    CategoryItem(2, 'Weekly'),
    CategoryItem(3, 'Monthly'),
    CategoryItem(4, 'Yearly'),
  ];
  static const _repeatKeys = ['none', 'daily', 'weekly', 'monthly', 'yearly'];

  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  List<CategoryItem> _incomeCategories = const [];
  List<CategoryItem> _expenseCategories = const [];
  List<_AccountGroup> _accountGroups = const [];
  final Map<int, String> _accountTypes = {};

  CategoryItem? _category;
  CategoryItem? _account; // "From" on a transfer
  CategoryItem? _toAccount;
  CategoryItem? _repeat; // null = nothing chosen yet (not prefilled)
  DateTime? _date;
  bool _reminderIncome = false; // reminder: false = Expense, true = Income
  String? _imagePath;
  bool _didSave = false;
  bool _saving = false;
  String? _error;

  bool get _isReminder => widget.type == TransactionColorType.reminder;
  bool get _isTransfer => widget.type == TransactionColorType.transfer;
  bool get _incomeLike =>
      _isReminder ? _reminderIncome : widget.type == TransactionColorType.income;
  List<CategoryItem> get _categoryList =>
      _incomeLike ? _incomeCategories : _expenseCategories;

  @override
  void initState() {
    super.initState();
    if (!_isReminder) {
      final n = DateTime.now();
      _date = DateTime(n.year, n.month, n.day, n.hour, n.minute); // prefilled
    }
    _title.addListener(_refresh);
    _amount.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    _title.removeListener(_refresh);
    _amount.removeListener(_refresh);
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    // A picked image that was never saved is not kept.
    final path = _imagePath;
    if (!_didSave && path != null) _deleteFile(path);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _deleteFile(String path) {
    try {
      File(path).delete();
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final db = DatabaseHelper.instance;
      final income = await db.getCategoryItems(CategoryGroup.income);
      final expense = await db.getCategoryItems(CategoryGroup.expense);
      final accounts = await db.getAccountOptions();

      // Same type order as the Finance screen.
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_FinanceScreenState._orderPref) ??
          const <String>[];
      final rank = <int, int>{
        for (var i = 0; i < saved.length; i++)
          (int.tryParse(saved[i]) ?? -1): i,
      };
      final byType = <int, List<AccountOption>>{};
      for (final a in accounts) {
        byType.putIfAbsent(a.typeId, () => []).add(a);
      }
      const last = 1 << 30;
      final typeIds = byType.keys.toList()
        ..sort((a, b) {
          final ra = rank[a] ?? last;
          final rb = rank[b] ?? last;
          return ra != rb ? ra.compareTo(rb) : a.compareTo(b);
        });
      final groups = [
        for (final id in typeIds)
          _AccountGroup(
            id,
            byType[id]!.first.typeName,
            byType[id]!.first.typeIcon,
            [
              for (final a in byType[id]!)
                CategoryItem(a.id, a.name, a.typeIcon),
            ],
          ),
      ];

      if (!mounted) return;
      setState(() {
        _incomeCategories = income;
        _expenseCategories = expense;
        _accountGroups = groups;
        for (final a in accounts) {
          _accountTypes[a.id] = a.typeName;
        }
      });
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      // Saved order unreadable: the accounts just stay in the default order.
    }
  }

  // ---------- Rules ----------

  bool get _canSave {
    if (_saving) return false;
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0 || _date == null) return false;
    if (_isTransfer) return _account != null && _toAccount != null;
    if (_title.text.trim().isEmpty) return false;
    if (_isReminder) return true; // category, account and repeat are optional
    return _account != null && _category != null;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final db = DatabaseHelper.instance;
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    try {
      switch (widget.type) {
        case TransactionColorType.income:
        case TransactionColorType.expense:
          await db.addTransaction(
            type: widget.type.name,
            title: _title.text,
            amount: amount,
            date: _date!,
            accountId: _account!.id,
            categoryId: _category!.id,
            note: _note.text,
            imagePath: _imagePath,
          );
        case TransactionColorType.transfer:
          await db.addTransfer(
            title: _title.text.trim().isEmpty ? 'Transfer' : _title.text,
            amount: amount,
            date: _date!,
            fromAccountId: _account!.id,
            toAccountId: _toAccount!.id,
            note: _note.text,
            imagePath: _imagePath,
          );
        case TransactionColorType.reminder:
          await db.addReminder(
            type: _reminderIncome ? 'income' : 'expense',
            title: _title.text,
            amount: amount,
            dueDate: _date!,
            categoryId: _category?.id,
            accountId: _account?.id,
            repeat: _repeatKeys[_repeat?.id ?? 0],
            note: _note.text,
            imagePath: _imagePath,
          );
      }
      _didSave = true;
      if (mounted) Navigator.of(context).pop();
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      if (mounted) setState(() => _error = const UnknownFailure().message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- Pickers ----------

  IconData _accountIcon(CategoryItem item) =>
      _iconForType(_accountTypes[item.id] ?? '', item.icon);

  Future<void> _pickCategory() async {
    final picked = await _pickItem(
      context,
      title: 'Category',
      items: _categoryList,
      selected: _category,
      iconFor: (item) => _iconForCategory(item.icon),
    );
    if (picked != null) setState(() => _category = picked);
  }

  Future<void> _pickAccount({bool isTo = false}) async {
    // On a transfer the account chosen on the other side is crossed out.
    final other = isTo ? _account : _toAccount;
    final picked = await _pickGroupedAccount(
      context,
      title: isTo ? 'To' : (_isTransfer ? 'From' : 'Account'),
      groups: _accountGroups,
      selected: isTo ? _toAccount : _account,
      disabledId: _isTransfer ? other?.id : null,
    );
    if (picked == null) return;
    setState(() {
      if (isTo) {
        _toAccount = picked;
      } else {
        _account = picked;
      }
    });
  }

  Future<void> _pickRepeat() async {
    final picked = await _pickItem(
      context,
      title: 'Repeat',
      items: _repeatOptions,
      selected: _repeat,
      iconFor: (item) =>
          item.id == 0 ? Icons.remove_circle_outline : Icons.repeat,
    );
    if (picked != null) setState(() => _repeat = picked);
  }

  Future<void> _pickDate(Color color) async {
    final picked = await _showDateTimeDialog(
      context,
      initial: _date ?? DateTime.now(),
      color: color,
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _swapAccounts() {
    setState(() {
      final tmp = _account;
      _account = _toAccount;
      _toAccount = tmp;
    });
  }

  // ---------- Image ----------

  Future<String> _copyToAppFolder(String source) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'attachments'));
    if (!await folder.exists()) await folder.create(recursive: true);
    final target = p.join(
      folder.path,
      '${DateTime.now().microsecondsSinceEpoch}${p.extension(source)}',
    );
    await File(source).copy(target);
    return target;
  }

  /// Asks Camera or Gallery, then keeps a copy inside the app.
  Future<void> _chooseImage() async {
    final choice = await _pickItem(
      context,
      title: 'Add image',
      items: const [CategoryItem(0, 'Camera'), CategoryItem(1, 'Gallery')],
      iconFor: (item) => item.id == 0
          ? Icons.photo_camera_outlined
          : Icons.photo_library_outlined,
    );
    if (choice == null || !mounted) return;
    try {
      final file = await ImagePicker().pickImage(
        source: choice.id == 0 ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (file == null) return;
      final saved = await _copyToAppFolder(file.path);
      final old = _imagePath;
      if (old != null) _deleteFile(old);
      if (mounted) setState(() => _imagePath = saved);
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t get that image.');
    }
  }

  void _removeImage() {
    final old = _imagePath;
    if (old != null) _deleteFile(old);
    setState(() => _imagePath = null);
  }

  Widget _imageTile(Color fg, double size) {
    final path = _imagePath;
    return InkWell(
      onTap: _chooseImage,
      borderRadius: BorderRadius.circular(_sheetRadius),
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_sheetRadius),
          border: Border.all(
            color: fg.withValues(alpha: AppConstants.borderAlpha),
          ),
        ),
        child: path == null
            ? Center(
                child: Icon(
                  Icons.add_photo_alternate_outlined,
                  color: fg,
                  size: 30,
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Center(
                      child: Icon(Icons.broken_image_outlined, color: fg),
                    ),
                  ),
                  Positioned(
                    top: 3,
                    right: 3,
                    child: GestureDetector(
                      onTap: _removeImage,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ---------- Pieces ----------

  Widget _kindButton({
    required bool selected,
    required Color color,
    required Color fg,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: selected
            ? color.withValues(alpha: 0.18)
            : fg.withValues(alpha: AppConstants.tintAlpha),
        shape: StadiumBorder(
          side: selected ? BorderSide(color: color, width: 2) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: selected ? color : fg),
                const SizedBox(width: AppConstants.spaceSm),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? color : fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateField(Color fg, Color color, {required bool due}) {
    final d = _date;
    return _sheetSelector(
      fg: fg,
      label: due ? 'Due date' : 'Date',
      icon: Icon(Icons.calendar_today_outlined, color: color),
      // Date and the Hour:Min of the transaction.
      value: d == null ? null : '${_fmtDate(d)}  ${Utils.formatTime(d)}',
      chevron: due,
      alwaysFloat: !due,
      shrink: true,
      vPad: 15,
      onTap: () => _pickDate(color),
    );
  }

  Widget _accountField(Color fg, {String label = 'Account', bool isTo = false}) {
    final value = isTo ? _toAccount : _account;
    return _sheetSelector(
      fg: fg,
      label: label,
      value: value?.name,
      icon: Icon(
        value == null ? Icons.touch_app_outlined : _accountIcon(value),
        color: fg,
      ),
      onTap: () => _pickAccount(isTo: isTo),
    );
  }

  Widget _categoryField(Color fg) {
    final value = _category;
    return _sheetSelector(
      fg: fg,
      label: 'Category',
      value: value?.name,
      icon: Icon(
        value == null
            ? (_isReminder ? Icons.label_outline : Icons.touch_app_outlined)
            : _iconForCategory(value.icon),
        color: fg,
      ),
      onTap: _pickCategory,
    );
  }

  Widget _repeatField(Color fg) {
    final value = _repeat;
    return _sheetSelector(
      fg: fg,
      label: 'Repeat',
      value: value?.name,
      icon: Icon(
        (value == null || value.id == 0)
            ? Icons.remove_circle_outline
            : Icons.repeat,
        color: fg,
      ),
      onTap: _pickRepeat,
    );
  }

  Widget _swapButton(Color color, double scale) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: _swapAccounts,
      child: Container(
        width: 40 * scale,
        height: 40 * scale,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.18),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Icon(Icons.swap_horiz, size: 20 * scale, color: color),
      ),
    );
  }

  String get _heading {
    switch (widget.type) {
      case TransactionColorType.income:
        return 'New Income';
      case TransactionColorType.expense:
        return 'New Expense';
      case TransactionColorType.transfer:
        return 'Transfer Funds';
      case TransactionColorType.reminder:
        return 'New Reminder';
    }
  }

  String get _buttonLabel {
    switch (widget.type) {
      case TransactionColorType.transfer:
        return 'Transfer';
      case TransactionColorType.reminder:
        return 'Add Reminder';
      default:
        return 'Add Transaction';
    }
  }

  IconData get _buttonIcon {
    switch (widget.type) {
      case TransactionColorType.transfer:
        return Icons.swap_horiz;
      case TransactionColorType.reminder:
        return Icons.notifications_active;
      default:
        return Icons.add;
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    final settings = AppSettings.instance;

    final typeColor = settings.transactionColor(widget.type);
    // Icons inside the fields. A reminder follows its Expense / Income pick.
    final fieldColor = _isReminder
        ? (_reminderIncome ? settings.incomeColor : settings.expenseColor)
        : typeColor;

    final scale = _fontScale(context).clamp(0.9, 1.3).toDouble();
    final noteHeight = 96 * scale;
    final amountStyle = TextStyle(color: fg, fontSize: 16);

    final amountField = TextField(
      controller: _amount,
      style: amountStyle,
      cursorColor: fg,
      maxLines: 1,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      decoration: _sheetDecoration(
        fg,
        label: 'Amount (${AppConstants.currencySymbol})',
        icon: Icon(Icons.payments_outlined, color: fieldColor),
      ),
    );

    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          primary: fg,
          onPrimary: bg,
          onSurface: fg,
          onSurfaceVariant: muted,
        ),
        textSelectionTheme: TextSelectionThemeData(cursorColor: fg),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            AppConstants.spaceSmMd,
            20,
            AppConstants.spaceMd,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: AppConstants.borderAlpha),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceSmMd),

              // Header: icon box tinted with the transaction color
              Row(
                children: [
                  Container(
                    width: 40 * scale,
                    height: 40 * scale,
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: AppConstants.tintAlpha),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                    ),
                    child: Icon(widget.type.icon, color: typeColor),
                  ),
                  const SizedBox(width: AppConstants.spaceMd),
                  Text(
                    _heading,
                    style: base.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceMd),

              // Reminder: Expense | Income
              if (_isReminder) ...[
                Row(
                  children: [
                    _kindButton(
                      selected: !_reminderIncome,
                      color: settings.expenseColor,
                      fg: fg,
                      icon: TransactionColorType.expense.icon,
                      label: 'Expense',
                      onTap: () => setState(() {
                        _reminderIncome = false;
                        _category = null;
                      }),
                    ),
                    const SizedBox(width: _sheetGap),
                    _kindButton(
                      selected: _reminderIncome,
                      color: settings.incomeColor,
                      fg: fg,
                      icon: TransactionColorType.income.icon,
                      label: 'Income',
                      onTap: () => setState(() {
                        _reminderIncome = true;
                        _category = null;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: _sheetGap),
              ],

              // Title
              TextField(
                controller: _title,
                style: amountStyle,
                cursorColor: fg,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: _sheetDecoration(
                  fg,
                  label: 'Title',
                  icon: Icon(Icons.title, color: fg),
                ),
              ),
              const SizedBox(height: _sheetGap),

              // Transfer: From | swap | To
              if (_isTransfer) ...[
                Row(
                  children: [
                    Expanded(child: _accountField(fg, label: 'From')),
                    const SizedBox(width: AppConstants.spaceSm),
                    _swapButton(typeColor, scale),
                    const SizedBox(width: AppConstants.spaceSm),
                    Expanded(child: _accountField(fg, label: 'To', isTo: true)),
                  ],
                ),
                const SizedBox(height: _sheetGap),
              ],

              // Amount (+ Date, or full width on a reminder)
              if (_isReminder)
                amountField
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: amountField),
                    const SizedBox(width: _sheetGap),
                    Expanded(flex: 2, child: _dateField(fg, fieldColor, due: false)),
                  ],
                ),
              const SizedBox(height: _sheetGap),

              // Income / Expense: Category | Account
              if (!_isTransfer && !_isReminder) ...[
                Row(
                  children: [
                    Expanded(child: _categoryField(fg)),
                    const SizedBox(width: _sheetGap),
                    Expanded(child: _accountField(fg)),
                  ],
                ),
                const SizedBox(height: _sheetGap),
              ],

              // Reminder: Category | Due date, then Repeat | Account
              if (_isReminder) ...[
                Row(
                  children: [
                    Expanded(child: _categoryField(fg)),
                    const SizedBox(width: _sheetGap),
                    Expanded(child: _dateField(fg, fieldColor, due: true)),
                  ],
                ),
                const SizedBox(height: _sheetGap),
                Row(
                  children: [
                    Expanded(child: _repeatField(fg)),
                    const SizedBox(width: _sheetGap),
                    Expanded(child: _accountField(fg)),
                  ],
                ),
                const SizedBox(height: _sheetGap),
              ],

              // Image (square, left) + Note
              SizedBox(
                height: noteHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: noteHeight, child: _imageTile(fg, noteHeight)),
                    const SizedBox(width: _sheetGap),
                    Expanded(
                      // The note icon sits in the top left corner of the
                      // box, so it is drawn on top of the field instead
                      // of being the field's (centered) prefix icon.
                      child: Stack(
                        children: [
                          TextField(
                            controller: _note,
                            style: amountStyle,
                            cursorColor: fg,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: _sheetDecoration(
                              fg,
                              label: 'Note (optional)',
                              alignLabelWithHint: true,
                              contentPadding: const EdgeInsets.fromLTRB(
                                48,
                                15,
                                AppConstants.spaceMd,
                                15,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 12,
                            top: 12,
                            child: IgnorePointer(
                              child: Icon(
                                Icons.sticky_note_2_outlined,
                                color: fg,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: AppConstants.spaceSm),
                Text(
                  _error!,
                  style: base.textTheme.bodySmall?.copyWith(color: fg),
                ),
              ],
              const SizedBox(height: AppConstants.spaceMd),

              // Main button, colored with the transaction color
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _canSave ? _save : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: typeColor,
                    foregroundColor: AppTheme.onColor(typeColor),
                  ),
                  icon: Icon(_buttonIcon),
                  label: Text(_buttonLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Date + time pop-up
// ------------------------------------------------------------------

/// Calendar pop-up with a time row under it. [color] is the accent
/// (the transaction color). Returns the chosen date and time, or null.
Future<DateTime?> _showDateTimeDialog(
  BuildContext context, {
  required DateTime initial,
  required Color color,
}) {
  return showDialog<DateTime>(
    context: context,
    barrierColor: AppConstants.popupBarrier,
    builder: (_) => _DateTimeDialog(initial: initial, color: color),
  );
}

class _DateTimeDialog extends StatefulWidget {
  final DateTime initial;
  final Color color;
  const _DateTimeDialog({required this.initial, required this.color});

  @override
  State<_DateTimeDialog> createState() => _DateTimeDialogState();
}

class _DateTimeDialogState extends State<_DateTimeDialog> {
  static const double _wheelItem = 20; // height of one number on a wheel

  late DateTime _month; // first day of the month being shown
  late DateTime _selected; // date only
  late int _hour;
  late int _minute;
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _month = DateTime(i.year, i.month);
    _selected = DateTime(i.year, i.month, i.day);
    _hour = i.hour;
    _minute = i.minute;
    _hourController = FixedExtentScrollController(initialItem: _hour);
    _minuteController = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _shiftMonth(int by) =>
      setState(() => _month = DateTime(_month.year, _month.month + by));

  String get _weekdayText => _weekdayShort[_selected.weekday - 1];

  String get _dateText =>
      '${_monthNames[_selected.month - 1].substring(0, 3)} '
      '${_selected.day}, ${_selected.year}';

  Widget _pill(Color fg, {required Widget child, VoidCallback? onTap}) {
    final color = widget.color;
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }

  Widget _cell(int day, int daysInMonth, Color fg) {
    final color = widget.color;
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 44);
    final date = DateTime(_month.year, _month.month, day);
    final selected = date == _selected;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selected = date),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.2) : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 16,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? color : fg,
            ),
          ),
        ),
      ),
    );
  }

  /// One wheel (hours or minutes). It loops, snaps to a number, and the
  /// number in the middle is drawn bigger and in the accent color.
  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required int current,
    required Color fg,
    required ValueChanged<int> onChanged,
  }) {
    final color = widget.color;
    return SizedBox(
      width: 46,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: _wheelItem,
        diameterRatio: 6, // large = flat, like a rectangle
        perspective: 0.002,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (index) {
          HapticFeedback.selectionClick();
          onChanged(index % count);
        },
        childDelegate: ListWheelChildLoopingListDelegate(
          children: [
            for (var i = 0; i < count; i++)
              Center(
                child: Text(
                  _two(i),
                  style: TextStyle(
                    fontSize: i == current ? 20 : 16,
                    fontWeight:
                        i == current ? FontWeight.w700 : FontWeight.w400,
                    color: i == current
                        ? color
                        : fg.withValues(alpha: AppConstants.mutedAlpha),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Rectangular box with the Hour : Minute wheels, a band marks the
  /// number that will be used.
  Widget _timeWheel(Color fg) {
    final color = widget.color;
    return Container(
      height: _wheelItem * 3,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Container(
              height: _wheelItem,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          SizedBox(
            height: _wheelItem * 3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _wheel(
                  controller: _hourController,
                  count: 24,
                  current: _hour,
                  fg: fg,
                  onChanged: (v) => setState(() => _hour = v),
                ),
                Text(
                  ':',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                _wheel(
                  controller: _minuteController,
                  count: 60,
                  current: _minute,
                  fg: fg,
                  onChanged: (v) => setState(() => _minute = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;
    final color = widget.color;
    final theme = Theme.of(context);

    final lead = DateTime(_month.year, _month.month, 1).weekday - 1; // Mon = 0
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final rows = ((lead + days) / 7).ceil();

    return Dialog(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // < October 2026 >
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.chevron_left, color: fg),
                  onPressed: () => _shiftMonth(-1),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${_monthNames[_month.month - 1]} ${_month.year}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.chevron_right, color: fg),
                  onPressed: () => _shiftMonth(1),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceSm),
            // M T W T F S S
            Row(
              children: [
                for (final letter in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                  Expanded(
                    child: Center(
                      child: Text(
                        letter,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: fg.withValues(alpha: AppConstants.mutedAlpha),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceSm),
            // Days
            for (var r = 0; r < rows; r++)
              Row(
                children: [
                  for (var c = 0; c < 7; c++)
                    Expanded(child: _cell(r * 7 + c - lead + 1, days, fg)),
                ],
              ),
            const SizedBox(height: AppConstants.spaceMd),
            // Bottom of the calendar: chosen date (left) and the time
            // wheels (right).
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: _wheelItem * 3,
                    child: _pill(
                      fg,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _weekdayText,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: color.withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _dateText,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppConstants.spaceSm),
                _timeWheel(fg),
              ],
            ),
            const SizedBox(height: AppConstants.spaceMd),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                      foregroundColor: color,
                      side: BorderSide(color: color.withValues(alpha: 0.5)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: _sheetGap),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                      backgroundColor: color,
                      foregroundColor: AppTheme.onColor(color),
                    ),
                    onPressed: () => Navigator.of(context).pop(
                      DateTime(
                        _selected.year,
                        _selected.month,
                        _selected.day,
                        _hour,
                        _minute,
                      ),
                    ),
                    child: const Text(
                      'Apply',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
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