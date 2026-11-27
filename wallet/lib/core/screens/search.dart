import 'package:material_ui/material_ui.dart';

import '../../database/helper.dart';
import '../../features/finance.dart';
import '../constants.dart';
import '../failures.dart';
import '../themes.dart';
import '../utils.dart';
import 'categories.dart';
import 'settings.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _CategoryHit {
  final CategoryGroup group;
  final CategoryItem item;
  const _CategoryHit(this.group, this.item);
}

class _SearchScreenState extends State<SearchScreen> {
  static const int _maxPerSection = 25;

  final _db = DatabaseHelper.instance;
  final _controller = TextEditingController();

  List<HistoryEntry> _history = const [];
  List<ReminderItem> _reminders = const [];
  List<AccountOption> _accounts = const [];
  List<_CategoryHit> _categories = const [];
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
    _db.changes.addListener(_load);
  }

  @override
  void dispose() {
    _db.changes.removeListener(_load);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final history = await _db.getHistory();
      final reminders = await _db.getReminders();
      final accounts = await _db.getAccountOptions();
      final hits = <_CategoryHit>[];
      for (final g in CategoryGroup.values) {
        for (final item in await _db.getCategoryItems(g)) {
          hits.add(_CategoryHit(g, item));
        }
      }
      if (!mounted) return;
      setState(() {
        _history = history;
        _reminders = reminders;
        _accounts = accounts;
        _categories = hits;
        _loaded = true;
        _error = null;
      });
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      if (mounted) setState(() => _error = const UnknownFailure().message);
    }
  }

  String _groupLabel(CategoryGroup g) {
    switch (g) {
      case CategoryGroup.accountType:
        return 'Account type';
      case CategoryGroup.accountCategory:
        return 'Account category';
      case CategoryGroup.income:
        return 'Income category';
      case CategoryGroup.expense:
        return 'Expense category';
      case CategoryGroup.transfer:
        return 'Transfer category';
    }
  }

  /// Every word typed has to be found somewhere in the item.
  bool _match(List<String?> fields, List<String> tokens) {
    final hay = fields.whereType<String>().join(' ').toLowerCase();
    return tokens.every((t) => hay.contains(t));
  }

  // ---------- Pieces ----------

  Widget _tint(Color color, Widget child) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Center(child: child),
  );

  Widget _amount(String text, Color color) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 110),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    ),
  );

  Widget _tile({
    required Color fg,
    required Widget leading,
    required String title,
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: leading,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w700, color: fg),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: fg.withValues(alpha: AppConstants.mutedAlpha),
              ),
            ),
      trailing: trailing,
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required int total,
    required List<Widget> rows,
    required Color fg,
    required Color bg,
  }) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final divider = Color.lerp(bg, fg, AppConstants.dividerBlend)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceMd + AppConstants.spaceXs,
            AppConstants.spaceMd,
            AppConstants.spaceMd,
            AppConstants.spaceSm,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: onSurface),
              const SizedBox(width: AppConstants.spaceSm),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: onSurface,
                ),
              ),
              const SizedBox(width: AppConstants.spaceSm),
              Text(
                '$total',
                style: TextStyle(
                  color: onSurface.withValues(alpha: AppConstants.mutedAlpha),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceMd,
          ),
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: AppConstants.spaceMd,
                      endIndent: AppConstants.spaceMd,
                      color: divider,
                    ),
                  rows[i],
                ],
              ],
            ),
          ),
        ),
        if (total > rows.length)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spaceLg,
              AppConstants.spaceSm,
              AppConstants.spaceMd,
              0,
            ),
            child: Text(
              'Showing ${rows.length} of $total. Type more to narrow it down.',
              style: TextStyle(
                fontSize: 12,
                color: onSurface.withValues(alpha: AppConstants.mutedAlpha),
              ),
            ),
          ),
      ],
    );
  }

  Widget _message(IconData icon, String title, String body) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppConstants.emptyStateIconSize, color: muted),
            const SizedBox(height: AppConstants.spaceSm),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: AppConstants.spaceXs),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Rows ----------

  Widget _accountRow(AccountOption a, Color fg) => _tile(
    fg: fg,
    leading: _tint(
      fg,
      accountTypeIconWidget(a.typeName, a.typeIcon, size: 22, color: fg),
    ),
    title: a.name,
    subtitle: a.typeName,
    trailing: Icon(Icons.chevron_right, color: fg),
    onTap: () => showAccountById(context, a.id),
  );

  Widget _categoryRow(_CategoryHit h, Color fg) {
    final isTx =
        h.group == CategoryGroup.income || h.group == CategoryGroup.expense;
    final color = (isTx && h.item.color != null) ? Color(h.item.color!) : fg;
    return _tile(
      fg: fg,
      leading: _tint(
        color,
        categoryIconWidget(h.item.icon, size: 22, color: color),
      ),
      title: h.item.name,
      subtitle: _groupLabel(h.group),
      trailing: Icon(Icons.chevron_right, color: fg),
      onTap: () {
        if (isTx) {
          showCategoryTransactions(
            context,
            id: h.item.id,
            name: h.item.name,
            icon: h.item.icon,
            color: h.item.color,
            kind: h.group == CategoryGroup.income ? 'income' : 'expense',
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CategoriesScreen()),
          );
        }
      },
    );
  }

  Widget _txRow(HistoryEntry e, Color fg) {
    final s = AppSettings.instance;
    final isTransfer = e.type == 'transfer';
    final color = isTransfer
        ? s.transferColor
        : (e.type == 'income' ? s.incomeColor : s.expenseColor);
    final sign = isTransfer ? '±' : (e.type == 'income' ? '+' : '−');
    final sub = isTransfer
        ? '${e.accountName} → ${e.toAccountName ?? ''}'
        : [e.categoryName, e.accountName].whereType<String>().join(' · ');
    return _tile(
      fg: fg,
      leading: _tint(
        color,
        isTransfer
            ? Icon(Icons.swap_horiz, size: 22, color: color)
            : categoryIconWidget(e.categoryIcon, size: 22, color: color),
      ),
      title: e.title,
      subtitle: '$sub · ${Utils.formatDate(e.date)}',
      trailing: _amount(
        '$sign${Utils.formatCurrency(e.amount, symbol: AppConstants.currencySymbol)}',
        color,
      ),
      onTap: () => showTransactionReceipt(context, e),
    );
  }

  Widget _reminderRow(ReminderItem r, Color fg) {
    final s = AppSettings.instance;
    final amountColor = r.type == 'income' ? s.incomeColor : s.expenseColor;
    final sub = [
      r.categoryName,
      'Due ${Utils.formatDate(r.dueDate)}',
    ].whereType<String>().join(' · ');
    return _tile(
      fg: fg,
      leading: _tint(
        s.reminderColor,
        Icon(Icons.notifications_active, size: 22, color: s.reminderColor),
      ),
      title: r.title,
      subtitle: sub,
      trailing: _amount(
        '${r.type == 'income' ? '+' : '−'}'
        '${Utils.formatCurrency(r.amount, symbol: AppConstants.currencySymbol)}',
        amountColor,
      ),
      onTap: () => showReminderEditor(context, r),
    );
  }

  // ---------- Screen ----------

  Widget _body(String query, Color fg, Color bg) {
    if (_error != null) {
      return _message(Icons.error_outline, 'Something went wrong', _error!);
    }
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (query.isEmpty) {
      return _message(
        Icons.search,
        'Search Wallet'.tr,
        'Find transactions, reminders, accounts and categories.',
      );
    }

    final tokens = query.toLowerCase().split(RegExp(r'\s+'));

    final accounts = [
      for (final a in _accounts)
        if (_match([a.name, a.typeName, 'account'], tokens)) a,
    ];
    final categories = [
      for (final h in _categories)
        if (_match([h.item.name, _groupLabel(h.group)], tokens)) h,
    ];
    final txs = [
      for (final e in _history)
        if (_match([
          e.title,
          e.note,
          e.categoryName,
          e.accountName,
          e.toAccountName,
          e.type,
          e.amount.toStringAsFixed(2),
          Utils.formatDate(e.date),
        ], tokens))
          e,
    ];
    final reminders = [
      for (final r in _reminders)
        if (_match([
          r.title,
          r.note,
          r.categoryName,
          r.accountName,
          r.type,
          'reminder',
          r.amount.toStringAsFixed(2),
          Utils.formatDate(r.dueDate),
        ], tokens))
          r,
    ];

    if (accounts.isEmpty &&
        categories.isEmpty &&
        txs.isEmpty &&
        reminders.isEmpty) {
      return _message(Icons.search_off, 'No results', 'Nothing matches "$query".');
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceLg),
      children: [
        if (accounts.isNotEmpty)
          _section(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Accounts',
            total: accounts.length,
            rows: [
              for (final a in accounts.take(_maxPerSection)) _accountRow(a, fg),
            ],
            fg: fg,
            bg: bg,
          ),
        if (categories.isNotEmpty)
          _section(
            icon: Icons.category_outlined,
            title: 'Categories',
            total: categories.length,
            rows: [
              for (final h in categories.take(_maxPerSection))
                _categoryRow(h, fg),
            ],
            fg: fg,
            bg: bg,
          ),
        if (txs.isNotEmpty)
          _section(
            icon: Icons.receipt_long_outlined,
            title: 'Transactions',
            total: txs.length,
            rows: [for (final e in txs.take(_maxPerSection)) _txRow(e, fg)],
            fg: fg,
            bg: bg,
          ),
        if (reminders.isNotEmpty)
          _section(
            icon: Icons.notifications_outlined,
            title: 'Reminders',
            total: reminders.length,
            rows: [
              for (final r in reminders.take(_maxPerSection))
                _reminderRow(r, fg),
            ],
            fg: fg,
            bg: bg,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final query = _controller.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search Wallet'.tr,
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Clear',
              onPressed: _controller.clear,
            ),
        ],
      ),
      body: _body(query, accent.foreground, accent.background),
    );
  }
}