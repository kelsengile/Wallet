import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../currency.dart';
import '../models/transaction_model.dart';
import '../models/category_model.dart';

final _currencyFmt = NumberFormat('#,##0.00', 'en_PH');
String _fmt(double v) => _currencyFmt.format(v);

// ── Filter modes (mirrored from history_page) ─────────────────────────────────
enum _FilterMode { daily, weekly, monthly, yearly, allTime, custom }

// ── Category palette ──────────────────────────────────────────────────────────
// 16 visually distinct colors that cycle when there are more categories.
const _kCategoryColors = [
  Color(0xFF6366F1), // indigo
  Color(0xFFF59E0B), // amber
  Color(0xFF10B981), // emerald
  Color(0xFFF87171), // red
  Color(0xFF3B82F6), // blue
  Color(0xFFA855F7), // purple
  Color(0xFFEC4899), // pink
  Color(0xFF14B8A6), // teal
  Color(0xFFF97316), // orange
  Color(0xFF84CC16), // lime
  Color(0xFF06B6D4), // cyan
  Color(0xFFEF4444), // crimson
  Color(0xFF8B5CF6), // violet
  Color(0xFF22C55E), // green
  Color(0xFFEAB308), // yellow
  Color(0xFF64748B), // slate
];

// ── Page ──────────────────────────────────────────────────────────────────────

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => AnalyticsPageState();
}

class AnalyticsPageState extends State<AnalyticsPage> {
  final _db = DatabaseHelper.instance;

  List<WalletTransaction> _transactions = [];
  List<WalletCategory> _txCategories = [];
  bool _loading = true;

  // ── Filter state (same logic as history_page) ─────────────────────────────
  _FilterMode _filterMode = _FilterMode.monthly;
  DateTime _anchor = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _customStart;
  DateTime? _customEnd;

  // ── Which data series the line chart shows ────────────────────────────────
  // true = expenses, false = income
  bool _showExpenses = true;

  // ── Period helpers ────────────────────────────────────────────────────────

  DateTime get _periodStart {
    final now = _anchor;
    switch (_filterMode) {
      case _FilterMode.daily:
        return DateTime(now.year, now.month, now.day);
      case _FilterMode.weekly:
        return now.subtract(Duration(days: now.weekday - 1));
      case _FilterMode.monthly:
        return DateTime(now.year, now.month);
      case _FilterMode.yearly:
        return DateTime(now.year);
      case _FilterMode.allTime:
        return DateTime(2000);
      case _FilterMode.custom:
        return _customStart ?? DateTime(2000);
    }
  }

  DateTime get _periodEnd {
    switch (_filterMode) {
      case _FilterMode.daily:
        return _periodStart.add(const Duration(days: 1));
      case _FilterMode.weekly:
        return _periodStart.add(const Duration(days: 7));
      case _FilterMode.monthly:
        final s = _periodStart;
        return DateTime(s.year, s.month + 1);
      case _FilterMode.yearly:
        return DateTime(_periodStart.year + 1);
      case _FilterMode.allTime:
        return DateTime(2100);
      case _FilterMode.custom:
        final end = _customEnd ?? DateTime.now();
        return DateTime(end.year, end.month, end.day + 1);
    }
  }

  String get _periodLabel {
    switch (_filterMode) {
      case _FilterMode.allTime:
        return 'All Time';
      case _FilterMode.custom:
        if (_customStart == null && _customEnd == null) return 'Custom Range';
        final fmt = DateFormat('MMM d, yyyy');
        final s = _customStart != null ? fmt.format(_customStart!) : '…';
        final e = _customEnd != null ? fmt.format(_customEnd!) : '…';
        return '$s – $e';
      default:
        final s = _periodStart;
        switch (_filterMode) {
          case _FilterMode.daily:
            return DateFormat('EEE, MMM d, yyyy').format(s);
          case _FilterMode.weekly:
            final e = _periodEnd.subtract(const Duration(days: 1));
            final sStr = DateFormat('MMM d').format(s);
            final eStr = DateFormat('MMM d, yyyy').format(e);
            return '$sStr – $eStr';
          case _FilterMode.monthly:
            return DateFormat('MMMM yyyy').format(s);
          case _FilterMode.yearly:
            return s.year.toString();
          default:
            return '';
        }
    }
  }

  bool get _canGoForward {
    if (_filterMode == _FilterMode.allTime || _filterMode == _FilterMode.custom)
      return false;
    final now = DateTime.now();
    return _periodEnd.isBefore(DateTime(now.year, now.month, now.day + 1));
  }

  void _goBack() {
    if (_filterMode == _FilterMode.allTime || _filterMode == _FilterMode.custom)
      return;
    setState(() {
      switch (_filterMode) {
        case _FilterMode.daily:
          _anchor = _anchor.subtract(const Duration(days: 1));
          break;
        case _FilterMode.weekly:
          _anchor = _anchor.subtract(const Duration(days: 7));
          break;
        case _FilterMode.monthly:
          _anchor = DateTime(_anchor.year, _anchor.month - 1);
          break;
        case _FilterMode.yearly:
          _anchor = DateTime(_anchor.year - 1);
          break;
        default:
          break;
      }
    });
  }

