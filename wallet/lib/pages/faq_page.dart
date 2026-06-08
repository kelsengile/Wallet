import 'package:flutter/material.dart';

class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  static const _faqs = [
    (
      q: 'How do I add an account?',
      a: 'On the Accounts page tap the + button in the top-right corner. '
          'Give your account a name, choose its type (Cash, Bank, E-Wallet…), '
          'enter an optional initial balance, then tap Save.'
    ),
    (
      q: 'How do I record a transaction?',
      a: 'Open the History page and tap the filled + button. Choose between '
          'Expense or Income, fill in the title, amount, category, and '
          'optionally an account and note, then tap Add Transaction.'
    ),
    (
      q: 'Can I edit or delete a transaction?',
      a: 'Yes. On the History page tap any transaction to edit it. '
          'To delete, swipe the transaction row to the left and confirm.'
    ),
    (
      q: 'Does the app work offline?',
      a: 'Completely. All data is stored locally on your device using '
          'SQLite (sqflite). No internet connection is required.'
    ),
    (
      q: 'How is my account balance calculated?',
      a: 'The balance is updated automatically whenever you add, edit, or '
          'delete a transaction. Income increases the balance; expenses '
          'decrease it. The initial balance you set when creating the account '
          'is the starting point.'
    ),
    (
      q: 'Can I reorder account sections?',
      a: 'Yes! On the Accounts page tap the reorder icon (top-right) to '
          'enter reorder mode, then drag the section headers to your '
          'preferred order. The order is saved automatically.'
    ),
    (
      q: 'How do I clear all my data?',
      a: 'Go to System Actions in the side menu (or Profile → Clear All Data) '
          'and confirm the prompt. This permanently deletes all accounts and '
          'transactions and cannot be undone.'
    ),
    (
      q: 'Will more features be added?',
      a: 'Yes! Planned features include budget goals, recurring transactions, '
          'CSV export/import, and customisable themes. Use Send Feedback to '
          'suggest features.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('FAQ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Frequently Asked Questions',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a question to expand the answer.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          ..._faqs.map(
            (item) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                leading:
                    Icon(Icons.help_outline, color: theme.colorScheme.primary),
                title: Text(
                  item.q,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                children: [
                  Text(item.a,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5,
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
