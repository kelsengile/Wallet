import 'package:flutter/material.dart';

import 'feedback_page.dart';

class _Faq {
  final String q;
  final String a;
  final String category;
  const _Faq({required this.q, required this.a, required this.category});
}

class FaqPage extends StatefulWidget {
  const FaqPage({super.key});

  @override
  State<FaqPage> createState() => _FaqPageState();
}

class _FaqPageState extends State<FaqPage> {
  static const _faqs = [
    _Faq(
      category: 'Accounts',
      q: 'How do I add an account?',
      a: 'On the Accounts page tap the + button in the top-right corner. '
          'Give your account a name, choose its type (Cash, Bank, E-Wallet…), '
          'enter an optional initial balance, then tap Save.',
    ),
    _Faq(
      category: 'Accounts',
      q: 'Can I reorder account sections?',
      a: 'Yes! On the Accounts page tap the reorder icon (top-right) to '
          'enter reorder mode, then drag the section headers to your '
          'preferred order. The order is saved automatically.',
    ),
    _Faq(
      category: 'Accounts',
      q: 'How is my account balance calculated?',
      a: 'The balance is updated automatically whenever you add, edit, or '
          'delete a transaction. Income increases the balance; expenses '
          'decrease it. The initial balance you set when creating the account '
          'is the starting point.',
    ),
    _Faq(
      category: 'Transactions',
      q: 'How do I record a transaction?',
      a: 'Open the History page and tap the filled + button. Choose between '
          'Expense or Income, fill in the title, amount, category, and '
          'optionally an account and note, then tap Add Transaction.',
    ),
    _Faq(
      category: 'Transactions',
      q: 'Can I edit or delete a transaction?',
      a: 'Yes. On the History page tap any transaction to edit it. '
          'To delete, swipe the transaction row to the left and confirm.',
    ),
    _Faq(
      category: 'Data & Privacy',
      q: 'Does the app work offline?',
      a: 'Completely. All data is stored locally on your device using '
          'SQLite (sqflite). No internet connection is required.',
    ),
    _Faq(
      category: 'Data & Privacy',
      q: 'How do I clear all my data?',
      a: 'Go to System Actions in the side menu (or Profile → Clear All Data) '
          'and confirm the prompt. This permanently deletes all accounts and '
          'transactions and cannot be undone.',
    ),
    _Faq(
      category: 'General',
      q: 'Will more features be added?',
      a: 'Yes! Planned features include budget goals, recurring transactions, '
          'CSV export/import, and customisable themes. Use Send Feedback to '
          'suggest features.',
    ),
    _Faq(
      category: 'Accounts',
      q: 'Can I have multiple accounts of the same type?',
      a: 'Yes. You can create as many accounts as you like, even several '
          'of the same type (e.g. two Bank accounts), as long as each one '
          'has a unique name.',
    ),
    _Faq(
      category: 'Accounts',
      q: 'Can I delete an account?',
      a: 'Yes. Open the account from the Accounts page, tap the menu icon, '
          'then choose Delete. Deleting an account also removes its '
          'transaction history, so make sure you no longer need it.',
    ),
    _Faq(
      category: 'Transactions',
      q: 'Can I attach a note or receipt photo to a transaction?',
      a: 'When adding or editing a transaction you can attach a short note. '
          'Tap a transaction afterward to view its receipt-style summary.',
    ),
    _Faq(
      category: 'Transactions',
      q: 'What happens to deleted transactions?',
      a: 'Deleted transactions go to the Trash Bin first instead of being '
          'removed immediately. You can restore them or permanently erase '
          'them from there.',
    ),
    _Faq(
      category: 'Transactions',
      q: 'Can I search or filter my transaction history?',
      a: 'Yes. Use the Search page to find transactions by title, category, '
          'account, or amount, and the History page filters to narrow by '
          'date range or type.',
    ),
    _Faq(
      category: 'Budgets',
      q: 'How do budgets work?',
      a: 'On the Budget page you can set a spending limit per category for '
          'a given period. The app tracks your expenses against that limit '
          'and warns you as you get close to it.',
    ),
    _Faq(
      category: 'Budgets',
      q: 'What happens when I go over budget?',
      a: 'The Budget page highlights any category that has gone over its '
          'limit so you can see at a glance where you overspent. This does '
          'not block you from adding more transactions.',
    ),
    _Faq(
      category: 'Categories',
      q: 'Can I create custom categories?',
      a: 'Yes. Open Category Manager from the side menu to add, rename, '
          'recolor, or delete categories for both income and expenses.',
    ),
    _Faq(
      category: 'Categories',
      q: 'Can I delete a category that already has transactions?',
      a: 'You can, but any existing transactions under that category will '
          'be moved to an "Uncategorized" group rather than deleted.',
    ),
    _Faq(
      category: 'General',
      q: 'Does the app support multiple currencies?',
      a: 'Yes. You can set a default currency in Settings, and the built-in '
          'Currency Converter lets you check conversions between supported '
          'currencies.',
    ),
    _Faq(
      category: 'General',
      q: 'Is there a built-in calculator?',
      a: 'Yes. Tap the calculator icon when entering an amount to quickly '
          'add, subtract, or multiply values before saving a transaction.',
    ),
    _Faq(
      category: 'General',
      q: "Can I customize the app's appearance?",
      a: 'Yes. Visit Settings to switch between light and dark themes, and '
          'use the Card Theme Picker to personalize the look of your '
          'account cards.',
    ),
    _Faq(
      category: 'Data & Privacy',
      q: 'Can I lock the app for privacy?',
      a: 'Yes. Enable the app lock option in Settings to require a PIN or '
          'biometric unlock (where supported) before the app opens.',
    ),
    _Faq(
      category: 'Data & Privacy',
      q: 'Does this app share my data with anyone?',
      a: 'No. Since everything is stored locally on your device, your '
          'financial data is never sent to an external server or shared '
          'with third parties.',
    ),
    _Faq(
      category: 'Data & Privacy',
      q: 'Can I back up or restore my data?',
      a: 'Backup and restore options live under Profile → System Actions. '
          "It's a good idea to back up before clearing data or switching "
          'devices.',
    ),
  ];

