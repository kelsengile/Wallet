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
    (56 + 8) *
        (1 + (_fontScale(context) - 1) * AppConstants.addButtonFollow) *
        AppConstants.addButtonScale +
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
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showTransactionHistory(context),
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
// Transaction history pop-up
// ------------------------------------------------------------------

/// Height of the bottom nav bar in main.dart. The history panel stops here.
const double _navBarHeight = 56;

const List<String> _weekdayLong = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  'Sunday',
];

String _fmtLong(DateTime d) =>
    '${_monthNames[d.month - 1].substring(0, 3)} ${d.day}, ${d.year}';

String _fmtTime12(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${_two(d.minute)} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

TransactionColorType _typeOf(String type) {
  switch (type) {
    case 'income':
      return TransactionColorType.income;
    case 'expense':
      return TransactionColorType.expense;
    default:
      return TransactionColorType.transfer;
  }
}

/// The last date filter the user used. Kept while the app is open.
_HistoryRange? _lastHistoryRange;

/// Rich, bright version of a color (stays saturated, not pale).
/// Grays are left as grays, so they never turn red.
Color _vivid(Color c) {
  final hsl = HSLColor.fromColor(c);
  if (hsl.saturation < 0.08) {
    return hsl.withLightness(hsl.lightness.clamp(0.6, 0.9).toDouble()).toColor();
  }
  return hsl
      .withSaturation(math.max(hsl.saturation, 0.8))
      .withLightness(hsl.lightness.clamp(0.58, 0.68).toDouble())
      .toColor();
}

/// Darker version of a color (same hue). Used for overdue reminders.
Color _darker(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness * 0.62).clamp(0.0, 1.0)).toColor();
}

/// True when the color is black or white (or close to it).
bool _isBW(Color c) {
  final l = HSLColor.fromColor(c).lightness;
  return l < 0.1 || l > 0.92;
}

enum _Period { day, week, month, year, all, custom }

/// The dates the history is showing. [end] is inclusive.
class _HistoryRange {
  final _Period period;
  final DateTime start;
  final DateTime end;
  const _HistoryRange(this.period, this.start, this.end);

  factory _HistoryRange.of(_Period p, DateTime a) {
    final d = DateTime(a.year, a.month, a.day);
    switch (p) {
      case _Period.day:
        return _HistoryRange(p, d, d);
      case _Period.week:
        final s = DateTime(d.year, d.month, d.day - (d.weekday - 1));
        return _HistoryRange(p, s, DateTime(s.year, s.month, s.day + 6));
      case _Period.month:
        return _HistoryRange(
          p,
          DateTime(d.year, d.month),
          DateTime(d.year, d.month + 1, 0),
        );
      case _Period.year:
        return _HistoryRange(p, DateTime(d.year), DateTime(d.year, 12, 31));
      case _Period.all:
      case _Period.custom:
        return _HistoryRange(p, d, d);
    }
  }

  bool get isAll => period == _Period.all;

  /// "All" and "Custom" have no arrows.
  bool get canStep => period != _Period.all && period != _Period.custom;

  DateTime? get from => isAll ? null : start;
  DateTime? get until =>
      isAll ? null : DateTime(end.year, end.month, end.day + 1);

  bool get groupByMonth =>
      period == _Period.year ||
      isAll ||
      (period == _Period.custom &&
          (start.month != end.month || start.year != end.year));

  bool get multiYear => isAll || start.year != end.year;

  _HistoryRange shifted(int by) {
    switch (period) {
      case _Period.day:
        return _HistoryRange.of(
          period,
          DateTime(start.year, start.month, start.day + by),
        );
      case _Period.week:
        return _HistoryRange.of(
          period,
          DateTime(start.year, start.month, start.day + 7 * by),
        );
      case _Period.month:
        return _HistoryRange.of(period, DateTime(start.year, start.month + by));
      case _Period.year:
        return _HistoryRange.of(period, DateTime(start.year + by));
      case _Period.all:
      case _Period.custom:
        return this;
    }
  }

  String get label {
    String mon(DateTime d) => _monthNames[d.month - 1].substring(0, 3);
    switch (period) {
      case _Period.day:
        return _fmtLong(start);
      case _Period.week:
        return start.year == end.year
            ? '${mon(start)} ${start.day} – ${mon(end)} ${end.day}, ${end.year}'
            : '${_fmtLong(start)} – ${_fmtLong(end)}';
      case _Period.month:
        return '${_monthNames[start.month - 1]} ${start.year}';
      case _Period.year:
        return '${start.year}';
      case _Period.all:
        return 'All Time';
      case _Period.custom:
        return '${_fmtLong(start)} – ${_fmtLong(end)}';
    }
  }
}

