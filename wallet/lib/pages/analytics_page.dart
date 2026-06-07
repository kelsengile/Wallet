import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';

final _currencyFmt = NumberFormat('#,##0.00', 'en_PH');
String _fmt(double v) => _currencyFmt.format(v);

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final _db = DatabaseHelper.instance;
  double _totalIncome = 0;
  double _totalExpenses = 0;
  List<Map<String, dynamic>> _byCategory = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final income = await _db.getTotalIncome();
    final expenses = await _db.getTotalExpenses();
    final byCategory = await _db.getExpensesByCategory();
    setState(() {
      _totalIncome = income;
      _totalExpenses = expenses;
      _byCategory = byCategory;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final net = _totalIncome - _totalExpenses;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Overview',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Net Balance',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '₱ ${_fmt(net)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: net >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Expenses by Category',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (_byCategory.isEmpty)
            const Text('No expense data yet.')
          else
            ..._byCategory.map((row) {
              final cat = row['category'] as String;
              final total = (row['total'] as num).toDouble();
              final pct = _totalExpenses > 0 ? (total / _totalExpenses) : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          cat,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '₱ ${_fmt(total)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 8,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Text(
                      '${(pct * 100).toStringAsFixed(1)}%',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

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