  late final List<String> _categories;
  String _activeCategory = 'All';
  String _query = '';
  final _searchCtrl = TextEditingController();
  int? _expandedIndex;

  @override
  void initState() {
    super.initState();
    _categories = ['All', ..._faqs.map((f) => f.category).toSet()];
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_Faq> get _filtered {
    final q = _query.trim().toLowerCase();
    return _faqs.where((f) {
      final matchesCategory =
          _activeCategory == 'All' || f.category == _activeCategory;
      final matchesQuery = q.isEmpty ||
          f.q.toLowerCase().contains(q) ||
          f.a.toLowerCase().contains(q);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _filtered;

    return Scaffold(
      appBar: AppBar(title: const Text('FAQ')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Frequently Asked Questions',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Search or browse by category, then tap a question to expand it.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search the FAQ…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() {
                              _searchCtrl.clear();
                              _query = '';
                            }),
                          ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final cat = _categories[i];
                      final selected = cat == _activeCategory;
                      return ChoiceChip(
                        label: Text(cat),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _activeCategory = cat),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? _EmptyState(query: _query, theme: theme)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: results.length + 1,
                    itemBuilder: (context, i) {
                      if (i == results.length) {
                        return _ContactCard(theme: theme);
                      }
                      final item = results[i];
                      final index = _faqs.indexOf(item);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        clipBehavior: Clip.antiAlias,
                        child: ExpansionTile(
                          initiallyExpanded: _expandedIndex == index,
                          onExpansionChanged: (open) => setState(
                              () => _expandedIndex = open ? index : null),
                          tilePadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          leading: Icon(Icons.help_outline,
                              color: theme.colorScheme.primary),
                          title: Text(
                            item.q,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            item.category,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          children: [
                            Text(
                              item.a,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String query;
  final ThemeData theme;
  const _EmptyState({required this.query, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              query.isEmpty
                  ? 'No questions in this category yet.'
                  : 'No results for "$query".',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FeedbackPage()),
                );
              },
              icon: const Icon(Icons.feedback_outlined),
              label: const Text('Ask us directly'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final ThemeData theme;
  const _ContactCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.support_agent, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Still need help?",
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Can't find your answer? Send us your question.",
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FeedbackPage()),
                );
              },
              child: const Text('Contact'),
            ),
          ],
        ),
      ),
    );
  }
}