/// Opens the history. It drops down from the top and stops just above the
/// bottom nav bar. Tap the dim area below, tap the handle, or swipe the
/// handle up to close it.
Future<void> showTransactionHistory(BuildContext context) {
  final bottom = MediaQuery.viewPaddingOf(context).bottom + _navBarHeight;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close history',
    barrierColor: AppConstants.popupBarrier,
    transitionDuration: AppConstants.pageAnimationDuration,
    pageBuilder: (_, _, _) => Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: const _HistoryPanel(),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class _HistoryPanel extends StatefulWidget {
  const _HistoryPanel();

  @override
  State<_HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<_HistoryPanel> {
  final _db = DatabaseHelper.instance;
  late _HistoryRange _range;
  List<HistoryEntry> _entries = const [];
  List<ReminderItem> _reminders = const [];
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _range =
        _lastHistoryRange ?? _HistoryRange.of(_Period.month, DateTime.now());
    _load();
    _db.changes.addListener(_load);
  }

  @override
  void dispose() {
    _db.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final entries = await _db.getHistory(
        from: _range.from,
        until: _range.until,
      );
      final reminders = await _db.getReminders();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _reminders = reminders;
        _loaded = true;
        _error = null;
      });
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      if (mounted) setState(() => _error = const UnknownFailure().message);
    }
  }

    Widget _swipeBackground(double radius) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppConstants.spaceLg),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: const Icon(Icons.delete_outline, color: Colors.white),
    );
  }

  /// Same red pop-up as the Categories delete.
  Future<bool> _confirmDelete(String title, String message) async {
    const white = TextStyle(color: Colors.white);
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: AppConstants.popupBarrier,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.red,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.popupRadius),
        ),
        insetPadding: AppConstants.popupInsetPadding,
        titlePadding: AppConstants.popupTitlePaddingCompact,
        contentPadding: AppConstants.popupContentPaddingCompact,
        actionsPadding: AppConstants.popupActionsPaddingCompact,
        title: Text(
          title,
          style: white.copyWith(fontWeight: FontWeight.w600),
        ),
        content: Text(message, style: white),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.red,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Called when a transaction is swiped. True only if really deleted.
  Future<bool> _deleteEntry(HistoryEntry e) async {
    if (!await _confirmDelete(
      'Delete transaction?',
      'It will be moved to the trash.',
    )) {
      return false;
    }
    try {
      await _db.softDeleteTransaction(e.id);
      return true;
    } on Failure catch (f) {
      _snack(f.message);
    } catch (_) {
      _snack(const UnknownFailure().message);
    }
    return false;
  }

  Future<bool> _deleteReminderItem(ReminderItem r) async {
    if (!await _confirmDelete(
      'Delete reminder?',
      'This reminder will be deleted.',
    )) {
      return false;
    }
    try {
      await _db.deleteReminder(r.id);
      return true;
    } on Failure catch (f) {
      _snack(f.message);
    } catch (_) {
      _snack(const UnknownFailure().message);
    }
    return false;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  double get _income => _entries
      .where((e) => e.type == 'income')
      .fold(0.0, (sum, e) => sum + e.amount);
  double get _expense => _entries
      .where((e) => e.type == 'expense')
      .fold(0.0, (sum, e) => sum + e.amount);

  void _shift(int by) {
    setState(() => _range = _range.shifted(by));
    _lastHistoryRange = _range;
    _load();
  }

  Future<void> _pickRange() async {
    final picked = await showDialog<_HistoryRange>(
      context: context,
      barrierColor: AppConstants.popupBarrier,
      builder: (_) => _RangeDialog(initial: _range),
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
    _lastHistoryRange = picked;
    _load();
  }

  // ---------- Receipts ----------

  void _openEntry(HistoryEntry first) {
    var current = first;
    _showReceipt(
      context,
      _entryReceipt(first),
      reload: () async {
        final all = await _db.getHistory();
        for (final x in all) {
          if (x.id == first.id) {
            current = x;
            return _entryReceipt(x);
          }
        }
        return null;
      },
      onEdit: () =>
          showTransactionSheet(context, _typeOf(first.type), entry: current),
    );
  }

  void _openReminder(ReminderItem first) {
    var current = first;
    _showReceipt(
      context,
      _reminderReceipt(first),
      reload: () async {
        final all = await _db.getReminders();
        for (final x in all) {
          if (x.id == first.id) {
            current = x;
            return _reminderReceipt(x);
          }
        }
        return null; // done or deleted: the receipt closes
      },
      onEdit: () => showTransactionSheet(
        context,
        TransactionColorType.reminder,
        reminder: current,
      ),
      onDone: () => _markDone(current),
    );
  }

  Future<void> _markDone(ReminderItem r) async {
    var accountId = r.accountId;
    if (accountId == null) {
      // No account saved on the reminder: ask which one to use.
      final accounts = await _db.getAccountOptions();
      if (!mounted) return;
      final picked = await _pickItem(
        context,
        title: 'Account',
        items: [for (final a in accounts) CategoryItem(a.id, a.name, a.typeIcon)],
        iconFor: (item) => _iconForType('', item.icon),
      );
      if (picked == null) return;
      accountId = picked.id;
    }
    try {
      await _db.completeReminder(r, accountId: accountId);
    } on Failure catch (f) {
      _snack(f.message);
    } catch (_) {
      _snack(const UnknownFailure().message);
    }
  }

  _ReceiptData _entryReceipt(HistoryEntry e) {
    final s = AppSettings.instance;
    final isTransfer = e.type == 'transfer';
    final color = isTransfer
        ? s.transferColor
        : (e.type == 'income' ? s.incomeColor : s.expenseColor);
    final dateText = '${_fmtLong(e.date)}  •  ${_fmtTime12(e.date)}';
    return _ReceiptData(
      color: color,
      icon: isTransfer ? Icons.arrow_upward : _iconForCategory(e.categoryIcon),
      title: e.title,
      kind: _typeOf(e.type).label,
      rows: isTransfer
          ? [
              ('From', e.accountName, null),
              ('To', e.toAccountName ?? '', null),
              ('Date', dateText, null),
            ]
          : [
              ('Account', e.accountName, null),
              (
                'Category',
                e.categoryName ?? '',
                _iconForCategory(e.categoryIcon),
              ),
              ('Date', dateText, null),
            ],
      note: e.note?.trim(),
      imagePath: e.imagePath,
      totalLabel: 'TOTAL',
      totalText: Utils.formatCurrency(
        e.amount,
        symbol: AppConstants.currencySymbol,
      ),
    );
  }

  bool _isOverdue(DateTime due) {
    final n = DateTime.now();
    return DateTime(due.year, due.month, due.day)
        .isBefore(DateTime(n.year, n.month, n.day));
  }

  _ReceiptData _reminderReceipt(ReminderItem r) {
    final s = AppSettings.instance;
    const repeatLabels = {
      'daily': 'Daily',
      'weekly': 'Weekly',
      'monthly': 'Monthly',
      'yearly': 'Yearly',
    };
    return _ReceiptData(
      color: s.reminderColor,
      icon: _iconForCategory(r.categoryIcon),
      title: r.title,
      kind: 'Reminder',
      overdue: _isOverdue(r.dueDate),
      rows: [
        ('Type', _capitalizeWord(r.type), null),
        if (r.categoryName != null)
          ('Category', r.categoryName!, _iconForCategory(r.categoryIcon)),
        (
          'Due date',
          '${_fmtLong(r.dueDate)}, ${_weekdayShort[r.dueDate.weekday - 1]}',
          null,
        ),
        if (repeatLabels.containsKey(r.repeat))
          ('Repeat', repeatLabels[r.repeat]!, null),
        if (r.accountName != null) ('Account', r.accountName!, null),
      ],
      note: r.note?.trim(),
      imagePath: r.imagePath,
      totalLabel: 'AMOUNT',
      totalText: Utils.formatCurrency(
        r.amount,
        symbol: AppConstants.currencySymbol,
      ),
    );
  }

  String _capitalizeWord(String t) =>
      t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);

  // ---------- Pieces ----------

  Widget _stat(IconData icon, Color color, double value) {
    return Expanded(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              Utils.formatCurrency(value, symbol: AppConstants.currencySymbol),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayHeader(DateTime d, Color fg) {
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMd,
        AppConstants.spaceSmMd,
        AppConstants.spaceMd,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_monthNames[d.month - 1].substring(0, 3)} ${d.day}'
            ',  ${_weekdayLong[d.weekday - 1]}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: muted,
            ),
          ),
          const SizedBox(height: 2),
          Divider(
            height: 1,
            thickness: 1,
            color: fg.withValues(alpha: AppConstants.dividerAlpha),
          ),
        ],
      ),
    );
  }

  Widget _monthHeader(int year, int month, Color fg) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMd,
        AppConstants.spaceLg,
        AppConstants.spaceMd,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _range.multiYear
                ? '${_monthNames[month - 1]} $year'
                : _monthNames[month - 1],
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          const SizedBox(height: AppConstants.spaceXs),
          Divider(height: 1, thickness: 2, color: fg.withValues(alpha: 0.3)),
        ],
      ),
    );
  }

  Widget _entryRow(HistoryEntry e, Color fg) {
    final s = AppSettings.instance;
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final k = _fontScale(context).clamp(0.8, 1.3).toDouble();
    final isTransfer = e.type == 'transfer';
    final color = isTransfer
        ? s.transferColor
        : (e.type == 'income' ? s.incomeColor : s.expenseColor);
    final sign = isTransfer ? '±' : (e.type == 'income' ? '+' : '−');
    final sub = isTransfer
        ? '${e.accountName} → ${e.toAccountName ?? ''}'
        : e.accountName;

    // Same size and shape as the reminder card.
    final card = Material(
      color: accent.background,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openEntry(e),
        child: Padding(
          padding: EdgeInsets.all(AppConstants.spaceSmMd * k),
          child: Row(
            children: [
              Container(
                width: 42 * k,
                height: 42 * k,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isTransfer
                      ? Icons.swap_horiz
                      : _iconForCategory(e.categoryIcon),
                  size: 22 * k,
                  color: color,
                ),
              ),
              const SizedBox(width: AppConstants.spaceSmMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                        color: fg.withValues(alpha: AppConstants.mutedAlpha),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.spaceSm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$sign${Utils.formatCurrency(e.amount, symbol: AppConstants.currencySymbol)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fmtTime12(e.date),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 11,
                      color: fg.withValues(alpha: AppConstants.mutedAlpha),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceMd),
        child: Dismissible(
        key: ValueKey('tx-${e.id}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _deleteEntry(e),
        onDismissed: (_) => setState(() {
          _entries = [
            for (final x in _entries)
              if (x.id != e.id) x,
          ];
        }),
        background: _swipeBackground(16),
        child: card,
      ),
    );
  }

  Widget _reminderCard(ReminderItem r, Color fg) {
    final s = AppSettings.instance;
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final k = _fontScale(context).clamp(0.8, 1.3).toDouble();
    final overdue = _isOverdue(r.dueDate);
    final base = overdue ? _darker(s.reminderColor) : s.reminderColor;
    final amountColor = r.type == 'income' ? s.incomeColor : s.expenseColor;
    final due =
        '${overdue ? 'Due ' : ''}${_monthNames[r.dueDate.month - 1].substring(0, 3)} '
        '${r.dueDate.day}, ${_weekdayShort[r.dueDate.weekday - 1]}';

    final card = Material(
      // Solid color, so the red swipe background doesn't show through.
      color: Color.alphaBlend(base.withValues(alpha: 0.14), accent.background),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openReminder(r),
        child: Padding(
          padding: EdgeInsets.all(AppConstants.spaceSmMd * k),
          child: Row(
            children: [
              Container(
                width: 42 * k,
                height: 42 * k,
                decoration: BoxDecoration(
                  color: base.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  overdue
                      ? Icons.warning_amber_rounded
                      : Icons.notifications_active,
                  size: 22 * k,
                  color: base,
                ),
              ),
              const SizedBox(width: AppConstants.spaceSmMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          _iconForCategory(r.categoryIcon),
                          size: 13 * k,
                          color: amountColor,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            r.categoryName ?? _capitalizeWord(r.type),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 12,
                              color: fg.withValues(
                                alpha: AppConstants.mutedAlpha,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.spaceSm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${r.type == 'income' ? '+' : '−'}'
                    '${Utils.formatCurrency(r.amount, symbol: AppConstants.currencySymbol)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: amountColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    due,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 11,
                      color: overdue
                          ? base
                          : fg.withValues(alpha: AppConstants.mutedAlpha),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMd,
        0,
        AppConstants.spaceMd,
        AppConstants.spaceSm,
      ),
      child: Dismissible(
        key: ValueKey('rem-${r.id}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _deleteReminderItem(r),
        onDismissed: (_) => setState(() {
          _reminders = [
            for (final x in _reminders)
              if (x.id != r.id) x,
          ];
        }),
        background: _swipeBackground(16),
        child: card,
      ),
    );
  }

  Widget _remindersSection(Color fg) {
    final color = AppSettings.instance.reminderColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceMd,
            AppConstants.spaceMd,
            AppConstants.spaceMd,
            AppConstants.spaceSm,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.notifications_outlined, size: 18, color: color),
              ),
              const SizedBox(width: AppConstants.spaceSm),
              Text(
                'REMINDERS',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: color,
                ),
              ),
              const SizedBox(width: AppConstants.spaceSm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_reminders.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final r in _reminders) _reminderCard(r, fg),
      ],
    );
  }

  List<Widget> _listChildren(Color fg) {
    final out = <Widget>[];
    if (_reminders.isNotEmpty) out.add(_remindersSection(fg));
    if (!_loaded) {
      out.add(const Padding(
        padding: EdgeInsets.all(AppConstants.spaceXl),
        child: Center(child: CircularProgressIndicator()),
      ));
      return out;
    }
    if (_entries.isEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.all(AppConstants.spaceXl),
        child: Center(
          child: Text(
            'No transactions',
            style: TextStyle(
              color: fg.withValues(alpha: AppConstants.mutedAlpha),
            ),
          ),
        ),
      ));
      return out;
    }
    int? lastMonth;
    String? lastDay;
    for (final e in _entries) {
      final d = e.date;
      if (_range.groupByMonth) {
        final mk = d.year * 100 + d.month;
        if (mk != lastMonth) {
          out.add(_monthHeader(d.year, d.month, fg));
          lastMonth = mk;
          lastDay = null;
        }
      }
      final dk = '${d.year}-${d.month}-${d.day}';
      if (dk != lastDay) {
        out.add(_dayHeader(d, fg));
        lastDay = dk;
      }
      out.add(_entryRow(e, fg));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final s = AppSettings.instance;
    final left = _income - _expense;

    return Material(
      color: accent.background,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(height: MediaQuery.viewPaddingOf(context).top),
          // Title + date filter button
                    // Title + date filter button
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spaceMd + AppConstants.spaceXs,
              AppConstants.spaceMd,
              AppConstants.spaceSm,
              0,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: AppConstants.tintAlpha),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Icon(Icons.receipt_long_outlined, color: fg),
                ),
                const SizedBox(width: AppConstants.spaceMd),
                Expanded(
                  child: Text(
                    'Transaction History',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.filter_list, color: fg),
                  tooltip: 'Filter by date',
                  onPressed: _pickRange,
                ),
              ],
            ),
          ),
          // < date >
                    // < date >
          Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: _range.canStep
                    ? IconButton(
                        icon: Icon(Icons.chevron_left, color: fg),
                        onPressed: () => _shift(-1),
                      )
                    : null,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _range.label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                height: 48,
                child: _range.canStep
                    ? IconButton(
                        icon: Icon(Icons.chevron_right, color: fg),
                        onPressed: () => _shift(1),
                      )
                    : null,
              ),
            ],
          ),
          // Income | Expense | What's left
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spaceMd,
              vertical: AppConstants.spaceSm,
            ),
            child: Row(
              children: [
                _stat(Icons.arrow_upward, s.incomeColor, _income),
                _stat(Icons.arrow_downward, s.expenseColor, _expense),
                _stat(
                  Icons.account_balance_wallet_outlined,
                  left >= 0 ? s.incomeColor : s.expenseColor,
                  left,
                ),
              ],
            ),
          ),
          // Line the list scrolls under
          Divider(height: 1, thickness: 2, color: fg.withValues(alpha: 0.3)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(AppConstants.spaceSm),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppConstants.spaceMd),
              children: _listChildren(fg),
            ),
          ),
          // Handle: tap or swipe up to close
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < 0) Navigator.of(context).pop();
            },
            child: SizedBox(
              height: 28,
              width: double.infinity,
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: AppConstants.borderAlpha),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------
// Receipt pop-up
// ------------------------------------------------------------------