  void _goForward() {
    if (!_canGoForward) return;
    setState(() {
      switch (_filterMode) {
        case _FilterMode.daily:
          _anchor = _anchor.add(const Duration(days: 1));
          break;
        case _FilterMode.weekly:
          _anchor = _anchor.add(const Duration(days: 7));
          break;
        case _FilterMode.monthly:
          _anchor = DateTime(_anchor.year, _anchor.month + 1);
          break;
        case _FilterMode.yearly:
          _anchor = DateTime(_anchor.year + 1);
          break;
        default:
          break;
      }
    });
  }

  // ── Filtered transactions ─────────────────────────────────────────────────

  List<WalletTransaction> get _filtered {
    final start = _periodStart;
    final end = _periodEnd;
    return _transactions.where((tx) {
      final d = DateTime.tryParse(tx.date);
      return d != null && !d.isBefore(start) && d.isBefore(end);
    }).toList();
  }

  double get _periodIncome => _filtered
      .where((tx) => tx.type == 'income')
      .fold(0.0, (sum, tx) => sum + tx.amount);

  double get _periodExpenses => _filtered
      .where((tx) => tx.type == 'expense')
      .fold(0.0, (sum, tx) => sum + tx.amount);

  double get _periodNet => _periodIncome - _periodExpenses;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> refresh() => _load();

  Future<void> _load() async {
    final results = await Future.wait([
      _db.getAllTransactions(),
      _db.getCategoryRegistry(),
    ]);
    final txs = results[0] as List<WalletTransaction>;
    final registry = results[1] as CategoryRegistry;

    if (!mounted) return;
    setState(() {
      _transactions = txs;
      _txCategories = registry.selectableTransactionCategories;
      _loading = false;
    });
  }

  // ── Period picker ─────────────────────────────────────────────────────────

  Future<void> _pickPeriod() async {
    final result = await showDialog<
        ({
          _FilterMode mode,
          DateTime anchor,
          DateTime? customStart,
          DateTime? customEnd
        })>(
      context: context,
      builder: (ctx) => _PeriodPickerDialog(
        currentMode: _filterMode,
        currentAnchor: _anchor,
        customStart: _customStart,
        customEnd: _customEnd,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _filterMode = result.mode;
      _anchor = result.anchor;
      _customStart = result.customStart;
      _customEnd = result.customEnd;
    });
  }

  // ── Line chart data ───────────────────────────────────────────────────────

  /// Returns a list of (label, value) pairs bucketed for the current filter.
  List<({String label, double value})> _buildChartData() {
    final type = _showExpenses ? 'expense' : 'income';
    final relevant = _filtered.where((tx) => tx.type == type).toList();

    if (relevant.isEmpty) return [];

    switch (_filterMode) {
      case _FilterMode.daily:
        // Bucket by hour (0–23)
        final buckets = List.filled(24, 0.0);
        for (final tx in relevant) {
          final d = DateTime.tryParse(tx.date);
          if (d != null) buckets[d.hour] += tx.amount;
        }
        return List.generate(
            24,
            (i) =>
                (label: '${i.toString().padLeft(2, '0')}h', value: buckets[i]));

      case _FilterMode.weekly:
        // Bucket by weekday (Mon–Sun)
        final buckets = List.filled(7, 0.0);
        final weekStart = _periodStart;
        for (final tx in relevant) {
          final d = DateTime.tryParse(tx.date);
          if (d != null) {
            final idx = d.difference(weekStart).inDays.clamp(0, 6);
            buckets[idx] += tx.amount;
          }
        }
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return List.generate(7, (i) => (label: days[i], value: buckets[i]));

      case _FilterMode.monthly:
        // Bucket by day of month
        final daysInMonth = DateTime(_anchor.year, _anchor.month + 1, 0).day;
        final buckets = List.filled(daysInMonth, 0.0);
        for (final tx in relevant) {
          final d = DateTime.tryParse(tx.date);
          if (d != null) {
            final idx = (d.day - 1).clamp(0, daysInMonth - 1);
            buckets[idx] += tx.amount;
          }
        }
        return List.generate(
            daysInMonth, (i) => (label: '${i + 1}', value: buckets[i]));

      case _FilterMode.yearly:
        // Bucket by month
        final buckets = List.filled(12, 0.0);
        for (final tx in relevant) {
          final d = DateTime.tryParse(tx.date);
          if (d != null) buckets[(d.month - 1).clamp(0, 11)] += tx.amount;
        }
        const months = [
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
          'Dec'
        ];
        return List.generate(12, (i) => (label: months[i], value: buckets[i]));

      case _FilterMode.allTime:
      case _FilterMode.custom:
        // Bucket by year
        if (relevant.isEmpty) return [];
        int minYear = relevant
            .map((tx) => DateTime.tryParse(tx.date)?.year ?? 9999)
            .reduce(math.min);
        int maxYear = relevant
            .map((tx) => DateTime.tryParse(tx.date)?.year ?? 0)
            .reduce(math.max);
        if (minYear == maxYear) {
          // Fall back to monthly within that year
          final buckets = List.filled(12, 0.0);
          for (final tx in relevant) {
            final d = DateTime.tryParse(tx.date);
            if (d != null) buckets[(d.month - 1).clamp(0, 11)] += tx.amount;
          }
          const months = [
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
            'Dec'
          ];
          return List.generate(
              12, (i) => (label: months[i], value: buckets[i]));
        }
        final years = List.generate(maxYear - minYear + 1, (i) => minYear + i);
        final buckets = <int, double>{};
        for (final y in years) buckets[y] = 0.0;
        for (final tx in relevant) {
          final d = DateTime.tryParse(tx.date);
          if (d != null && buckets.containsKey(d.year)) {
            buckets[d.year] = (buckets[d.year] ?? 0) + tx.amount;
          }
        }
        return years.map((y) => (label: '$y', value: buckets[y]!)).toList();
    }
  }

