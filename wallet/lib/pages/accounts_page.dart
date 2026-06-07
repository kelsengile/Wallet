import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/account_model.dart';
import '../models/transaction_model.dart';

// ── Number formatter ───────────────────────────────────────────────────────────

final _currencyFmt = NumberFormat('#,##0.00', 'en_PH');

String _fmt(double v) => _currencyFmt.format(v);

// ── Type metadata ──────────────────────────────────────────────────────────────

const _typeColors = {
  'cash': Color(0xFF22C55E),
  'bank': Color(0xFF3B82F6),
  'e-wallet': Color(0xFFA855F7),
  'credit': Color(0xFFEF4444),
  'loan': Color(0xFFF97316),
  'investment': Color(0xFF0EA5E9),
  'savings': Color(0xFF14B8A6),
};

const _typeIcons = {
  'cash': Icons.payments_outlined,
  'bank': Icons.account_balance_outlined,
  'e-wallet': Icons.phone_android_outlined,
  'credit': Icons.credit_card_outlined,
  'loan': Icons.handshake_outlined,
  'investment': Icons.trending_up_outlined,
  'savings': Icons.savings_outlined,
};

const _typeGradients = {
  'cash': [Color(0xFF16A34A), Color(0xFF4ADE80)],
  'bank': [Color(0xFF1D4ED8), Color(0xFF60A5FA)],
  'e-wallet': [Color(0xFF7C3AED), Color(0xFFC084FC)],
  'credit': [Color(0xFFB91C1C), Color(0xFFF87171)],
  'loan': [Color(0xFFC2410C), Color(0xFFFB923C)],
  'investment': [Color(0xFF0369A1), Color(0xFF38BDF8)],
  'savings': [Color(0xFF0F766E), Color(0xFF2DD4BF)],
};

const _typeLabels = {
  'cash': 'Cash',
  'bank': 'Bank',
  'e-wallet': 'E-Wallet',
  'credit': 'Credits',
  'loan': 'Loans',
  'investment': 'Investments',
  'savings': 'Savings',
};

const _typeColorHexMap = {
  'cash': '#22C55E',
  'bank': '#3B82F6',
  'e-wallet': '#A855F7',
  'credit': '#EF4444',
  'loan': '#F97316',
  'investment': '#0EA5E9',
  'savings': '#14B8A6',
};

const _allTypes = [
  'cash',
  'bank',
  'e-wallet',
  'credit',
  'loan',
  'investment',
  'savings'
];

// ── Page ───────────────────────────────────────────────────────────────────────

class AccountsPage extends StatefulWidget {
  final VoidCallback? onNavigateToAnalytics;

  const AccountsPage({super.key, this.onNavigateToAnalytics});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  final _db = DatabaseHelper.instance;
  List<Account> _accounts = [];
  Map<String, List<Account>> _grouped = {};
  double _totalBalance = 0;
  double _totalIncome = 0;
  double _totalExpenses = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accounts = await _db.getAllAccounts();
    final income = await _db.getTotalIncome();
    final expenses = await _db.getTotalExpenses();
    if (!mounted) return;

    final grouped = <String, List<Account>>{};
    double total = 0;
    for (final a in accounts) {
      total += a.balance;
      (grouped[a.type] ??= []).add(a);
    }