class _ReceiptData {
  final Color color;
  final IconData icon;
  final String title;
  final String kind; // Income / Expense / Transfer / Reminder
  final bool overdue;
  final List<(String, String, IconData?)> rows; // label, value, icon
  final String? note;
  final String? imagePath;
  final String totalLabel;
  final String totalText;

  const _ReceiptData({
    required this.color,
    required this.icon,
    required this.title,
    required this.kind,
    required this.rows,
    required this.totalLabel,
    required this.totalText,
    this.overdue = false,
    this.note,
    this.imagePath,
  });
}

/// [onDone] is only given for reminders (shows the Mark as Done button).
/// [reload] returns fresh data after the database changes (null = close).
Future<void> _showReceipt(
  BuildContext context,
  _ReceiptData data, {
  required Future<_ReceiptData?> Function() reload,
  required VoidCallback onEdit,
  VoidCallback? onDone,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: AppConstants.popupBarrier,
    builder: (ctx) => _ReceiptDialog(
      data: data,
      reload: reload,
      onEdit: onEdit, // the receipt stays open behind the edit sheet
      onDone: onDone == null
          ? null
          : () {
              Navigator.of(ctx).pop();
              onDone();
            },
    ),
  );
}

class _ReceiptDialog extends StatefulWidget {
  final _ReceiptData data;
  final Future<_ReceiptData?> Function() reload;
  final VoidCallback onEdit;
  final VoidCallback? onDone;

