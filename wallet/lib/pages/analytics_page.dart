import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';

final _currencyFmt = NumberFormat('#,##0.00', 'en_PH');
String _fmt(double v) => _currencyFmt.format(v);

enum _Period { thisMonth, last6Months, allTime }

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => AnalyticsPageState();
}

class AnalyticsPageState extends State<AnalyticsPage> {
  final _db = DatabaseHelper.instance;

  _Period _period = _Period.thisMonth;
  bool _loading = true;

  double _totalIncome = 0;
  double _totalExpenses = 0;
  List<Map<String, dynamic>> _byCategory = [];
  List<Map<String, dynamic>> _monthly = []; // chronological, oldest -> newest

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> refresh() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);

    final now = DateTime.now();
    late final Future<double> incomeFuture;
    late final Future<double> expensesFuture;
    late final Future<List<Map<String, dynamic>>> categoryFuture;

    switch (_period) {
      case _Period.thisMonth:
        incomeFuture = _db.getMonthlyIncome(now.year, now.month);
        expensesFuture = _db.getMonthlyExpenses(now.year, now.month);
        categoryFuture = _db.getExpensesByCategoryForMonth(now.year, now.month);
        break;
      case _Period.last6Months:
      case _Period.allTime:
        incomeFuture = _db.getTotalIncome();
        expensesFuture = _db.getTotalExpenses();
        categoryFuture = _db.getExpensesByCategory();
        break;
    }

    final results = await Future.wait([
      incomeFuture,
      expensesFuture,
      categoryFuture,
      _db.getLast6MonthsSummary(),
    ]);

    if (!mounted) return;
    setState(() {
      _totalIncome = results[0] as double;
      _totalExpenses = results[1] as double;
      _byCategory = results[2] as List<Map<String, dynamic>>;
      _monthly = (results[3] as List<Map<String, dynamic>>).reversed.toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final net = _totalIncome - _totalExpenses;
    final savingsRate = _totalIncome > 0 ? (net / _totalIncome) : 0.0;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _PeriodSelector(
            period: _period,
            onChanged: (p) {
              setState(() => _period = p);
              _load();
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _SummaryCard(
                label: 'Income',
                amount: _totalIncome,
                color: Colors.green,
                icon: Icons.arrow_downward,
              ),
              const SizedBox(width: 10),
              _SummaryCard(
                label: 'Expenses',
                amount: _totalExpenses,
                color: Colors.red,
                icon: Icons.arrow_upward,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _NetBalanceCard(net: net, savingsRate: savingsRate),
          const SizedBox(height: 24),
          if (_monthly.isNotEmpty) ...[
            Text(
              '6-Month Trend',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _TrendChart(monthly: _monthly),
            const SizedBox(height: 24),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Expenses by Category',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (_byCategory.isNotEmpty)
                Text(
                  '${_byCategory.length} ${_byCategory.length == 1 ? 'category' : 'categories'}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_byCategory.isEmpty)
            const _EmptyCategories()
          else
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    for (int i = 0; i < _byCategory.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _CategoryRow(
                        rank: i,
                        category: _byCategory[i]['category'] as String,
                        total: (_byCategory[i]['total'] as num).toDouble(),
                        totalExpenses: _totalExpenses,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Period selector ──────────────────────────────────────────────────────────

class _PeriodSelector extends StatelessWidget {
  final _Period period;
  final ValueChanged<_Period> onChanged;

  const _PeriodSelector({required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const options = [
      (_Period.thisMonth, 'This Month'),
      (_Period.last6Months, 'Last 6 Months'),
      (_Period.allTime, 'All Time'),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: options.map((opt) {
          final selected = opt.$1 == period;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(opt.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color:
                      selected ? theme.colorScheme.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  opt.$2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Summary + net balance cards ──────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                radius: 18,
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '₱ ${_fmt(amount)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetBalanceCard extends StatelessWidget {
  final double net;
  final double savingsRate;

  const _NetBalanceCard({required this.net, required this.savingsRate});

  @override
  Widget build(BuildContext context) {
    final color = net >= 0 ? Colors.green : Colors.red;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Net Balance',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${net >= 0 ? '+' : '-'}₱ ${_fmt(net.abs())}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: color,
                  ),
                ),
              ],
            ),
            if (savingsRate != 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    net >= 0 ? 'Savings rate' : 'Overspent by',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  Text(
                    '${(savingsRate.abs() * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 6-month trend chart (no external chart package required) ───────────────

class _TrendChart extends StatelessWidget {
  final List<Map<String, dynamic>> monthly; // oldest -> newest

  const _TrendChart({required this.monthly});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxVal = monthly.fold<double>(0, (max, row) {
      final income = (row['income'] as num?)?.toDouble() ?? 0;
      final expenses = (row['expenses'] as num?)?.toDouble() ?? 0;
      return [max, income, expenses].reduce((a, b) => a > b ? a : b);
    });

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          children: [
            SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: monthly.map((row) {
                  final income = (row['income'] as num?)?.toDouble() ?? 0;
                  final expenses = (row['expenses'] as num?)?.toDouble() ?? 0;
                  final incomeH = maxVal > 0 ? (income / maxVal) * 120 : 0.0;
                  final expensesH =
                      maxVal > 0 ? (expenses / maxVal) * 120 : 0.0;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _bar(incomeH, Colors.green),
                              const SizedBox(width: 3),
                              _bar(expensesH, Colors.red),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _monthLabel(row['month'] as String),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: Colors.green, label: 'Income'),
                const SizedBox(width: 16),
                _LegendDot(color: Colors.red, label: 'Expenses'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(double height, Color color) {
    return Container(
      width: 10,
      height: height.clamp(2.0, 120.0),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  String _monthLabel(String ym) {
    final parts = ym.split('-');
    if (parts.length != 2) return ym;
    final month = int.tryParse(parts[1]) ?? 1;
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[(month - 1).clamp(0, 11)];
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

// ── Category breakdown ───────────────────────────────────────────────────────

const _categoryPalette = [
  Color(0xFF6366F1),
  Color(0xFFEC4899),
  Color(0xFFF59E0B),
  Color(0xFF10B981),
  Color(0xFF3B82F6),
  Color(0xFFEF4444),
  Color(0xFF8B5CF6),
  Color(0xFF14B8A6),
];

Color _colorForCategory(String name) =>
    _categoryPalette[name.hashCode.abs() % _categoryPalette.length];

class _CategoryRow extends StatelessWidget {
  final int rank;
  final String category;
  final double total;
  final double totalExpenses;

  const _CategoryRow({
    required this.rank,
    required this.category,
    required this.total,
    required this.totalExpenses,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = totalExpenses > 0 ? (total / totalExpenses) : 0.0;
    final color = _colorForCategory(category);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Text(
              category.isNotEmpty ? category[0].toUpperCase() : '?',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        category,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      '₱ ${_fmt(total)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 7,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${(pct * 100).toStringAsFixed(1)}% of expenses',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCategories extends StatelessWidget {
  const _EmptyCategories();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Icon(Icons.bar_chart_outlined,
                size: 36, color: theme.colorScheme.outline),
            const SizedBox(height: 8),
            Text(
              'No expense data for this period.',
              style: TextStyle(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
