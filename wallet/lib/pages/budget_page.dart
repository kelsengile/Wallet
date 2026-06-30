import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../currency.dart';
import '../models/category_model.dart';
import '../models/budget_model.dart';

final _currencyFmt = NumberFormat('#,##0.00', 'en_PH');
String _fmt(double v) => _currencyFmt.format(v);

Color? _parseHex(String hex) {
  try {
    final cleaned = hex.replaceFirst('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  } catch (_) {
    return null;
  }
}

/// Dark mode swaps the indigo/blue "primary" accent for a neutral gray on
/// this page, so progress bars, the summary card, and the period picker
/// don't clash with the rest of the (still-blue) app chrome.
Color _accentFor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? Colors.grey.shade400
      : theme.colorScheme.primary;
}

/// Fixed dark-gray used for the "Total budgeted" header card and the Add
/// Budget buttons (empty-state button + FAB), regardless of light/dark mode.
const Color _headerGray = Color(0xFF424242);

/// Picks black or white text depending on how light/dark [bg] is, so
/// filled buttons stay readable no matter which accent color they end up
/// using (e.g. the light-gray dark-mode accent needs black text, not white).
Color _onColorFor(Color bg) {
  return ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
      ? Colors.white
      : Colors.black;
}

// ── Filter modes (mirrored exactly from history_page) ──────────────────────
enum _FilterMode { daily, weekly, monthly, yearly, allTime, custom }

/// A budget joined with its computed "spent so far" for the active period.
class _BudgetProgress {
  final Budget budget;
  final double spent;
  final WalletCategory? category;

  const _BudgetProgress({
    required this.budget,
    required this.spent,
    required this.category,
  });

  double get remaining => budget.monthlyLimit - spent;
  double get fraction =>
      budget.monthlyLimit > 0 ? (spent / budget.monthlyLimit) : 0;
  bool get isOver => spent > budget.monthlyLimit;
}