  const _ReceiptDialog({
    required this.data,
    required this.reload,
    required this.onEdit,
    this.onDone,
  });

  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<_ReceiptDialog> {
  /// Receipt size settings: edit these to resize it.
  static const double _radius = 20; // corner roundness
  static const double _imageMaxHeight = 200; // max picture height
  static const double _sideInset = 32; // space left/right of the popup
  static const double _bodyPad = 20; // side padding of the receipt body
  /// 35% of the body padding: the picture almost touches the edges.
  static const double _imageSidePad = _bodyPad * 0.20;

  late _ReceiptData _data = widget.data;

  @override
  void initState() {
    super.initState();
    DatabaseHelper.instance.changes.addListener(_refresh);
  }

  @override
  void dispose() {
    DatabaseHelper.instance.changes.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final fresh = await widget.reload();
      if (!mounted) return;
      if (fresh == null) {
        Navigator.of(context).pop();
      } else {
        setState(() => _data = fresh);
      }
    } catch (_) {
      // Keep showing what we have.
    }
  }

  Widget _row(String label, String value, IconData? icon, Color fg, Color tint) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: fg.withValues(alpha: AppConstants.mutedAlpha),
            ),
          ),
          const SizedBox(width: AppConstants.spaceMd),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: tint),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 14, color: fg),
                  ),
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
    final data = _data;
    final accentC = data.color;
    final onDone = widget.onDone;
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final body = accent.background;
    final isBW = _isBW(accentC);
    // Strong, saturated colors (not mixed with white).
    final header = Color.alphaBlend(accentC.withValues(alpha: 0.4), body);
    final bright = isBW ? accentC : _vivid(accentC);
    final dash = fg.withValues(alpha: 0.35);
    final note = data.note;
    final image = data.imagePath;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: _sideInset, vertical: 24),
      child: Stack(
        clipBehavior: Clip.none, // lets the edit button sit on the edge
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: Material(
              color: body,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ----- Colored top (taller) -----
                    Container(
                      width: double.infinity,
                      color: header,
                      padding: const EdgeInsets.fromLTRB(20, 40, 20, 26),
                      child: Column(
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: data.color.withValues(alpha: 0.3),
                              border: Border.all(color: bright, width: 3),
                            ),
                            child: Icon(data.icon, size: 32, color: bright),
                          ),
                          const SizedBox(height: AppConstants.spaceMd),
                          Text(
                            data.title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: fg,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            data.kind,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: bright,
                            ),
                          ),
                          if (data.overdue) ...[
                            const SizedBox(height: AppConstants.spaceSmMd),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: _darker(data.color)
                                    .withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 16,
                                    color: bright,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Overdue',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: bright,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Scalloped edge
                    LayoutBuilder(
                      builder: (context, c) {
                        final n = (c.maxWidth / 18).round();
                        final r = c.maxWidth / n / 2;
                        return SizedBox(
                          width: c.maxWidth,
                          height: r,
                          child: CustomPaint(
                            painter: _ScallopPainter(header, body, n),
                          ),
                        );
                      },
                    ),
                    // ----- Picture: nearly the full width -----
                    if (image != null && image.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          _imageSidePad,
                          AppConstants.spaceSm,
                          _imageSidePad,
                          0,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: _imageMaxHeight,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(image),
                              width: double.infinity,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => Padding(
                                padding: const EdgeInsets.all(16),
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: fg,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    // ----- Receipt body (more spaced out) -----
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        _bodyPad,
                        AppConstants.spaceMd,
                        _bodyPad,
                        28,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Dashed(color: dash),
                          const SizedBox(height: AppConstants.spaceSmMd),
                          for (final r in data.rows)
                            _row(r.$1, r.$2, r.$3, fg, bright),
                          if (note != null && note.isNotEmpty) ...[
                            const SizedBox(height: AppConstants.spaceSmMd),
                            _Dashed(color: dash),
                            const SizedBox(height: AppConstants.spaceSmMd),
                            _row('Note', note, null, fg, bright),
                          ],
                          const SizedBox(height: AppConstants.spaceSmMd),
                          _Dashed(color: dash),
                          const SizedBox(height: AppConstants.spaceMd),
                          Row(
                            children: [
                              Text(
                                data.totalLabel,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                  color: fg,
                                ),
                              ),
                              const SizedBox(width: AppConstants.spaceMd),
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    data.totalText,
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      color: bright,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (onDone != null) ...[
                            const SizedBox(height: AppConstants.spaceMd),
                            Center(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF1B6B3A),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(0, 46),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 22,
                                  ),
                                ),
                                onPressed: onDone,
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text(
                                  'Mark as Done',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
                    // Edit button: receipt color, with white pen and shadow for black/white
          Positioned(
            top: -10,
            right: -10,
            child: Material(
              color: accentC,
              shape: const CircleBorder(),
              elevation: 6,
              shadowColor: isBW ? Colors.white : accentC,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onEdit,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.edit,
                    size: 20,
                    color: isBW ? Colors.white : AppTheme.onColor(accentC),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dashed separator line (- - - - -).
class _Dashed extends StatelessWidget {
  final Color color;
  const _Dashed({required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final n = (c.maxWidth / 9).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < n; i++)
              Container(width: 5, height: 1.5, color: color),
          ],
        );
      },
    );
  }
}

/// The round bumps between the colored top and the receipt body.
class _ScallopPainter extends CustomPainter {
  final Color top;
  final Color body;
  final int count;
  const _ScallopPainter(this.top, this.body, this.count);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = top);
    final r = size.width / count / 2;
    final paint = Paint()..color = body;
    for (var i = 0; i < count; i++) {
      canvas.drawCircle(Offset(r * (2 * i + 1), size.height), r, paint);
    }
  }

  @override
  bool shouldRepaint(_ScallopPainter old) =>
      old.top != top || old.body != body || old.count != count;
}

// ------------------------------------------------------------------
// Date filter pop-up (Day / Week / Month / Year / All / Custom)
// ------------------------------------------------------------------

class _RangeDialog extends StatefulWidget {
  final _HistoryRange initial;
  const _RangeDialog({required this.initial});

  @override
  State<_RangeDialog> createState() => _RangeDialogState();
}

class _RangeDialogState extends State<_RangeDialog> {
  /// Fixed height of the middle part, so the pop-up never changes shape.
  static const double _bodyHeight = 262;

  static const _tabs = <(_Period, String)>[
    (_Period.day, 'Day'),
    (_Period.week, 'Week'),
    (_Period.month, 'Month'),
    (_Period.year, 'Year'),
    (_Period.all, 'All'),
    (_Period.custom, 'Custom'),
  ];

  late _Period _period;
  late DateTime _view; // month shown / year shown / decade shown
  late DateTime _picked; // date only
  DateTime? _cStart;
  DateTime? _cEnd;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    final n = DateTime.now();
    _period = i.period;
    _picked = i.isAll ? DateTime(n.year, n.month, n.day) : i.start;
    if (i.period == _Period.custom) {
      _cStart = i.start;
      _cEnd = i.end;
    }
    _view = DateTime(_picked.year, _picked.month);
  }

  _HistoryRange get _result {
    switch (_period) {
      case _Period.all:
        return _HistoryRange.of(_Period.all, _picked);
      case _Period.custom:
        final s = _cStart ?? _picked;
        return _HistoryRange(_Period.custom, s, _cEnd ?? s);
      default:
        return _HistoryRange.of(_period, _picked);
    }
  }

  String get _pillText {
    final r = _result;
    if (r.period == _Period.day) {
      return '${_weekdayShort[r.start.weekday - 1]}, ${r.label}';
    }
    return r.label;
  }

  int get _decadeStart => ((_view.year - 1) ~/ 10) * 10 + 1;

  String get _viewTitle {
    switch (_period) {
      case _Period.month:
        return '${_view.year}';
      case _Period.year:
        return '$_decadeStart – ${_decadeStart + 9}';
      default:
        return '${_monthNames[_view.month - 1]} ${_view.year}';
    }
  }

  void _step(int by) {
    setState(() {
      switch (_period) {
        case _Period.month:
          _view = DateTime(_view.year + by);
        case _Period.year:
          _view = DateTime(_view.year + 10 * by);
        default:
          _view = DateTime(_view.year, _view.month + by);
      }
    });
  }

  void _tapDay(DateTime date) {
    setState(() {
      if (_period == _Period.custom) {
        final s = _cStart;
        if (s == null || _cEnd != null) {
          _cStart = date;
          _cEnd = null;
        } else if (date.isBefore(s)) {
          _cEnd = s;
          _cStart = date;
        } else {
          _cEnd = date;
        }
      } else {
        _picked = date;
      }
    });
  }

  Widget _tabBar(Color fg) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: AppConstants.tintAlpha),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final t in _tabs)
            Expanded(
              child: Material(
                color: t.$1 == _period
                    ? fg.withValues(alpha: 0.3)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => setState(() => _period = t.$1),
                  child: SizedBox(
                    height: 40,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          t.$2,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: t.$1 == _period
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: t.$1 == _period
                                ? fg
                                : fg.withValues(
                                    alpha: AppConstants.mutedAlpha,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _navRow(Color fg) {
    if (_period == _Period.all) return const SizedBox(height: 40);
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.chevron_left, color: fg),
          onPressed: () => _step(-1),
        ),
        Expanded(
          child: Center(
            child: Text(
              _viewTitle,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.chevron_right, color: fg),
          onPressed: () => _step(1),
        ),
      ],
    );
  }
  Widget _dayCell(int day, int days, Color fg) {
    if (day < 1 || day > days) return const SizedBox(height: 38);
    final date = DateTime(_view.year, _view.month, day);
    var inRange = false;
    var strong = false;
    switch (_period) {
      case _Period.day:
        strong = date == _picked;
      case _Period.week:
        final w = _HistoryRange.of(_Period.week, _picked);
        inRange = !date.isBefore(w.start) && !date.isAfter(w.end);
        strong = date == _picked;
      case _Period.custom:
        final s = _cStart;
        if (s != null) {
          final e = _cEnd ?? s;
          inRange = !date.isBefore(s) && !date.isAfter(e);
          strong = date == s || date == e;
        }
      default:
        break;
    }
    final highlighted = inRange || strong;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _tapDay(date),
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: strong
                ? fg.withValues(alpha: 0.38)
                : (inRange ? fg.withValues(alpha: 0.16) : null),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 16,
              fontWeight: highlighted ? FontWeight.w700 : FontWeight.w400,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }

  Widget _calendar(Color fg) {
    final lead = DateTime(_view.year, _view.month, 1).weekday - 1; // Mon = 0
    final days = DateTime(_view.year, _view.month + 1, 0).day;
    return Column(
      children: [
        SizedBox(
          height: 28,
          child: Row(
            children: [
              for (final l in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Center(
                    child: Text(
                      l,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: fg.withValues(alpha: AppConstants.mutedAlpha),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Always 6 rows, so every month has the same height.
        for (var r = 0; r < 6; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(child: _dayCell(r * 7 + c - lead + 1, days, fg)),
            ],
          ),
      ],
    );
  }

  Widget _gridCell(String text, bool selected, Color fg, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? fg.withValues(alpha: 0.3) : null,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 17,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }

  Widget _grid(int count, Widget Function(int i) cell) {
    return Center(
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisExtent: 54,
        ),
        itemCount: count,
        itemBuilder: (_, i) => cell(i),
      ),
    );
  }

  Widget _body(Color fg) {
    switch (_period) {
      case _Period.month:
        return _grid(
          12,
          (i) => _gridCell(
            _monthNames[i].substring(0, 3),
            _picked.year == _view.year && _picked.month == i + 1,
            fg,
            () => setState(() => _picked = DateTime(_view.year, i + 1)),
          ),
        );
      case _Period.year:
        return _grid(
          10,
          (i) => _gridCell(
            '${_decadeStart + i}',
            _picked.year == _decadeStart + i,
            fg,
            () => setState(() => _picked = DateTime(_decadeStart + i)),
          ),
        );
      case _Period.all:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.all_inclusive,
                size: 64,
                color: fg.withValues(alpha: AppConstants.mutedAlpha),
              ),
              const SizedBox(height: AppConstants.spaceMd),
              Text(
                'Showing all transactions',
                style: TextStyle(
                  fontSize: 18,
                  color: fg.withValues(alpha: AppConstants.mutedAlpha),
                ),
              ),
            ],
          ),
        );
      default:
        return _calendar(fg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;

    return Dialog(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tabBar(fg),
            const SizedBox(height: AppConstants.spaceSm),
            _navRow(fg),
            SizedBox(height: _bodyHeight, child: _body(fg)),
            const SizedBox(height: AppConstants.spaceSm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              ),
              child: Text(
                _pillText,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spaceMd),
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
                      backgroundColor: fg,
                      foregroundColor: bg,
                    ),
                    onPressed: () => Navigator.of(context).pop(_result),
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

// ------------------------------------------------------------------
// Transaction pop-ups: Income, Expense, Transfer and Reminder
// ------------------------------------------------------------------

/// Opens the pop-up for [type] (called by the + button in main.dart).
/// Pass [entry] (or [reminder]) to edit an existing one.
Future<void> showTransactionSheet(
  BuildContext context,
  TransactionColorType type, {
  HistoryEntry? entry,
  ReminderItem? reminder,
}) {
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
    builder: (_) =>
        _TransactionSheet(type: type, entry: entry, reminder: reminder),
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
  final HistoryEntry? entry;
  final ReminderItem? reminder;
  const _TransactionSheet({required this.type, this.entry, this.reminder});

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

  String? _originalImage; // picture the edited item already had
  bool get _editing => widget.entry != null || widget.reminder != null;

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
    // Edit mode: start with the saved values.
    final e = widget.entry;
    final r = widget.reminder;
    if (e != null) {
      _title.text = e.title;
      _amount.text = e.amount.toStringAsFixed(2);
      _note.text = e.note ?? '';
      _date = e.date;
      _imagePath = _originalImage = e.imagePath;
    }
    if (r != null) {
      _title.text = r.title;
      _amount.text = r.amount.toStringAsFixed(2);
      _note.text = r.note ?? '';
      _date = r.dueDate;
      _reminderIncome = r.type == 'income';
      final i = _repeatKeys.indexOf(r.repeat);
      _repeat = _repeatOptions[i < 0 ? 0 : i];
      _imagePath = _originalImage = r.imagePath;
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
    if (!_didSave && path != null && path != _originalImage) _deleteFile(path);
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
      CategoryItem? find(List<CategoryItem> list, int? id) {
        for (final i in list) {
          if (i.id == id) return i;
        }
        return null;
      }

      CategoryItem? findAccount(int? id) {
        for (final g in groups) {
          final f = find(g.items, id);
          if (f != null) return f;
        }
        return null;
      }

      if (!mounted) return;
      setState(() {
        _incomeCategories = income;
        _expenseCategories = expense;
        _accountGroups = groups;
        for (final a in accounts) {
          _accountTypes[a.id] = a.typeName;
        }
        // Edit mode: select the saved category / accounts.
        final e = widget.entry;
        final r = widget.reminder;
        if (e != null) {
          _account = findAccount(e.accountId);
          _toAccount = findAccount(e.toAccountId);
          if (e.type == 'income') _category = find(income, e.categoryId);
          if (e.type == 'expense') _category = find(expense, e.categoryId);
        }
        if (r != null) {
          _account = findAccount(r.accountId);
          _category = find(r.type == 'income' ? income : expense, r.categoryId);
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
      if (_editing) {
        await _saveEdit(db, amount);
      } else {
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

  Future<void> _saveEdit(DatabaseHelper db, double amount) async {
    final e = widget.entry;
    if (e != null) {
      await db.updateTransaction(
        id: e.id,
        type: e.type,
        title: _isTransfer && _title.text.trim().isEmpty
            ? 'Transfer'
            : _title.text,
        amount: amount,
        date: _date!,
        accountId: _account!.id,
        toAccountId: _isTransfer ? _toAccount!.id : null,
        categoryId: _isTransfer ? null : _category!.id,
        note: _note.text,
        imagePath: _imagePath,
      );
    } else {
      await db.updateReminder(
        id: widget.reminder!.id,
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
      if (old != null && old != _originalImage) _deleteFile(old);
      if (mounted) setState(() => _imagePath = saved);
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t get that image.');
    }
  }

  void _removeImage() {
    final old = _imagePath;
    if (old != null && old != _originalImage) _deleteFile(old);
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
    final edit = _editing;
    switch (widget.type) {
      case TransactionColorType.income:
        return edit ? 'Edit Income' : 'New Income';
      case TransactionColorType.expense:
        return edit ? 'Edit Expense' : 'New Expense';
      case TransactionColorType.transfer:
        return edit ? 'Edit Transfer' : 'Transfer Funds';
      case TransactionColorType.reminder:
        return edit ? 'Edit Reminder' : 'New Reminder';
    }
  }

  String get _buttonLabel {
    if (_editing) return 'Save Changes';
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
    if (_editing) return Icons.save;
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
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 38);
    final date = DateTime(_month.year, _month.month, day);
    final selected = date == _selected;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selected = date),
        child: Container(
          height: 34,
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
    const rows = 6; 

    return Dialog(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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