    setState(() {
      _accounts = accounts;
      _grouped = grouped;
      _totalBalance = total;
      _totalIncome = income;
      _totalExpenses = expenses;
      _loading = false;
    });
  }

  void _showAddAccountDialog({Account? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final balanceCtrl = TextEditingController(
      text: existing != null ? existing.balance.toStringAsFixed(2) : '',
    );
    String selectedType = existing?.type ?? 'cash';
    String selectedCategory = existing?.category ?? 'personal';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                existing != null ? 'Edit Account' : 'New Account',
                style: Theme.of(ctx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              // Name
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Account Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 12),

              // Initial balance (add only)
              if (existing == null) ...[
                TextField(
                  controller: balanceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Initial Balance (₱)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Account type grid
              Text('Account Type', style: Theme.of(ctx).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _allTypes.map((t) {
                  final selected = selectedType == t;
                  final color = _typeColors[t]!;
                  return GestureDetector(
                    onTap: () => setS(() => selectedType = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: (MediaQuery.of(ctx).size.width - 40 - 24) / 4,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? color.withValues(alpha: 0.15)
                            : Theme.of(ctx).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? color : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(_typeIcons[t],
                              color: selected ? color : null, size: 20),
                          const SizedBox(height: 3),
                          Text(
                            _typeLabels[t]!,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: selected ? color : null,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Account category picker
              Text('Category', style: Theme.of(ctx).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kAccountCategories.map((cat) {
                  final selected = selectedCategory == cat;
                  final color = Theme.of(ctx).colorScheme.primary;
                  return GestureDetector(
                    onTap: () => setS(() => selectedCategory = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? color.withValues(alpha: 0.12)
                            : Theme.of(ctx).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected ? color : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        _capitalize(cat),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected ? color : null,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Submit
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: Icon(existing != null ? Icons.save : Icons.add),
                  label:
                      Text(existing != null ? 'Save Changes' : 'Add Account'),
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    if (existing != null) {
                      await _db.updateAccount(existing.copyWith(
                        name: nameCtrl.text.trim(),
                        type: selectedType,
                        category: selectedCategory,
                        colorHex: _typeColorHexMap[selectedType] ?? '#6366F1',
                      ));
                    } else {
                      await _db.insertAccount(Account(
                        name: nameCtrl.text.trim(),
                        balance:
                            double.tryParse(balanceCtrl.text.trim()) ?? 0.0,
                        type: selectedType,
                        category: selectedCategory,
                        colorHex: _typeColorHexMap[selectedType] ?? '#6366F1',
                        icon: 'wallet',
                      ));
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    _loadAccounts();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Future<void> _deleteAccount(Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: Text(
            'Delete "${account.name}" and all its transactions? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && account.id != null) {
      await _db.deleteAccount(account.id!);
      _loadAccounts();
    }
  }

  void _showAccountDetail(Account account) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _AccountDetailSheet(
        account: account,
        onTransactionChanged: _loadAccounts,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final presentTypes =
        _allTypes.where((t) => _grouped.containsKey(t)).toList();

    return RefreshIndicator(
      onRefresh: _loadAccounts,
      child: CustomScrollView(
        slivers: [
          // ── Hero header — seamlessly continues the nav bar gradient ───
          SliverToBoxAdapter(
            child: _TotalBalanceHero(
              totalBalance: _totalBalance,
              accountCount: _accounts.length,
              totalIncome: _totalIncome,
              totalExpenses: _totalExpenses,
              onAddAccount: _showAddAccountDialog,
              onNavigateToAnalytics: widget.onNavigateToAnalytics,
            ),
          ),

          // ── "My Accounts" label ───────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('My Accounts',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  FilledButton.tonalIcon(
                    onPressed: _showAddAccountDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
            ),
          ),

          // ── Empty state ───────────────────────────────────────────────
          if (_accounts.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        size: 56, color: theme.colorScheme.outlineVariant),
                    const SizedBox(height: 12),
                    Text('No accounts yet',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                    const SizedBox(height: 4),
                    Text('Tap "Add" to create your first account',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outlineVariant)),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final type = presentTypes[i];
                  return _AccountCategoryCarousel(
                    type: type,
                    accounts: _grouped[type]!,
                    onTap: _showAccountDetail,
                    onLongPress: (a) => _showAddAccountDialog(existing: a),
                    onDelete: _deleteAccount,
                  );
                },
                childCount: presentTypes.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

// ── Hero header ────────────────────────────────────────────────────────────────

class _TotalBalanceHero extends StatelessWidget {
  final double totalBalance;
  final int accountCount;
  final double totalIncome;
  final double totalExpenses;
  final VoidCallback onAddAccount;
  final VoidCallback? onNavigateToAnalytics;

  const _TotalBalanceHero({
    required this.totalBalance,
    required this.accountCount,
    required this.totalIncome,
    required this.totalExpenses,
    required this.onAddAccount,
    this.onNavigateToAnalytics,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final tertiary = theme.colorScheme.tertiary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary, tertiary],
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Top row: label + account counter ───────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Balance',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.white70, letterSpacing: 0.5),
              ),
              Text(
                '$accountCount account${accountCount != 1 ? 's' : ''}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ── Bottom row: big balance + income | expense ──────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₱ ${_fmt(totalBalance)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1.5,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onNavigateToAnalytics,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _IncomeExpenseCompact(
                        icon: Icons.arrow_downward,
                        amount: totalIncome,
                        color: const Color(0xFF4ADE80),
                      ),
                      Container(
                        width: 1,
                        height: 10,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                      _IncomeExpenseCompact(
                        icon: Icons.arrow_upward,
                        amount: totalExpenses,
                        color: const Color(0xFFF87171),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IncomeExpenseCompact extends StatelessWidget {
  final IconData icon;
  final double amount;
  final Color color;

  const _IncomeExpenseCompact({
    required this.icon,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 10),
        const SizedBox(width: 3),
        Text(
          '₱ ${_fmt(amount)}',
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Category carousel ──────────────────────────────────────────────────────────

class _AccountCategoryCarousel extends StatelessWidget {
  final String type;
  final List<Account> accounts;
  final void Function(Account) onTap;
  final void Function(Account) onLongPress;
  final void Function(Account) onDelete;

  const _AccountCategoryCarousel({
    required this.type,
    required this.accounts,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor = _typeColors[type] ?? theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header — number badge removed
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_typeIcons[type] ?? Icons.wallet,
                      color: typeColor, size: 15),
                ),
                const SizedBox(width: 8),
                Text(
                  _typeLabels[type] ?? type,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                // Count badge removed per design request
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Carousel
          SizedBox(
            height: 172,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              cacheExtent: 520,
              itemCount: accounts.length,
              itemBuilder: (_, i) {
                final a = accounts[i];
                return Padding(
                  padding:
                      EdgeInsets.only(right: i < accounts.length - 1 ? 14 : 0),
                  child: _AccountCard(
                    account: a,
                    onTap: () => onTap(a),
                    onLongPress: () => onLongPress(a),
                    onDelete: () => onDelete(a),
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

// ── Account card ───────────────────────────────────────────────────────────────

class _AccountCard extends StatelessWidget {
  final Account account;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  const _AccountCard({
    required this.account,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
  });

  BorderRadius _borderRadius() {
    switch (account.type) {
      case 'cash':
        return BorderRadius.zero;
      case 'e-wallet':
        return BorderRadius.circular(24);
      default:
        return BorderRadius.circular(18);
    }
  }

  bool get _isEwallet => account.type == 'e-wallet';

  @override
  Widget build(BuildContext context) {
    final gradients = _typeGradients[account.type] ??
        [const Color(0xFF6366F1), const Color(0xFF818CF8)];
    final br = _borderRadius();

    Widget card = Container(
      width: 255,
      height: 155,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradients,
        ),
        borderRadius: _isEwallet ? null : br,
        boxShadow: [
          BoxShadow(
            color: gradients[0].withValues(alpha: 0.38),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            right: -22,
            top: -22,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.09),
              ),
            ),
          ),
          Positioned(
            left: -10,
            bottom: -22,
            child: Container(
              width: 75,
              height: 75,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          // Delete button — pinned top-right, independent of text layout
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(Icons.delete_outline,
                    color: Colors.white70, size: 15),
              ),
            ),
          ),
          // Card body — name directly above balance, anchored to bottom-left
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Name sits directly above the balance number
                Padding(
                  padding: const EdgeInsets.only(right: 36),
                  child: Text(
                    account.name,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '₱ ${_fmt(account.balance)}',
                  style: TextStyle(
                    color: account.balance >= 0
                        ? Colors.white
                        : Colors.red.shade200,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    account.category.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (_isEwallet) {
      card = ClipPath(
        clipper: _OctagonClipper(),
        child: card,
      );
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: card,
    );
  }
}

class _OctagonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const cut = 22.0;
    return Path()
      ..moveTo(cut, 0)
      ..lineTo(size.width - cut, 0)
      ..lineTo(size.width, cut)
      ..lineTo(size.width, size.height - cut)
      ..lineTo(size.width - cut, size.height)
      ..lineTo(cut, size.height)
      ..lineTo(0, size.height - cut)
      ..lineTo(0, cut)
      ..close();
  }

  @override
  bool shouldReclip(_OctagonClipper old) => false;
}

// ── Account detail bottom sheet ────────────────────────────────────────────────

class _AccountDetailSheet extends StatefulWidget {
  final Account account;
  final VoidCallback? onTransactionChanged;

  const _AccountDetailSheet({
    required this.account,
    this.onTransactionChanged,
  });

  @override
  State<_AccountDetailSheet> createState() => _AccountDetailSheetState();
}

class _AccountDetailSheetState extends State<_AccountDetailSheet> {
  List<WalletTransaction> _transactions = [];
  List<Account> _allAccounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final txs = await DatabaseHelper.instance
        .getTransactionsByAccount(widget.account.id!);
    final accounts = await DatabaseHelper.instance.getAllAccounts();
    if (mounted) {
      setState(() {
        _transactions = txs;
        _allAccounts = accounts;
        _loading = false;
      });
    }
  }

  Future<void> _editTransaction(WalletTransaction existing) async {
    final updated = await WalletTransaction.showDialog(
      context,
      accounts: _allAccounts,
      existing: existing,
    );
    if (updated == null) return;
    await DatabaseHelper.instance.updateTransaction(existing, updated);
    await _load();
    widget.onTransactionChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor =
        _typeColors[widget.account.type] ?? theme.colorScheme.primary;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _typeIcons[widget.account.type] ??
                        Icons.account_balance_wallet,
                    color: typeColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.account.name,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Text(
                            (_typeLabels[widget.account.type] ??
                                    widget.account.type)
                                .toUpperCase(),
                            style: TextStyle(
                                fontSize: 11,
                                color: typeColor,
                                fontWeight: FontWeight.bold),
                          ),
                          if (widget.account.category.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              '· ${_capitalize(widget.account.category)}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.outline),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  '₱ ${_fmt(widget.account.balance)}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: widget.account.balance >= 0
                        ? Colors.green.shade700
                        : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Transactions',
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.outline)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _transactions.isEmpty
                      ? Center(
                          child: Text('No transactions for this account',
                              style:
                                  TextStyle(color: theme.colorScheme.outline)))
                      : ListView.separated(
                          controller: scrollCtrl,
                          itemCount: _transactions.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) {
                            final tx = _transactions[i];
                            final isIncome = tx.type == 'income';
                            return ListTile(
                              onTap: () => _editTransaction(tx),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              tileColor: theme
                                  .colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              leading: CircleAvatar(
                                backgroundColor: isIncome
                                    ? Colors.green.shade100
                                    : Colors.red.shade100,
                                radius: 18,
                                child: Icon(
                                  isIncome
                                      ? Icons.arrow_downward
                                      : Icons.arrow_upward,
                                  color: isIncome ? Colors.green : Colors.red,
                                  size: 16,
                                ),
                              ),
                              title: Text(tx.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              subtitle: Text(
                                  '${tx.category} • ${tx.date.substring(0, 10)}',
                                  style: const TextStyle(fontSize: 12)),
                              trailing: Text(
                                '${isIncome ? '+' : '-'}₱${_fmt(tx.amount)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: isIncome ? Colors.green : Colors.red,
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
