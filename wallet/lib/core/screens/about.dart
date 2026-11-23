import 'package:flutter/material.dart';

import '../constants.dart';
import '../links.dart';
import '../themes.dart';

// ------------------------------------------------------------------
// Info widgets (also used by the Feedback screen)
// ------------------------------------------------------------------

/// Big round icon + title + subtitle at the top of an info screen.
class InfoHero extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const InfoHero({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceLg,
        AppConstants.spaceLg,
        AppConstants.spaceLg,
        AppConstants.spaceSm,
      ),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: accent.background,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: accent.foreground),
          ),
          const SizedBox(height: AppConstants.spaceMd),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Rounded accent card with an icon, a title and any content.
class InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  const InfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMd,
        vertical: AppConstants.spaceXs + 2,
      ),
      child: Material(
        color: accent.background,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: AppConstants.tintAlpha),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusSm,
                      ),
                    ),
                    child: Icon(icon, size: 20, color: fg),
                  ),
                  const SizedBox(width: AppConstants.spaceSmMd),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceSmMd),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Paragraph drawn in the accent card's text color.
class InfoText extends StatelessWidget {
  final String text;
  const InfoText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final fg = AppTheme.accentOf(context).foreground;
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        height: 1.45,
        color: fg.withValues(alpha: 0.9),
      ),
    );
  }
}

/// One line with a small icon in front.
class InfoBullet extends StatelessWidget {
  final IconData icon;
  final String text;
  const InfoBullet({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final fg = AppTheme.accentOf(context).foreground;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: AppConstants.spaceSmMd),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: fg.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------
// About screen
// ------------------------------------------------------------------

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _features = <(IconData, String)>[
    (
      Icons.account_balance_wallet_outlined,
      'Accounts shown as flippable cards: cash, bank, e-wallet, credit and more',
    ),
    (
      Icons.swap_vert,
      'Income, expense and transfer records with notes and pictures',
    ),
    (
      Icons.notifications_active_outlined,
      'One-time or repeating reminders, with optional phone alerts',
    ),
    (
      Icons.category_outlined,
      'Your own categories, icons, colors and monthly budgets',
    ),
    (Icons.insights_outlined, 'History and analytics with charts'),
    (
      Icons.calculate_outlined,
      'A calculator and a converter for currency, units, loans, dates and more',
    ),
    (Icons.lock_outline, 'PIN, fingerprint and face lock'),
    (
      Icons.backup_outlined,
      'Backup and restore from a file, plus a trash bin for mistakes',
    ),
    (Icons.palette_outlined, 'Themes, fonts, many languages and currencies'),
  ];

  Future<void> _github(BuildContext context) async {
    final ok = await Links.openRepository();
    if (ok || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Couldn\'t open GitHub.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: AppConstants.spaceSm),
            Text('About'.tr),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppConstants.spaceXl),
        children: [
          InfoHero(
            icon: Icons.account_balance_wallet_outlined,
            title: AppConstants.appName,
            subtitle: '${'Version'.tr} ${AppConstants.appVersion}',
          ),
          const SizedBox(height: AppConstants.spaceSm),
          const InfoCard(
            icon: Icons.help_outline,
            title: 'What is Wallet?',
            child: InfoText(
              'Wallet is a personal finance app that keeps your money in one '
              'place. Add your cash, bank, e-wallet, credit and other accounts '
              'as cards, record every income, expense and transfer, and see '
              'where your money goes.',
            ),
          ),
          const InfoCard(
            icon: Icons.flag_outlined,
            title: 'Our purpose',
            child: InfoText(
              'Wallet was built to make everyday money tracking simple, fast '
              'and private. It helps you know what you have, what you spent '
              'and what is coming up, so you can plan with confidence instead '
              'of guessing.',
            ),
          ),
          InfoCard(
            icon: Icons.auto_awesome_outlined,
            title: 'What you can do',
            child: Column(
              children: [
                for (final f in _features) InfoBullet(icon: f.$1, text: f.$2),
              ],
            ),
          ),
          const InfoCard(
            icon: Icons.shield_outlined,
            title: 'Your data stays yours',
            child: InfoText(
              'Everything is stored in a database on your device. There is no '
              'account and no sign-up. The only thing that goes online is the '
              'currency rate lookup in the Converter and when you change '
              'currency. Alerts are created on your phone. You can export a '
              'backup file at any time and restore it later.',
            ),
          ),
          InfoCard(
            icon: Icons.favorite_outline,
            title: 'Made by',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const InfoText(
                  'Designed and developed by ${AppConstants.developerName}, '
                  'built with Flutter, and improved with the help of everyone '
                  'who sends feedback.',
                ),
                const SizedBox(height: AppConstants.spaceMd),
                OutlinedButton.icon(
                  onPressed: () => _github(context),
                  icon: const Icon(Icons.code),
                  label: const Text('View on GitHub'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppConstants.spaceMd),
            child: Center(
              child: Text(
                '© ${DateTime.now().year} ${AppConstants.developerName}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}