  // ── By-category data ──────────────────────────────────────────────────────

  List<({String category, double amount, Color color})> _buildCategoryData(
      String type) {
    final relevant = _filtered.where((tx) => tx.type == type).toList();

    final Map<String, double> totals = {};
    for (final tx in relevant) {
      totals[tx.category] = (totals[tx.category] ?? 0) + tx.amount;
    }

    // Sort by amount descending
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Assign colors: first try to keep order consistent with _txCategories list
    final catOrder = _txCategories.map((c) => c.name).toList();

    return sorted.asMap().entries.map((e) {
      final idx = e.key;
      final entry = e.value;
      // Look up position in category registry for stable color assignment
      final catIdx = catOrder.indexOf(entry.key);
      final colorIdx = (catIdx >= 0 ? catIdx : idx) % _kCategoryColors.length;
      return (
        category: entry.key,
        amount: entry.value,
        color: _kCategoryColors[colorIdx],
      );
    }).toList();
  }

  // ── Category legend builder ───────────────────────────────────────────────

  List<Widget> _buildCategoryLegend(
    List<({String category, double amount, Color color})> data,
    ThemeData theme,
  ) {
    final total = data.fold(0.0, (sum, item) => sum + item.amount);
    return data.map((c) {
      final pct = total > 0 ? (c.amount / total * 100) : 0.0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: c.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        c.category,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${pct.toStringAsFixed(1)}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: total > 0 ? c.amount / total : 0,
                            backgroundColor: c.color.withValues(alpha: 0.15),
                            valueColor: AlwaysStoppedAnimation(c.color),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${currencySymbolNotifier.value}${_fmt(c.amount)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // ignore: unused_local_variable
    final topPadding = MediaQuery.paddingOf(context).top;
    final chartData = _buildChartData();
    final expenseCategoryData = _buildCategoryData('expense');
    final incomeCategoryData = _buildCategoryData('income');
    final income = _periodIncome;
    final expenses = _periodExpenses;
    final net = _periodNet;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Overview title + filter button row ───────────────────────
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Overview',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Filter',
                    onPressed: _pickPeriod,
                    icon: _FunnelIcon(color: theme.colorScheme.onSurface),
                  ),
                ],
              ),

              // ── Period navigator ─────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Opacity(
                    opacity: (_filterMode == _FilterMode.allTime ||
                            _filterMode == _FilterMode.custom)
                        ? 0.0
                        : 1.0,
                    child: IgnorePointer(
                      ignoring: _filterMode == _FilterMode.allTime ||
                          _filterMode == _FilterMode.custom,
                      child: IconButton(
                        icon: Icon(Icons.chevron_left,
                            color: theme.colorScheme.onSurface),
                        onPressed: _goBack,
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickPeriod,
                      child: Center(
                        child: Text(
                          _periodLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: (_filterMode == _FilterMode.allTime ||
                            _filterMode == _FilterMode.custom)
                        ? 0.0
                        : 1.0,
                    child: IgnorePointer(
                      ignoring: _filterMode == _FilterMode.allTime ||
                          _filterMode == _FilterMode.custom,
                      child: IconButton(
                        icon: Icon(
                          Icons.chevron_right,
                          color: _canGoForward
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.25),
                        ),
                        onPressed: _canGoForward ? _goForward : null,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 4),

              // ── Income / Expense / Net toggle buttons ────────────────────
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showExpenses = false),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        decoration: BoxDecoration(
                          color: !_showExpenses
                              ? const Color(0xFF4ADE80).withValues(alpha: 0.12)
                              : theme.colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: !_showExpenses
                                ? const Color(0xFF4ADE80)
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.arrow_upward_rounded,
                                    color: Color(0xFF4ADE80), size: 13),
                                const SizedBox(width: 4),
                                Text(
                                  'Income',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${currencySymbolNotifier.value}${_fmt(income)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showExpenses = true),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        decoration: BoxDecoration(
                          color: _showExpenses
                              ? const Color(0xFFF87171).withValues(alpha: 0.12)
                              : theme.colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _showExpenses
                                ? const Color(0xFFF87171)
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.arrow_downward_rounded,
                                    color: Color(0xFFF87171), size: 13),
                                const SizedBox(width: 4),
                                Text(
                                  'Expenses',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${currencySymbolNotifier.value}${_fmt(expenses)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.account_balance_wallet_outlined,
                                  color: net >= 0
                                      ? const Color(0xFF4ADE80)
                                      : const Color(0xFFF87171),
                                  size: 13),
                              const SizedBox(width: 4),
                              Text(
                                'Net',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${currencySymbolNotifier.value}${_fmt(net)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── Scrollable content ───────────────────────────────────────────────
        Expanded(
          child: ColoredBox(
            color: Colors.white,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Line chart section ─────────────────────────────────────
                  _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Toggle header
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _showExpenses ? 'Expenses' : 'Income',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        chartData.isEmpty
                            ? const _EmptyChart()
                            : _LineChart(
                                data: chartData,
                                color: _showExpenses
                                    ? const Color(0xFFF87171)
                                    : const Color(0xFF4ADE80),
                              ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── By category section ────────────────────────────────────
                  _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'By Category',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Builder(builder: (_) {
                          final categoryData = _showExpenses
                              ? expenseCategoryData
                              : incomeCategoryData;
                          final isExpense = _showExpenses;

                          if (categoryData.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text(
                                  'No category data for this period.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isExpense
                                        ? Icons.arrow_downward_rounded
                                        : Icons.arrow_upward_rounded,
                                    color: isExpense
                                        ? const Color(0xFFF87171)
                                        : const Color(0xFF4ADE80),
                                    size: 14,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isExpense ? 'Expenses' : 'Income',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: isExpense
                                          ? const Color(0xFFF87171)
                                          : const Color(0xFF4ADE80),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _PieChart(data: categoryData),
                              const SizedBox(height: 12),
                              ..._buildCategoryLegend(categoryData, theme),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

// ── Toggle chip ───────────────────────────────────────────────────────────────

// ignore: unused_element
class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.grey.withValues(alpha: 0.3),
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? color : Colors.grey,
          ),
        ),
      ),
    );
  }
}

// ── Empty chart placeholder ───────────────────────────────────────────────────

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 120,
      child: Center(
        child: Text(
          'No data for this period.',
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }
}

// ── Line chart ────────────────────────────────────────────────────────────────

// Layout constants shared between the widget (hit-testing) and painter (drawing).
const double _kChartLabelH = 20.0;
const double _kChartLeftPad = 48.0;
const double _kChartRightPad = 8.0;
const double _kChartTopPad = 10.0;

class _LineChart extends StatefulWidget {
  final List<({String label, double value})> data;
  final Color color;

  const _LineChart({required this.data, required this.color});

  @override
  State<_LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<_LineChart> {
  int? _selectedIndex;

  static int _xLabelInterval(int count) {
    if (count <= 12) return 1;
    if (count <= 24) return 3;
    return (count / 8).ceil();
  }

  /// Returns the dot x-positions for a given render [size], mirroring the
  /// painter's layout so tap hit-testing lines up exactly.
  List<double> _xPositions(Size size) {
    final chartW = size.width - _kChartLeftPad - _kChartRightPad;
    final n = widget.data.length;
    return List.generate(n, (i) {
      return _kChartLeftPad + (n == 1 ? chartW / 2 : i / (n - 1) * chartW);
    });
  }

  void _onTapUp(TapUpDetails details, Size size) {
    if (widget.data.length > 31) return; // dots not drawn for dense data
    final tap = details.localPosition;
    final xs = _xPositions(size);
    const hitRadius = 18.0; // generous touch target

    int? best;
    double bestDist = double.infinity;
    for (int i = 0; i < xs.length; i++) {
      if (widget.data[i].value == 0) continue; // no dot drawn for zero
      final dist = (tap.dx - xs[i]).abs();
      if (dist < hitRadius && dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }

    setState(() => _selectedIndex = (best == _selectedIndex) ? null : best);
  }

  @override
  void didUpdateWidget(_LineChart old) {
    super.didUpdateWidget(old);
    // Clear selection when data changes (period switch etc.)
    if (old.data != widget.data) _selectedIndex = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showEvery = _xLabelInterval(widget.data.length);

    return SizedBox(
      height: 180,
      child: LayoutBuilder(builder: (context, constraints) {
        final size = Size(constraints.maxWidth, 180);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _onTapUp(d, size),
          child: CustomPaint(
            painter: _LineChartPainter(
              data: widget.data,
              color: widget.color,
              gridColor: theme.colorScheme.outline.withValues(alpha: 0.12),
              labelColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              showEvery: showEvery,
              selectedIndex: _selectedIndex,
              currencySymbol: currencySymbolNotifier.value,
            ),
            child: const SizedBox.expand(),
          ),
        );
      }),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<({String label, double value})> data;
  final Color color;
  final Color gridColor;
  final Color labelColor;
  final int showEvery;
  final int? selectedIndex;
  final String currencySymbol;

  const _LineChartPainter({
    required this.data,
    required this.color,
    required this.gridColor,
    required this.labelColor,
    required this.showEvery,
    required this.selectedIndex,
    required this.currencySymbol,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = _kChartLabelH;
    const leftPad = _kChartLeftPad;
    const rightPad = _kChartRightPad;
    const topPad = _kChartTopPad;
    final chartH = size.height - labelH - topPad;
    final chartW = size.width - leftPad - rightPad;

    final maxVal = data.fold(0.0, (m, d) => math.max(m, d.value));
    final safeMax = maxVal == 0 ? 1.0 : maxVal;

    // Grid lines (4 horizontal)
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    final labelStyle = TextStyle(
      fontSize: 9,
      color: labelColor,
      fontWeight: FontWeight.w500,
    );

    const gridCount = 4;
    for (int i = 0; i <= gridCount; i++) {
      final y = topPad + chartH - (i / gridCount) * chartH;
      canvas.drawLine(
          Offset(leftPad, y), Offset(leftPad + chartW, y), gridPaint);

      // Y-axis label
      final val = (i / gridCount) * safeMax;
      final tp = TextPainter(
        text: TextSpan(text: _shortAmount(val), style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    if (data.isEmpty) return;

    // Compute x positions
    final xPositions = List.generate(data.length, (i) {
      return leftPad +
          (data.length == 1 ? chartW / 2 : i / (data.length - 1) * chartW);
    });

    // Compute y positions
    final yPositions = data
        .map((d) => topPad + chartH - (d.value / safeMax) * chartH)
        .toList();

    // Fill area under line
    final fillPath = Path();
    fillPath.moveTo(xPositions.first, topPad + chartH);
    for (int i = 0; i < data.length; i++) {
      fillPath.lineTo(xPositions[i], yPositions[i]);
    }
    fillPath.lineTo(xPositions.last, topPad + chartH);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.25),
          color.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, topPad, size.width, chartH));
    canvas.drawPath(fillPath, fillPaint);

    // Line
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final linePath = Path();
    linePath.moveTo(xPositions.first, yPositions.first);
    for (int i = 1; i < data.length; i++) {
      linePath.lineTo(xPositions[i], yPositions[i]);
    }
    canvas.drawPath(linePath, linePaint);

    // Dots — only draw if not too many points
    if (data.length <= 31) {
      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      final dotBg = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      for (int i = 0; i < data.length; i++) {
        if (data[i].value > 0) {
          final isSelected = i == selectedIndex;
          final outerR = isSelected ? 7.0 : 4.0;
          final innerR = isSelected ? 5.0 : 3.0;
          canvas.drawCircle(
              Offset(xPositions[i], yPositions[i]), outerR, dotBg);
          canvas.drawCircle(Offset(xPositions[i], yPositions[i]), innerR,
              dotPaint..color = isSelected ? color : color);
          // Ring accent for selected dot
          if (isSelected) {
            final ringPaint = Paint()
              ..color = color.withValues(alpha: 0.35)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0;
            canvas.drawCircle(
                Offset(xPositions[i], yPositions[i]), 10, ringPaint);
          }
        }
      }
    }

    // X-axis labels
    for (int i = 0; i < data.length; i++) {
      if (i % showEvery != 0) continue;
      final tp = TextPainter(
        text: TextSpan(text: data[i].label, style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(xPositions[i] - tp.width / 2, topPad + chartH + 4),
      );
    }

    // Tooltip for selected dot
    if (selectedIndex != null &&
        selectedIndex! < data.length &&
        data[selectedIndex!].value > 0) {
      _drawTooltip(
        canvas,
        size,
        xPositions[selectedIndex!],
        yPositions[selectedIndex!],
        data[selectedIndex!].label,
        data[selectedIndex!].value,
        chartW,
        leftPad,
        rightPad,
        topPad,
      );
    }
  }

  void _drawTooltip(
    Canvas canvas,
    Size size,
    double dotX,
    double dotY,
    String label,
    double value,
    double chartW,
    double leftPad,
    double rightPad,
    double topPad,
  ) {
    // ignore: unused_local_variable
    const tooltipH = 36.0;
    const tooltipPadH = 10.0;
    const tooltipPadV = 6.0;
    const arrowH = 6.0;
    const cornerR = 6.0;

    final amountText = '$currencySymbol${_fmt(value)}';
    final amountStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    );
    final labelStyle2 = TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w500,
      color: Colors.white.withValues(alpha: 0.75),
    );

    final amountTp = TextPainter(
      text: TextSpan(text: amountText, style: amountStyle),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final labelTp = TextPainter(
      text: TextSpan(text: label, style: labelStyle2),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    final contentW = math.max(amountTp.width, labelTp.width);
    final tooltipW = contentW + tooltipPadH * 2;
    final tooltipActualH =
        amountTp.height + labelTp.height + tooltipPadV * 2 + 2;

    // Position tooltip above the dot; clamp horizontally to chart bounds
    double tipX = dotX - tooltipW / 2;
    tipX = tipX.clamp(leftPad, size.width - rightPad - tooltipW);

    // Arrow tip points at the dot; tooltip sits above it
    const dotClearance = 14.0;
    double tipY = dotY - dotClearance - tooltipActualH - arrowH;
    // If it would go above the chart area, flip below the dot
    final flipBelow = tipY < topPad - 4;
    if (flipBelow) tipY = dotY + dotClearance;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(tipX, tipY, tooltipW, tooltipActualH),
      const Radius.circular(cornerR),
    );

    // Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(tipX, tipY + 2, tooltipW, tooltipActualH),
        const Radius.circular(cornerR),
      ),
      shadowPaint,
    );

    // Background
    canvas.drawRRect(rect, Paint()..color = color);

    // Arrow
    final arrowPath = Path();
    final arrowMidX = dotX.clamp(tipX + cornerR, tipX + tooltipW - cornerR);
    if (!flipBelow) {
      // Arrow points down toward the dot
      arrowPath.moveTo(arrowMidX - 5, tipY + tooltipActualH);
      arrowPath.lineTo(arrowMidX, tipY + tooltipActualH + arrowH);
      arrowPath.lineTo(arrowMidX + 5, tipY + tooltipActualH);
    } else {
      // Arrow points up toward the dot
      arrowPath.moveTo(arrowMidX - 5, tipY);
      arrowPath.lineTo(arrowMidX, tipY - arrowH);
      arrowPath.lineTo(arrowMidX + 5, tipY);
    }
    arrowPath.close();
    canvas.drawPath(arrowPath, Paint()..color = color);

    // Text
    final textX = tipX + tooltipPadH;
    amountTp.paint(canvas, Offset(textX, tipY + tooltipPadV));
    labelTp.paint(
        canvas, Offset(textX, tipY + tooltipPadV + amountTp.height + 2));
  }

  String _shortAmount(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  String _fmt(double v) => NumberFormat('#,##0.00', 'en_PH').format(v);

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.data != data ||
      old.color != color ||
      old.selectedIndex != selectedIndex ||
      old.currencySymbol != currencySymbol;
}

// ── Pie chart ─────────────────────────────────────────────────────────────────

class _PieChart extends StatelessWidget {
  final List<({String category, double amount, Color color})> data;

  const _PieChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = data.fold(0.0, (s, d) => s + d.amount);
    return SizedBox(
      height: 200,
      child: CustomPaint(
        painter: _PieChartPainter(data: data, total: total),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<({String category, double amount, Color color})> data;
  final double total;

  const _PieChartPainter({required this.data, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    const innerRadius = 0.52; // donut hole ratio

    double startAngle = -math.pi / 2; // start at top

    for (final slice in data) {
      // Clamp to just under a full rotation: canvas.arcTo treats a sweep of
      // exactly 2π as a no-op, so a single-category chart would render blank.
      final sweepAngle =
          ((slice.amount / total) * 2 * math.pi).clamp(0.0, math.pi * 1.9999);

      final paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.fill;

      // Outer arc path
      final path = Path();
      final outerRect = Rect.fromCircle(center: center, radius: radius);
      final innerRect =
          Rect.fromCircle(center: center, radius: radius * innerRadius);

      path.moveTo(
        center.dx + radius * innerRadius * math.cos(startAngle),
        center.dy + radius * innerRadius * math.sin(startAngle),
      );
      path.arcTo(outerRect, startAngle, sweepAngle, false);
      path.arcTo(innerRect, startAngle + sweepAngle, -sweepAngle, false);
      path.close();

      canvas.drawPath(path, paint);

      // Thin gap between slices — only needed when there are multiple slices
      if (data.length > 1) {
        final gapPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        canvas.drawPath(path, gapPaint);
      }

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(_PieChartPainter old) =>
      old.data != data || old.total != total;
}

// ── Summary tile (matches history page _AnalyticsTile) ────────────────────────

// ignore: unused_element
class _SummaryTile extends StatelessWidget {
  final IconData icon;
  final double amount;
  final Color color;
  final Color textColor;

  const _SummaryTile({
    required this.icon,
    required this.amount,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${currencySymbolNotifier.value}${_fmt(amount)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Funnel / filter icon (copied from history_page) ───────────────────────────

class _FunnelIcon extends StatelessWidget {
  final Color color;
  const _FunnelIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(20, 20),
      painter: _FunnelPainter(color: color),
    );
  }
}

class _FunnelPainter extends CustomPainter {
  final Color color;
  _FunnelPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    final w = size.width;
    final h = size.height;
    for (final line in [
      (0.0, w, h * 0.22),
      (w * 0.18, w * 0.82, h * 0.50),
      (w * 0.36, w * 0.64, h * 0.78),
    ]) {
      canvas.drawLine(
          Offset(line.$1, line.$3), Offset(line.$2, line.$3), paint);
    }
  }

  @override
  bool shouldRepaint(_FunnelPainter old) => old.color != color;
}

// ── Period picker dialog (mirrored from history_page) ─────────────────────────

class _PeriodPickerDialog extends StatefulWidget {
  final _FilterMode currentMode;
  final DateTime currentAnchor;
  final DateTime? customStart;
  final DateTime? customEnd;

  const _PeriodPickerDialog({
    required this.currentMode,
    required this.currentAnchor,
    this.customStart,
    this.customEnd,
  });

  @override
  State<_PeriodPickerDialog> createState() => _PeriodPickerDialogState();
}

class _PeriodPickerDialogState extends State<_PeriodPickerDialog> {
  late _FilterMode _mode;
  late DateTime _anchor;
  late DateTime _calendarMonth;
  DateTime? _customStart;
  DateTime? _customEnd;

  static const _modes = [
    (_FilterMode.daily, 'Day'),
    (_FilterMode.weekly, 'Week'),
    (_FilterMode.monthly, 'Month'),
    (_FilterMode.yearly, 'Year'),
    (_FilterMode.allTime, 'All'),
    (_FilterMode.custom, 'Custom'),
  ];

  @override
  void initState() {
    super.initState();
    _mode = widget.currentMode;
    _anchor = widget.currentAnchor;
    _calendarMonth = DateTime(_anchor.year, _anchor.month);
    _customStart = widget.customStart;
    _customEnd = widget.customEnd;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isInSameWeek(DateTime d) {
    final weekStart = _anchor.subtract(Duration(days: _anchor.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(
            DateTime(weekStart.year, weekStart.month, weekStart.day)) &&
        !day.isAfter(DateTime(weekEnd.year, weekEnd.month, weekEnd.day));
  }

  bool _isHighlighted(DateTime d) {
    switch (_mode) {
      case _FilterMode.daily:
        return _isSameDay(d, _anchor);
      case _FilterMode.weekly:
        return _isInSameWeek(d);
      case _FilterMode.monthly:
        return d.year == _anchor.year && d.month == _anchor.month;
      case _FilterMode.yearly:
        return d.year == _anchor.year;
      case _FilterMode.allTime:
        return false;
      case _FilterMode.custom:
        if (_customStart == null && _customEnd == null) return false;
        final day = DateTime(d.year, d.month, d.day);
        final start = _customStart != null
            ? DateTime(
                _customStart!.year, _customStart!.month, _customStart!.day)
            : null;
        final end = _customEnd != null
            ? DateTime(_customEnd!.year, _customEnd!.month, _customEnd!.day)
            : null;
        if (start != null && end != null) {
          return !day.isBefore(start) && !day.isAfter(end);
        } else if (start != null) {
          return _isSameDay(day, start);
        } else if (end != null) {
          return _isSameDay(day, end);
        }
        return false;
    }
  }

  void _onDayTapped(DateTime d) {
    setState(() {
      switch (_mode) {
        case _FilterMode.daily:
          _anchor = d;
          break;
        case _FilterMode.weekly:
          _anchor = d;
          break;
        case _FilterMode.monthly:
          _anchor = DateTime(d.year, d.month);
          break;
        case _FilterMode.yearly:
          _anchor = DateTime(d.year);
          break;
        case _FilterMode.custom:
          if (_customStart == null ||
              (_customStart != null && _customEnd != null)) {
            _customStart = d;
            _customEnd = null;
          } else {
            if (d.isBefore(_customStart!)) {
              _customEnd = _customStart;
              _customStart = d;
            } else {
              _customEnd = d;
            }
          }
          break;
        default:
          break;
      }
    });
  }

  List<DateTime?> _calendarDays() {
    final firstDay = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final daysInMonth =
        DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    final startWeekday = firstDay.weekday; // 1=Mon, 7=Sun
    final result = <DateTime?>[];
    for (int i = 1; i < startWeekday; i++) result.add(null);
    for (int d = 1; d <= daysInMonth; d++) {
      result.add(DateTime(_calendarMonth.year, _calendarMonth.month, d));
    }
    return result;
  }

  String get _selectedLabel {
    switch (_mode) {
      case _FilterMode.allTime:
        return 'All Time';
      case _FilterMode.custom:
        if (_customStart == null && _customEnd == null)
          return 'Select start date';
        final fmt = DateFormat('MMM d, yyyy');
        if (_customStart != null && _customEnd == null) {
          return 'From ${fmt.format(_customStart!)} – select end';
        }
        return '${fmt.format(_customStart!)} – ${fmt.format(_customEnd!)}';
      case _FilterMode.daily:
        return DateFormat('EEE, MMM d, yyyy').format(_anchor);
      case _FilterMode.weekly:
        final wStart = _anchor.subtract(Duration(days: _anchor.weekday - 1));
        final wEnd = wStart.add(const Duration(days: 6));
        return '${DateFormat('MMM d').format(wStart)} – ${DateFormat('MMM d, yyyy').format(wEnd)}';
      case _FilterMode.monthly:
        return DateFormat('MMMM yyyy').format(_anchor);
      case _FilterMode.yearly:
        return '${_anchor.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final now = DateTime.now();

    final showCalendar =
        _mode != _FilterMode.allTime && _mode != _FilterMode.yearly;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mode tabs
            Row(
              children: _modes.map((entry) {
                final mode = entry.$1;
                final label = entry.$2;
                final selected = _mode == mode;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _mode = mode;
                      if (mode == _FilterMode.allTime ||
                          mode == _FilterMode.custom) {
                        // do nothing to anchor
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: selected
                            ? primary.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected
                                ? primary
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            if (_mode == _FilterMode.allTime) ...[
              const Text('Showing all transactions'),
            ] else ...[
              // Calendar month navigator (only for non-yearly)
              if (showCalendar) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => setState(() {
                        _calendarMonth = DateTime(
                          _calendarMonth.year,
                          _calendarMonth.month - 1,
                        );
                      }),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _mode = _FilterMode.monthly),
                      child: Text(
                        DateFormat('MMMM yyyy').format(_calendarMonth),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: DateTime(
                                  _calendarMonth.year, _calendarMonth.month + 1)
                              .isAfter(DateTime(now.year, now.month))
                          ? null
                          : () => setState(() {
                                _calendarMonth = DateTime(
                                  _calendarMonth.year,
                                  _calendarMonth.month + 1,
                                );
                              }),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Weekday headers
                Row(
                  children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((d) {
                    return Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 4),
                // Day grid
                Builder(builder: (_) {
                  final days = _calendarDays();
                  while (days.length % 7 != 0) days.add(null);
                  final rows = days.length ~/ 7;
                  return Column(
                    children: List.generate(rows, (row) {
                      return Row(
                        children: List.generate(7, (col) {
                          final d = days[row * 7 + col];
                          if (d == null) {
                            return const Expanded(child: SizedBox(height: 36));
                          }
                          final isFuture = d.isAfter(now);
                          final highlighted = !isFuture && _isHighlighted(d);
                          final isToday = _isSameDay(d, now);

                          Color? bgColor;
                          Color textColor = theme.colorScheme.onSurface;
                          if (highlighted) {
                            bgColor = primary.withValues(alpha: 0.15);
                            textColor = primary;
                          } else if (isToday) {
                            textColor = primary;
                          }
                          if (isFuture) {
                            textColor = theme.colorScheme.onSurface
                                .withValues(alpha: 0.25);
                          }

                          return Expanded(
                            child: GestureDetector(
                              onTap: isFuture ? null : () => _onDayTapped(d),
                              child: Container(
                                height: 36,
                                decoration: BoxDecoration(
                                  color: bgColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    '${d.day}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: highlighted || isToday
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: textColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      );
                    }),
                  );
                }),
              ] else ...[
                // Yearly: decade grid
                Builder(builder: (_) {
                  final decadeStart = (_anchor.year ~/ 10) * 10;
                  const rowSizes = [4, 4, 2];

                  Widget yearCell(int yr) {
                    final isFuture = yr > now.year;
                    final isSelected = _anchor.year == yr;
                    final isCurrentYear = yr == now.year;
                    final Color textColor = isFuture
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.25)
                        : isSelected
                            ? primary
                            : isCurrentYear
                                ? primary
                                : theme.colorScheme.onSurface;
                    return Expanded(
                      child: GestureDetector(
                        onTap: isFuture
                            ? null
                            : () => setState(() => _anchor = DateTime(yr)),
                        child: Container(
                          height: 56,
                          margin: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? primary.withValues(alpha: 0.15)
                                : null,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              '$yr',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected || isCurrentYear
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: textColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  int offset = 0;
                  return Column(
                    children: rowSizes.map((count) {
                      final start = offset;
                      offset += count;
                      if (count < 4) {
                        return Row(
                          children: [
                            const Expanded(child: SizedBox()),
                            ...List.generate(count,
                                (i) => yearCell(decadeStart + start + i)),
                            const Expanded(child: SizedBox()),
                          ],
                        );
                      }
                      return Row(
                        children: List.generate(
                            count, (i) => yearCell(decadeStart + start + i)),
                      );
                    }).toList(),
                  );
                }),
              ],
            ],

            const SizedBox(height: 12),

            // Selected period label
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _selectedLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: primary,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, (
                      mode: _mode,
                      anchor: _anchor,
                      customStart: _customStart,
                      customEnd: _customEnd,
                    )),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