class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  final _db = DatabaseHelper.instance;

  bool _loading = true;
  List<Budget> _budgets = [];
  List<WalletCategory> _expenseCategories = [];
  Map<String, double> _spentByCategory = {};

  // ── Filter state (mirrored exactly from history_page) ────────────────────
  _FilterMode _filterMode = _FilterMode.monthly;
  DateTime _anchor = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _customStart;
  DateTime? _customEnd;

  // ── Period helpers (mirrored exactly from history_page) ──────────────────

  /// Inclusive start of the current period.
  DateTime get _periodStart {
    final now = _anchor;
    switch (_filterMode) {
      case _FilterMode.daily:
        return DateTime(now.year, now.month, now.day);
      case _FilterMode.weekly:
        // Monday of the week containing _anchor
        return now.subtract(Duration(days: now.weekday - 1));
      case _FilterMode.monthly:
        return DateTime(now.year, now.month);
      case _FilterMode.yearly:
        return DateTime(now.year);
      case _FilterMode.allTime:
        return DateTime(2000); // effectively epoch
      case _FilterMode.custom:
        return _customStart ?? DateTime(2000);
    }
  }

  /// Exclusive end (start of next period).
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
    if (_filterMode == _FilterMode.allTime ||
        _filterMode == _FilterMode.custom) {
      return false;
    }
    return true;
  }

  void _goBack() {
    if (_filterMode == _FilterMode.allTime ||
        _filterMode == _FilterMode.custom) {
      return;
    }
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
    _saveFilter();
    _loadSpending();
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
    _saveFilter();
    _loadSpending();
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _db.getAllBudgets(),
      _db.getCategoryRegistry(),
      _db.getSetting('budget_filter_mode'),
      _db.getSetting('budget_filter_anchor'),
      _db.getSetting('budget_filter_custom_start'),
      _db.getSetting('budget_filter_custom_end'),
    ]);
    final budgets = results[0] as List<Budget>;
    final registry = results[1] as CategoryRegistry;
    final savedFilter = results[2] as String?;
    final savedAnchor = results[3] as String?;
    final savedCustomStart = results[4] as String?;
    final savedCustomEnd = results[5] as String?;
    final expenseCategories = registry.selectableTransactionCategories
        .where((c) => c.subType == 'expense')
        .toList();

    _FilterMode restoredMode = _filterMode;
    DateTime restoredAnchor = _anchor;
    if (savedFilter != null) {
      restoredMode = _FilterMode.values.firstWhere(
        (m) => m.name == savedFilter,
        orElse: () => _FilterMode.monthly,
      );
    }
    if (savedAnchor != null) {
      restoredAnchor = DateTime.tryParse(savedAnchor) ?? _anchor;
    }

    if (!mounted) return;
    setState(() {
      _budgets = budgets;
      _expenseCategories = expenseCategories;
      _filterMode = restoredMode;
      _anchor = restoredAnchor;
      if (savedCustomStart != null) {
        _customStart = DateTime.tryParse(savedCustomStart);
      }
      if (savedCustomEnd != null) {
        _customEnd = DateTime.tryParse(savedCustomEnd);
      }
    });

    await _loadSpending();
  }

  /// Recomputes "spent so far" for each budget against the active period.
  /// Split out from [_load] so period navigation doesn't re-fetch budgets.
  Future<void> _loadSpending() async {
    final start = _periodStart;
    final end = _periodEnd;
    final spentMap = <String, double>{};
    for (final b in _budgets) {
      spentMap[b.category] =
          await _db.getSpentForCategoryInRange(b.category, start, end);
    }
    if (!mounted) return;
    setState(() {
      _spentByCategory = spentMap;
      _loading = false;
    });
  }

  Future<void> _saveFilter() async {
    await _db.saveSetting('budget_filter_mode', _filterMode.name);
    await _db.saveSetting('budget_filter_anchor', _anchor.toIso8601String());
    if (_customStart != null) {
      await _db.saveSetting(
          'budget_filter_custom_start', _customStart!.toIso8601String());
    }
    if (_customEnd != null) {
      await _db.saveSetting(
          'budget_filter_custom_end', _customEnd!.toIso8601String());
    }
  }

  // ── Period picker (tapping the label) — mirrored from history_page ───────

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
      _loading = true;
    });
    _saveFilter();
    await _loadSpending();
  }

  List<_BudgetProgress> get _progress {
    final catMap = {for (final c in _expenseCategories) c.name: c};
    final list = _budgets
        .map((b) => _BudgetProgress(
              budget: b,
              spent: _spentByCategory[b.category] ?? 0,
              category: catMap[b.category],
            ))
        .toList();
    // Categories over budget first, then by highest spend fraction.
    list.sort((a, b) {
      if (a.isOver != b.isOver) return a.isOver ? -1 : 1;
      return b.fraction.compareTo(a.fraction);
    });
    return list;
  }

  Future<void> _addBudget() async {
    final taken = _budgets.map((b) => b.category).toSet();
    final available =
        _expenseCategories.where((c) => !taken.contains(c.name)).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Every expense category already has a budget.'),
        ),
      );
      return;
    }
    final result = await Budget.showDialog(
      context,
      categories: available,
      takenCategories: taken,
    );
    if (result == null) return;
    await _db.addBudget(result);
    if (!mounted) return;
    await _load();
  }

  Future<void> _editBudget(Budget budget) async {
    final taken = _budgets.map((b) => b.category).toSet();
    final result = await Budget.showDialog(
      context,
      categories: _expenseCategories,
      takenCategories: taken,
      existing: budget,
    );
    if (result == null) return;
    await _db.updateBudget(result);
    if (!mounted) return;
    await _load();
  }

  Future<void> _deleteBudget(Budget budget) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete budget?'),
        content: Text(
          'This removes the monthly limit for "${budget.category}". '
          'Past transactions are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || budget.id == null) return;
    await _db.deleteBudget(budget.id!);
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final totalLimit = _budgets.fold(0.0, (s, b) => s + b.monthlyLimit);
    final totalSpent = _spentByCategory.values.fold(0.0, (s, v) => s + v);
    final totalFraction = totalLimit > 0 ? (totalSpent / totalLimit) : 0.0;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Budget',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Filter',
            onPressed: _pickPeriod,
            icon: _FunnelIcon(
              color: theme.appBarTheme.foregroundColor ??
                  theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  // ── Period navigator (mirrored from history_page) ────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Opacity(
                        opacity: _filterMode == _FilterMode.allTime ? 0.0 : 1.0,
                        child: IgnorePointer(
                          ignoring: _filterMode == _FilterMode.allTime,
                          child: IconButton(
                            icon: const Icon(Icons.chevron_left),
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
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Opacity(
                        opacity: _filterMode == _FilterMode.allTime ? 0.0 : 1.0,
                        child: IgnorePointer(
                          ignoring: _filterMode == _FilterMode.allTime,
                          child: IconButton(
                            icon: Icon(
                              Icons.chevron_right,
                              color: _canGoForward
                                  ? null
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: 0.3),
                            ),
                            onPressed: _canGoForward ? _goForward : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ── Summary card ─────────────────────────────────────────
                  if (_budgets.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _headerGray,
                            _headerGray.withValues(alpha: 0.75),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total budgeted',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${currencySymbolNotifier.value}${_fmt(totalLimit)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: totalFraction.clamp(0, 1).toDouble(),
                              minHeight: 8,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.25),
                              valueColor: AlwaysStoppedAnimation(
                                totalFraction > 1
                                    ? Colors.red.shade200
                                    : Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Spent ${currencySymbolNotifier.value}${_fmt(totalSpent)}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                totalLimit - totalSpent >= 0
                                    ? 'Left ${currencySymbolNotifier.value}${_fmt(totalLimit - totalSpent)}'
                                    : 'Over by ${currencySymbolNotifier.value}${_fmt(totalSpent - totalLimit)}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),

                  // ── Budget list / empty state ────────────────────────────
                  if (_budgets.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: Column(
                        children: [
                          Icon(
                            Icons.savings_outlined,
                            size: 56,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'No budgets yet',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Set a monthly spending limit for a category\n'
                            'to start tracking it here.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _headerGray,
                              foregroundColor: _onColorFor(_headerGray),
                            ),
                            onPressed: _addBudget,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Budget'),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._progress.map((p) => _BudgetCard(
                          progress: p,
                          onTap: () => _editBudget(p.budget),
                          onDelete: () => _deleteBudget(p.budget),
                        )),
                ],
              ),
            ),
      floatingActionButton: _budgets.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: _headerGray,
              foregroundColor: _onColorFor(_headerGray),
              onPressed: _addBudget,
              icon: const Icon(Icons.add),
              label: const Text('Add Budget'),
            ),
    );
  }
}

// ── Budget card ────────────────────────────────────────────────────────────

class _BudgetCard extends StatelessWidget {
  final _BudgetProgress progress;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _BudgetCard({
    required this.progress,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cat = progress.category;
    final color = cat != null
        ? (_parseHex(cat.colorHex) ?? _accentFor(context))
        : _accentFor(context);
    final icon = cat?.iconData ?? Icons.label_outline;
    final fraction = progress.fraction.clamp(0, 1).toDouble();
    final barColor = progress.isOver ? Colors.red : color;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: progress.isOver
            ? Border.all(color: Colors.red.withValues(alpha: 0.4))
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          progress.budget.category,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${currencySymbolNotifier.value}${_fmt(progress.spent)} of '
                          '${currencySymbolNotifier.value}${_fmt(progress.budget.monthlyLimit)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert,
                        size: 18, color: theme.colorScheme.outline),
                    onSelected: (v) {
                      if (v == 'edit') onTap();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 7,
                  backgroundColor: barColor.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(barColor),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(progress.fraction * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: barColor,
                    ),
                  ),
                  Text(
                    progress.isOver
                        ? 'Over by ${currencySymbolNotifier.value}${_fmt(-progress.remaining)}'
                        : '${currencySymbolNotifier.value}${_fmt(progress.remaining)} left',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: progress.isOver
                          ? Colors.red
                          : theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Custom funnel / filter icon (copied verbatim from history_page) ───────

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

    // Three horizontal lines, each shorter than the last (funnel / filter look)
    final lines = [
      // (startX, endX, y)
      (0.0, w, h * 0.22),
      (w * 0.18, w * 0.82, h * 0.50),
      (w * 0.36, w * 0.64, h * 0.78),
    ];

    for (final (x1, x2, y) in lines) {
      canvas.drawLine(Offset(x1, y), Offset(x2, y), paint);
    }
  }

  @override
  bool shouldRepaint(_FunnelPainter old) => old.color != color;
}

// ── Period picker dialog (copied verbatim from history_page, with the
// "primary" accent swapped for the gray dark-mode accent) ─────────────────
//
// A centred dialog that lets the user pick both a filter mode (Day / Week /
// Month / Year / All / Custom) and an exact anchor date. Returns a named
// record so the caller gets both values atomically.

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

  // For the inline calendar grid
  late DateTime _calendarMonth; // which month the mini-calendar is showing

  // Custom date range
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

  // ── Helpers ─────────────────────────────────────────────────────────────────

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
          _anchor = DateTime(d.year, d.month, d.day);
          break;
        case _FilterMode.weekly:
          // snap anchor to Monday of tapped week
          _anchor = d.subtract(Duration(days: d.weekday - 1));
          break;
        case _FilterMode.monthly:
          _anchor = DateTime(d.year, d.month);
          break;
        case _FilterMode.yearly:
          _anchor = DateTime(d.year);
          break;
        case _FilterMode.allTime:
          break;
        case _FilterMode.custom:
          // First tap sets start, second tap sets end (if after start), third resets
          final day = DateTime(d.year, d.month, d.day);
          if (_customStart == null ||
              (_customEnd != null) ||
              day.isBefore(_customStart!)) {
            _customStart = day;
            _customEnd = null;
          } else if (_isSameDay(day, _customStart!)) {
            _customStart = null;
            _customEnd = null;
          } else {
            _customEnd = day;
          }
          break;
      }
    });
  }

  String _calendarMonthLabel() =>
      DateFormat('MMMM yyyy').format(_calendarMonth);

  // Days to display: leading blanks + days of the month
  List<DateTime?> _calendarDays() {
    final firstDay = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final daysInMonth =
        DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    final leadingBlanks = firstDay.weekday - 1; // Monday = 1
    return [
      ...List<DateTime?>.filled(leadingBlanks, null),
      ...List.generate(daysInMonth,
          (i) => DateTime(_calendarMonth.year, _calendarMonth.month, i + 1)),
    ];
  }

  // ── Selected period label shown at bottom ─────────────────────────────────

  String get _selectedLabel {
    switch (_mode) {
      case _FilterMode.daily:
        return DateFormat('EEE, MMM d, yyyy').format(_anchor);
      case _FilterMode.weekly:
        final start = _anchor.subtract(Duration(days: _anchor.weekday - 1));
        final end = start.add(const Duration(days: 6));
        return '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, yyyy').format(end)}';
      case _FilterMode.monthly:
        return DateFormat('MMMM yyyy').format(_anchor);
      case _FilterMode.yearly:
        return _anchor.year.toString();
      case _FilterMode.allTime:
        return 'All Time';
      case _FilterMode.custom:
        if (_customStart == null && _customEnd == null) {
          return 'Tap to select start date';
        } else if (_customStart != null && _customEnd == null) {
          return 'From ${DateFormat('MMM d, yyyy').format(_customStart!)} — tap end date';
        } else if (_customStart != null && _customEnd != null) {
          return '${DateFormat('MMM d, yyyy').format(_customStart!)} – ${DateFormat('MMM d, yyyy').format(_customEnd!)}';
        }
        return 'Custom Range';
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = _accentFor(context);
    final now = DateTime.now();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Mode tabs ──────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(3),
              child: Row(
                children: _modes.map((opt) {
                  final (mode, label) = opt;
                  final sel = _mode == mode;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _mode = mode;
                        // re-snap anchor to the same date under the new mode
                        _onDayTapped(_anchor);
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: sel
                              ? theme.colorScheme.surface
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: sel
                              ? [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 4)
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  sel ? FontWeight.w700 : FontWeight.w400,
                              color: sel
                                  ? primary
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // ── Unified nav row (always present for stable dialog height) ─
            Opacity(
              opacity: _mode == _FilterMode.allTime ? 0.0 : 1.0,
              child: IgnorePointer(
                ignoring: _mode == _FilterMode.allTime,
                child: Builder(builder: (_) {
                  // Compute label, back handler, and forward-disabled state
                  // once, based on the active mode.
                  final decadeStart = (_calendarMonth.year - 1) ~/ 10 * 10 + 1;

                  final String navLabel;
                  final VoidCallback onBack;
                  final VoidCallback? onForward;
                  final double labelFontSize;

                  switch (_mode) {
                    case _FilterMode.monthly:
                      navLabel = '${_calendarMonth.year}';
                      labelFontSize = 15;
                      onBack = () => setState(() => _calendarMonth = DateTime(
                          _calendarMonth.year - 1, _calendarMonth.month));
                      onForward = () => setState(() => _calendarMonth =
                          DateTime(
                              _calendarMonth.year + 1, _calendarMonth.month));
                    case _FilterMode.yearly:
                      navLabel = '$decadeStart – ${decadeStart + 9}';
                      labelFontSize = 15;
                      onBack = () => setState(() => _calendarMonth =
                          DateTime(_calendarMonth.year - 10, 1));
                      onForward = () => setState(() => _calendarMonth =
                          DateTime(_calendarMonth.year + 10, 1));
                    default:
                      // Daily / Weekly / Custom — navigate by month
                      navLabel = _calendarMonthLabel();
                      labelFontSize = 13;
                      onBack = () => setState(() => _calendarMonth = DateTime(
                          _calendarMonth.year, _calendarMonth.month - 1));
                      onForward = () => setState(() => _calendarMonth =
                          DateTime(
                              _calendarMonth.year, _calendarMonth.month + 1));
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.chevron_left),
                        onPressed: onBack,
                      ),
                      Text(
                        navLabel,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: labelFontSize,
                        ),
                      ),
                      IconButton(
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          Icons.chevron_right,
                          // ignore: unnecessary_null_comparison
                          color: onForward == null
                              ? theme.colorScheme.onSurface
                                  .withValues(alpha: 0.25)
                              : null,
                        ),
                        onPressed: onForward,
                      ),
                    ],
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),

            // ── Mode-specific picker body (fixed height = tallest mode) ────
            SizedBox(
              height: 240,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_mode == _FilterMode.allTime) ...[
                    // All Time: no date selection needed
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.all_inclusive,
                          size: 48,
                          color: primary.withValues(alpha: 0.35),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Showing all transactions',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ] else if (_mode == _FilterMode.custom) ...[
                    // Custom range: weekday header + tappable day grid
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
                                return const Expanded(
                                    child: SizedBox(height: 36));
                              }

                              final highlighted = _isHighlighted(d);
                              final isStart = _customStart != null &&
                                  _isSameDay(d, _customStart!);
                              final isEnd = _customEnd != null &&
                                  _isSameDay(d, _customEnd!);
                              final isToday = _isSameDay(d, now);

                              Color? bgColor;
                              Color textColor = theme.colorScheme.onSurface;

                              if (isStart || isEnd) {
                                bgColor = primary.withValues(alpha: 0.85);
                                textColor = theme.colorScheme.onPrimary;
                              } else if (highlighted) {
                                bgColor = primary.withValues(alpha: 0.12);
                                textColor = primary;
                              } else if (isToday) {
                                textColor = primary;
                              }

                              return Expanded(
                                child: GestureDetector(
                                  onTap: () => _onDayTapped(d),
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
                                          fontWeight: highlighted ||
                                                  isToday ||
                                                  isStart ||
                                                  isEnd
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
                  ] else if (_mode == _FilterMode.monthly) ...[
                    // Monthly: 3×4 month grid
                    Builder(builder: (_) {
                      const monthNames = [
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
                      return Column(
                        children: List.generate(3, (row) {
                          return Row(
                            children: List.generate(4, (col) {
                              final monthIdx = row * 4 + col + 1;
                              final isSelected =
                                  _anchor.year == _calendarMonth.year &&
                                      _anchor.month == monthIdx;
                              final isCurrentMonth =
                                  _calendarMonth.year == now.year &&
                                      monthIdx == now.month;
                              Color textColor = isSelected
                                  ? primary
                                  : isCurrentMonth
                                      ? primary
                                      : theme.colorScheme.onSurface;
                              return Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _anchor =
                                        DateTime(_calendarMonth.year, monthIdx);
                                  }),
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
                                        monthNames[monthIdx - 1],
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight:
                                              isSelected || isCurrentMonth
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
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
                  ] else if (_mode == _FilterMode.yearly) ...[
                    // Yearly: 4 + 4 + 2 year grid
                    Builder(builder: (_) {
                      final decadeStart =
                          (_calendarMonth.year - 1) ~/ 10 * 10 + 1;
                      // Row sizes: [4, 4, 2]
                      const rowSizes = [4, 4, 2];

                      Widget yearCell(int yr) {
                        final isSelected = _anchor.year == yr;
                        final isCurrentYear = yr == now.year;
                        final Color textColor = isSelected
                            ? primary
                            : isCurrentYear
                                ? primary
                                : theme.colorScheme.onSurface;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _anchor = DateTime(yr)),
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
                            // Last row: one spacer on each side to centre the 2 cells
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
                            children: List.generate(count,
                                (i) => yearCell(decadeStart + start + i)),
                          );
                        }).toList(),
                      );
                    }),
                  ] else ...[
                    // Daily / Weekly: weekday header + day grid
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
                                return const Expanded(
                                    child: SizedBox(height: 36));
                              }

                              final highlighted = _isHighlighted(d);
                              final isToday = _isSameDay(d, now);

                              Color? bgColor;
                              Color textColor = theme.colorScheme.onSurface;

                              if (highlighted) {
                                bgColor = primary.withValues(alpha: 0.15);
                                textColor = primary;
                              } else if (isToday) {
                                textColor = primary;
                              }

                              return Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    _onDayTapped(d);
                                  },
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
                  ], // end else (daily/weekly)
                ], // end Column.children
              ),
            ), // end SizedBox
            const SizedBox(height: 12),

            // ── Selected period label ──────────────────────────────────────
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

            // ── Actions ────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: _onColorFor(primary),
                    ),
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
