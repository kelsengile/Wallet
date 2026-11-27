import 'package:material_ui/material_ui.dart';

import '../constants.dart';
import '../themes.dart';

class _Qa {
  final String q;
  final String a;
  const _Qa(this.q, this.a);
}

class _Topic {
  final IconData icon;
  final String title;
  final List<_Qa> items;
  const _Topic(this.icon, this.title, this.items);
}

const List<_Topic> _topics = [
  _Topic(Icons.explore_outlined, 'Getting around', [
    _Qa('Open and close the side menu',
        'Tap the menu button at the top left, or swipe from the left edge. To close it, swipe left, tap the dimmed area, or tap an item.'),
    _Qa('Search everything',
        'Tap the magnifier at the top right and start typing. Accounts, categories, transactions and reminders are searched together. Tap a result to open it.'),
    _Qa('Use the + button',
        'Tap + to fan out Income, Expense, Transfer and Reminder, then tap one to open its form. Tap X, tap anywhere on the page, or scroll to fold the buttons away.'),
    _Qa('Close a pop-up',
        'Tap the dimmed area outside sheets and dialogs, drag a handle down, or use the phone Back button or gesture.'),
  ]),
  _Topic(Icons.account_balance_wallet_outlined, 'Accounts and cards', [
    _Qa('Flip a card',
        'Tap an account card. The back shows your note and a shortcut button.'),
    _Qa('Open an account',
        'Long-press a card or a row in list view. Tap the account name for full history, the net balance for analytics, or the income/expense figure to filter.'),
    _Qa('Edit or delete an account',
        'Open the account, then long-press its name at the top of the panel. Change what you like and tap Save Changes, or tap Delete Account.'),
    _Qa('Add an account',
        'Tap + next to "My Accounts", fill in the name, balance, type and category, then tap Add Account.'),
    _Qa('Hide or show amounts',
        'Tap the eye button next to "My Accounts". A closed eye masks every amount with ****.'),
    _Qa('Switch account views',
        'Tap the view button to the right of the eye to switch between card view and list view.'),
    _Qa('Reorder account types',
        'Long-press the view button. Drag the handle beside a type up or down, then tap the check button.'),
  ]),
  _Topic(Icons.receipt_long_outlined, 'Transactions and reminders', [
    _Qa('Add a transaction',
        'Tap +, choose Income, Expense, Transfer or Reminder, fill in the form and tap the button at the bottom. The button stays unavailable until required fields are filled.'),
    _Qa('Pick a date and time',
        'Tap the date field, choose a day, scroll the hour and minute wheels, then tap Apply.'),
    _Qa('See, edit or delete a transaction',
        'Tap a transaction to see its receipt, then tap the pen to edit it. Swipe left to move it to the Trash.'),
    _Qa('Work with reminders',
        'Reminders sit at the top of History. Tap one to open it and use Mark as Done to turn it into a transaction. A repeating reminder creates the next one.'),
  ]),
  _Topic(Icons.insights_outlined, 'History and analytics', [
    _Qa('Open History or Analytics',
        'Tap the big Total Balance number for History, or the income and expense figures beside it for Analytics.'),
    _Qa('Change the dates',
        'Tap the filter icon in the header. Choose Day, Week, Month, Year, All or Custom, then tap Apply. Use the arrows to move between periods.'),
    _Qa('Filter income or expense',
        'In History, tap the income or expense total; tap again to see everything. In Analytics, tap Income, Expense or Net to open that view.'),
    _Qa('Use the line graph',
        'Tap a dot to see its amount; tap empty space to deselect. Pinch to zoom and drag to move around. Double-tap or use the reset button to reset.'),
  ]),
  _Topic(Icons.category_outlined, 'Categories', [
    _Qa('Open Categories',
        'Open the side menu and choose Categories. Find account Types and Categories, plus Income, Expense and Transfer categories.'),
    _Qa('Add, edit or delete',
        'Tap + on a card to add. Tap a bar or its pen to edit. Swipe a bar left to delete; Wallet asks first. Transfer is locked.'),
    _Qa('Reorder',
        'Press and drag the handle beside a category bar.'),
  ]),
  _Topic(Icons.calculate_outlined, 'Calculator and converter', [
    _Qa('Use the calculator',
        'Open Calculator from the side menu. Tap f(x) for scientific keys and the clock for history. Hold Backspace to clear everything.'),
    _Qa('Float the calculator',
        'Tap the float button. Drag the title bar to move it, tap it to minimise or restore it, or use the full-screen and close buttons.'),
    _Qa('Use the converter',
        'Choose a category in Converter. Tap a panel to type, tap a unit name to change it, and use the swap button to reverse units.'),
  ]),
  _Topic(Icons.person_outline, 'Profile', [
    _Qa('Set up your profile',
        'Open Profile, tap the pen, then change the banner or round picture and fill in your name, username and bio.'),
  ]),
  _Topic(Icons.storage_outlined, 'Trash, backup and reset', [
    _Qa('Restore or delete from Trash',
        'Open Database, then Trash bin. Swipe right to restore, swipe left to delete forever, or use the menu. The sweep icon empties everything.'),
    _Qa('Backup and reset',
        'Database > Export data saves a backup. Import data replaces the current data with a backup. Clear all data and reset returns Wallet to a fresh install.'),
  ]),
  _Topic(Icons.settings_outlined, 'Settings, security and notifications', [
    _Qa('Change theme and font',
        'Settings > Theme changes transaction and action colors. Font changes style, size and bold text. Animation can be enabled or disabled.'),
    _Qa('Currency, location and language',
        'Settings > Localization changes the currency, location and language. Location determines the time used for dates, reminders and notifications.'),
    _Qa('Lock the app',
        'Settings > Security > App Security creates a PIN. Touch ID or Face ID can be added if the phone supports it. Wallet locks after 30 seconds in the background.'),
    _Qa('Turn on notifications',
        'Settings > Notifications > Push notifications allows Wallet to send alerts. You can enable reminder alerts, budget alerts, a daily 8 PM summary, sound and vibration.'),
  ]),
];

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.help_outline),
            const SizedBox(width: AppConstants.spaceSm),
            Text('FAQ'.tr),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppConstants.spaceXl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spaceMd + AppConstants.spaceXs,
              AppConstants.spaceMd,
              AppConstants.spaceMd,
              AppConstants.spaceSm,
            ),
            child: Text(
              'Tap a topic, then a question, to see how every gesture in Wallet works.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final topic in _topics) _TopicCard(topic: topic),
        ],
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  final _Topic topic;
  const _TopicCard({required this.topic});

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final inner = Color.alphaBlend(
      fg.withValues(alpha: 0.08),
      accent.background,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMd,
        vertical: AppConstants.spaceXs + 2,
      ),
      child: Material(
        color: accent.background,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          iconColor: fg,
          collapsedIconColor: fg,
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: fg.withValues(alpha: AppConstants.tintAlpha),
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            ),
            child: Icon(topic.icon, size: 20, color: fg),
          ),
          title: Text(
            topic.title,
            style: TextStyle(fontWeight: FontWeight.w700, color: fg),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            for (final qa in topic.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: inner,
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm + 4),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    shape: const Border(),
                    collapsedShape: const Border(),
                    iconColor: fg,
                    collapsedIconColor: fg,
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    title: Text(
                      qa.q,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                    children: [
                      Text(
                        qa.a,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: fg.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
