import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/themes.dart';
import '../../core/utils.dart';

/// Numbers shown on the total balance card.
class AccountsSummary {
  final double totalBalance;
  final int accountCount;
  final double income;
  final double expense;

  const AccountsSummary({
    required this.totalBalance,
    required this.accountCount,
    required this.income,
    required this.expense,
  });
}

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  // TODO: replace with real data from the database once the finance
  // repository is built (use the account_balances view).
  static const _summary = AccountsSummary(
    totalBalance: 26752.26,
    accountCount: 11,
    income: 187670.96,
    expense: 175046.21,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // padding: zero so the card can start at the very top of the screen,
    // behind the status bar and the transparent app bar.
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const TotalBalanceCard(summary: _summary),
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

/// Debit/credit card shaped panel at the top of the Accounts page.
/// It draws behind the status bar and the (transparent) app bar.
class TotalBalanceCard extends StatelessWidget {
  final AccountsSummary summary;
  const TotalBalanceCard({super.key, required this.summary});

  /// ISO/IEC 7810 ID-1 card size: 85.60 mm x 53.98 mm.
  static const double cardRatio = 85.60 / 53.98;

  static const double _bottomRadius = 28;
  static const Color _incomeColor = Color(0xFF4CAF50);
  static const Color _expenseColor = Color(0xFFF44A5A);

  static String _plain(double v) => Utils.formatCurrency(v, symbol: '');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final muted = fg.withValues(alpha: 0.7);

    // Space taken by the status bar + app bar, so content starts below them.
    final topInset = MediaQuery.viewPaddingOf(context).top + kToolbarHeight;

    return AspectRatio(
      aspectRatio: cardRatio,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          AppConstants.spaceLg - AppConstants.spaceXs,
          topInset,
          AppConstants.spaceLg - AppConstants.spaceXs,
          AppConstants.spaceMd,
        ),
        decoration: BoxDecoration(
          color: accent.background,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(_bottomRadius),
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // "Total Balance" on the left, account count on the right
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Balance',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: muted,
                        ),
                      ),
                      Text(
                        '${summary.accountCount} accounts',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spaceXs),
                  // Big balance on the left
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      Utils.formatCurrency(
                        summary.totalBalance,
                        symbol: '₱ ',
                      ),
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontSize: 38,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceSm),
                  // Analytics: green = income | red = expense (right side)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.arrow_upward,
                          size: 11,
                          color: _incomeColor,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          _plain(summary.income),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _incomeColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                        Text(
                          _plain(summary.expense),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _expenseColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}