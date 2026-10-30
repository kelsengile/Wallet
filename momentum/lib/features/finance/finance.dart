import 'dart:math' as math;

import 'package:flutter/material.dart';

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
  final double balance;

  const _AccountCardData({
    required this.id,
    required this.name,
    required this.typeId,
    required this.typeName,
    required this.typeIcon,
    required this.category,
    required this.balance,
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
    (_fontScale(context) - AppConstants.bigTextScale) *
        AppConstants.textFollow;

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
      SELECT a.id, a.name, a.type_id,
             t.name AS type_name, t.icon AS type_icon,
             c.name AS category_name,
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
          balance: (row['balance'] as num).toInt() /
              AppConstants.centavosPerPeso,
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
                onPressed: () {}, // TODO: add account
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

/// Front: icon on the top right, then name, balance and category at the
/// bottom left. Sizes are measured from the sample (u = width / 612).
/// Text sizes use k = u * textFactor, so at the Big font size they match
/// the sample and change only slightly at other sizes.
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
          // Icon, top right
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
                _iconForType(account.typeName, account.typeIcon),
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
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    balanceText,
                    maxLines: 1,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 52 * k,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: fg,
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
                  'Notes',
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
              'Notes',
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