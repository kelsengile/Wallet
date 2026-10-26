import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/failures.dart';
import '../../core/themes.dart';
import '../../core/utils.dart';
import '../../database/helper.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  AccountsSummary _summary = AccountsSummary.empty;
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

  Future<void> _load() async {
    try {
      final summary = await DatabaseHelper.instance.getAccountsSummary();
      if (!mounted) return;
      setState(() {
        _summary = summary;
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
                tooltip: 'Add account',
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
      ],
    );
  }
}

/// Panel at the top of the Accounts page.
/// It draws behind the status bar and the (transparent) app bar.
class TotalBalanceCard extends StatelessWidget {
  final AccountsSummary summary;

  /// When true, the balance, income and expense are masked with asterisks.
  final bool hidden;

  const TotalBalanceCard({
    super.key,
    required this.summary,
    this.hidden = false,
  });

  /// ISO/IEC 7810 ID-1 card size: 85.60 mm x 53.98 mm.
  static const double cardRatio = 85.60 / 53.98;

  // ------------------------------------------------------------------
  // true  = card keeps the exact debit/credit card ratio (taller, text
  //         is centered inside, so there is more empty space).
  // false = card is only as tall as its content (less empty space).
  // ------------------------------------------------------------------
  static const bool useCardRatio = false;

  // ------------------------------------------------------------------
  // CHANGE THESE to set the space above and below the text.
  // textTopMargin    = space between the app bar and "Total Balance".
  // textBottomMargin = space between the balance row and the
  //                    bottom edge of the card.
  // Smaller number -> less space.
  // ------------------------------------------------------------------
  static const double textTopMargin = 60;
  static const double textBottomMargin = 35;
  static const double textSideMargin =
      AppConstants.spaceLg - AppConstants.spaceXs;

  // ------------------------------------------------------------------
  // CHANGE THIS to set the space between the labels.
  // Smaller number -> labels sit closer together.
  // ------------------------------------------------------------------
  /// Space between "Total Balance" and the balance row.
  static const double labelToBalanceGap = 10;

  // ------------------------------------------------------------------
  // CHANGE THIS to set how bold the big balance is.
  // w300 = light, w400 = normal, w500 = medium, w600 = semi-bold,
  // w700 = bold.
  // ------------------------------------------------------------------
  static const FontWeight balanceWeight = FontWeight.w700;

  // ------------------------------------------------------------------
  // CHANGE THIS to move the * up or down.
  // It is a fraction of the font size: bigger = lower, 0 = no shift.
  // ------------------------------------------------------------------
  static const double maskDrop = 0.25;

  static const double _bottomRadius = 28;
  static const Color _incomeColor = Color(0xFF4CAF50);
  static const Color _expenseColor = Color(0xFFF44A5A);

  /// Shown instead of amounts when hidden.
  static const String _mask = '****';

  static String _plain(double v) => Utils.formatCurrency(v, symbol: '');

  /// Draws the asterisks vertically centered on the text line.
  /// The `*` glyph normally sits high, so it is shifted down.
  /// [prefix] (for example the peso sign) stays on the normal baseline.
  static Widget _maskedText(
    BuildContext context,
    TextStyle? style, {
    String prefix = '',
  }) {
    final size = style?.fontSize ?? 14;
    final drop = MediaQuery.textScalerOf(context).scale(size) * maskDrop;
    return Text.rich(
      TextSpan(
        children: [
          if (prefix.isNotEmpty) TextSpan(text: prefix),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Transform.translate(
              offset: Offset(0, drop),
              child: Text(_mask, style: style),
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
    final muted = fg.withValues(alpha: 0.7);

    // Space taken by the status bar + app bar, so content starts below them.
    final topInset = MediaQuery.viewPaddingOf(context).top + kToolbarHeight;

    final balanceStyle = theme.textTheme.headlineLarge?.copyWith(
      fontSize: 38,
      fontWeight: balanceWeight,
      color: fg,
      height: 1.0, // removes the font's extra line spacing
    );
    final incomeStyle = theme.textTheme.labelSmall?.copyWith(
      color: _incomeColor,
      fontWeight: FontWeight.w600,
    );
    final expenseStyle = theme.textTheme.labelSmall?.copyWith(
      color: _expenseColor,
      fontWeight: FontWeight.w600,
    );

    final card = Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        textSideMargin,
        topInset + textTopMargin,
        textSideMargin,
        textBottomMargin,
      ),
      decoration: BoxDecoration(
        color: accent.background,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(_bottomRadius),
        ),
      ),
      child: Column(
        // Shrinks to the content when the ratio is off.
        mainAxisSize: useCardRatio ? MainAxisSize.max : MainAxisSize.min,
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
                '${summary.accountCount == 1 ? 'account' : 'accounts'}',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
          const SizedBox(height: labelToBalanceGap),
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
                      ? _maskedText(context, balanceStyle, prefix: '₱ ')
                      : Text(
                          Utils.formatCurrency(
                            summary.totalBalance,
                            symbol: '₱ ',
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
                    color: _incomeColor,
                  ),
                  const SizedBox(width: 2),
                  hidden
                      ? _maskedText(context, incomeStyle)
                      : Text(_plain(summary.income), style: incomeStyle),
                  const SizedBox(width: AppConstants.spaceSm),
                  Container(
                    width: 1,
                    height: 12,
                    color: fg.withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: AppConstants.spaceSm),
                  const Icon(
                    Icons.arrow_downward,
                    size: 11,
                    color: _expenseColor,
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

    return useCardRatio
        ? AspectRatio(aspectRatio: cardRatio, child: card)
        : card;
  }
}