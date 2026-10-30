import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/failures.dart';
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

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  AccountsSummary _summary = AccountsSummary.empty;
  List<_AccountCardData> _accounts = const [];
  String? _error;

  // true = amounts are hidden (eye closed), false = amounts are shown.
  bool _hideAmounts = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Reload whenever the database reports a change.
    DatabaseHelper.instance.changes.addListener(_load);
  }

  @override
  void dispose() {
    DatabaseHelper.instance.changes.removeListener(_load);
    super.dispose();
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

  /// Accounts grouped by account type, in the order of the types.
  List<List<_AccountCardData>> get _groups {
    final groups = <int, List<_AccountCardData>>{};
    for (final account in _accounts) {
      groups.putIfAbsent(account.typeId, () => []).add(account);
    }
    return groups.values.toList();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // padding: zero so the card can start at the very top of the screen,
    // behind the status bar and the transparent app bar.
    return ListView(
      padding: EdgeInsets.zero,
      children: [
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
              IconButton(
                icon: const Icon(Icons.view_headline),
                tooltip: 'Change view',
                onPressed: () {}, // TODO: list / grid view
              ),
            ],
          ),
        ),
        // One section per account type.
        for (final group in _groups)
          _AccountTypeSection(accounts: group, hidden: _hideAmounts),
        const SizedBox(height: AppConstants.spaceLg),
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
  static const double _balanceMaxFont = 16; // NEW
  static const double _balanceMinFont = 8; // NEW

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

  /// NEW: the biggest font size (down to the minimum) at which the typed
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
              LayoutBuilder( // CHANGED
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

/// A header (type icon + type name) with a sideways list of its cards.
class _AccountTypeSection extends StatelessWidget {
  final List<_AccountCardData> accounts;
  final bool hidden;

  const _AccountTypeSection({required this.accounts, required this.hidden});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final first = accounts.first;

    // The card follows the font size, but only a little.
    final cardWidth = _cardWidthFor(context);
    final cardHeight = _cardHeightFor(cardWidth);

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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.background,
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Icon(
                  _iconForType(first.typeName, first.typeIcon),
                  size: 20,
                  color: accent.foreground,
                ),
              ),
              const SizedBox(width: AppConstants.spaceSmMd),
              Text(
                first.typeName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
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
                  width: double.infinity, // CHANGED: gives FittedBox a width
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);

    // Space taken by the status bar + app bar, so content starts below them.
    final topInset = MediaQuery.viewPaddingOf(context).top + kToolbarHeight;

    final balanceStyle = theme.textTheme.headlineLarge?.copyWith(
      fontSize: AppConstants.balanceFontSize,
      fontWeight: AppConstants.balanceWeight,
      color: fg,
      height: 1.0, // removes the font's extra line spacing
    );
    final incomeStyle = theme.textTheme.labelSmall?.copyWith(
      color: AppConstants.incomeColor,
      fontWeight: FontWeight.w600,
    );
    final expenseStyle = theme.textTheme.labelSmall?.copyWith(
      color: AppConstants.expenseColor,
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
              // Analytics: green = income | red = expense (right side)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.arrow_upward,
                    size: 11,
                    color: AppConstants.incomeColor,
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
                  const Icon(
                    Icons.arrow_downward,
                    size: 11,
                    color: AppConstants.expenseColor,
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