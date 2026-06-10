import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/transaction_model.dart';
import '../models/account_model.dart';

final _currencyFmt = NumberFormat('#,##0.00', 'en_PH');
String _fmt(double v) => _currencyFmt.format(v);

// ── Filter modes ───────────────────────────────────────────────────────────────
enum _FilterMode { daily, weekly, monthly, yearly }

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => HistoryPageState();
}

class HistoryPageState extends State<HistoryPage> {
  final _db = DatabaseHelper.instance;
  List<WalletTransaction> _transactions = [];
  List<Account> _accounts = [];
  bool _loading = true;

  _FilterMode _filterMode = _FilterMode.monthly;

  // The "anchor" date — we navigate around this.
  DateTime _anchor = DateTime(DateTime.now().year, DateTime.now().month);

  // ── Period helpers ────────────────────────────────────────────────────────

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
    }
  }

  String get _periodLabel {
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
    }
  }

  bool get _canGoForward {
    final now = DateTime.now();
    return _periodEnd.isBefore(DateTime(now.year, now.month, now.day + 1));
  }

  void _goBack() {
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
      }
    });
    _saveFilter();
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
      }
    });
    _saveFilter();
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

  // ── Analytics for current period ──────────────────────────────────────────

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

  Future<void> _load() async {
    final txs = await _db.getAllTransactions();
    final accounts = await _db.getAllAccounts();
    final savedFilter = await _db.getSetting('history_filter_mode');
    final savedAnchor = await _db.getSetting('history_filter_anchor');

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
      _transactions = txs;
      _accounts = accounts;
      _filterMode = restoredMode;
      _anchor = restoredAnchor;
      _loading = false;
    });
  }

  Future<void> _saveFilter() async {
    await _db.saveSetting('history_filter_mode', _filterMode.name);
    await _db.saveSetting('history_filter_anchor', _anchor.toIso8601String());
  }

  // ── Filter bottom-sheet ───────────────────────────────────────────────────

  Future<void> _showFilterSheet() async {
    final selected = await showModalBottomSheet<_FilterMode>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _FilterSheet(current: _filterMode),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _filterMode = selected;
      // Reset anchor to today's period when switching modes
      final now = DateTime.now();
      switch (_filterMode) {
        case _FilterMode.daily:
          _anchor = DateTime(now.year, now.month, now.day);
          break;
        case _FilterMode.weekly:
          _anchor = now.subtract(Duration(days: now.weekday - 1));
          break;
        case _FilterMode.monthly:
          _anchor = DateTime(now.year, now.month);
          break;
        case _FilterMode.yearly:
          _anchor = DateTime(now.year);
          break;
      }
    });
    _saveFilter();
  }

  // ── Public API (called from main.dart) ────────────────────────────────────

  Future<void> refresh() => _load();

  Future<void> addTransaction() async {
    final tx = await WalletTransaction.showDialog(
      context,
      accounts: _accounts,
    );
    if (tx == null) return;
    await _db.insertTransaction(tx);
    _load();
  }

  Future<void> _editTransaction(WalletTransaction existing) async {
    final updated = await WalletTransaction.showDialog(
      context,
      accounts: _accounts,
      existing: existing,
    );
    if (updated == null) return;
    await _db.updateTransaction(existing, updated);
    _load();
  }

  Future<void> _deleteTransaction(WalletTransaction tx) async {
    await _db.deleteTransaction(tx);
    _load();
  }

  // ── Date group label ──────────────────────────────────────────────────────

  /// Returns the header string for a group of transactions sharing the same
  /// calendar day, based on the active filter mode.
  String _dateGroupLabel(DateTime d) {
    switch (_filterMode) {
      case _FilterMode.daily:
        return ''; // no header needed — date already shown in navigator
      case _FilterMode.weekly:
      case _FilterMode.monthly:
        // e.g. "Jun 9, Monday"
        return DateFormat('MMM d, EEEE').format(d);
      case _FilterMode.yearly:
        // e.g. "Jun 9 • Monday"
        return DateFormat('MMM d • EEEE').format(d);
    }
  }

  // ── Grouped list builder ──────────────────────────────────────────────────

  Widget _buildGroupedList(List<WalletTransaction> txs, ThemeData theme) {
    // Group transactions by calendar date string "yyyy-MM-dd"
    final Map<String, List<WalletTransaction>> groups = {};
    for (final tx in txs) {
      final key = tx.date.length >= 10 ? tx.date.substring(0, 10) : tx.date;
      groups.putIfAbsent(key, () => []).add(tx);
    }
    // Keys are already date-DESC ordered because _transactions is sorted DESC
    final keys = groups.keys.toList();

    // Build a flat list of items: header + transactions for each group
    final items = <_ListItem>[];
    for (final key in keys) {
      final d = DateTime.tryParse(key);
      final label = d != null ? _dateGroupLabel(d) : '';
      if (label.isNotEmpty) items.add(_ListItem.header(label));
      for (final tx in groups[key]!) {
        items.add(_ListItem.tx(tx));
      }
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        if (item.isHeader) {
          return _DateHeader(label: item.label!, theme: theme);
        }
        final tx = item.tx!;
        final isIncome = tx.type == 'income';
        final accountName = _accounts
            .firstWhere(
              (a) => a.id == tx.accountId,
              orElse: () => Account(
                name: 'Unknown',
                balance: 0,
                type: '',
                colorHex: '',
                icon: '',
              ),
            )
            .name;
        return Dismissible(
          key: Key('tx_${tx.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            color: Colors.red,
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => _deleteTransaction(tx),
          child: ListTile(
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
            onTap: () => _editTransaction(tx),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor:
                  isIncome ? Colors.green.shade100 : Colors.red.shade100,
              child: Icon(
                kTransactionCategoryIcons[tx.category] ?? Icons.category,
                size: 17,
                color: isIncome ? Colors.green : Colors.red,
              ),
            ),
            title: Text(
              tx.title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            subtitle: Text(
              accountName,
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Text(
              '${isIncome ? '+' : '-'} ₱${_fmt(tx.amount)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isIncome ? Colors.green : Colors.red,
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filtered;
    final income = _periodIncome;
    final expenses = _periodExpenses;
    final net = _periodNet;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ───────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Transaction History',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600, fontSize: 18),
              ),
              IconButton(
                tooltip: 'Filter',
                onPressed: _showFilterSheet,
                icon: _FunnelIcon(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),

          // ── Period navigator ─────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _goBack,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _periodLabel,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.chevron_right,
                  color: _canGoForward
                      ? null
                      : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                onPressed: _canGoForward ? _goForward : null,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Analytics strip ──────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _AnalyticsTile(
                  icon: Icons.arrow_upward_rounded,
                  amount: income,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AnalyticsTile(
                  icon: Icons.arrow_downward_rounded,
                  amount: expenses,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AnalyticsTile(
                  icon: Icons.account_balance_wallet_outlined,
                  amount: net,
                  color: net >= 0 ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ── Divider ──────────────────────────────────────────────────────
          const Divider(height: 40),

          // ── Transaction list ─────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      _transactions.isEmpty
                          ? 'No transactions yet. Add one!'
                          : 'No transactions for this period.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : _buildGroupedList(filtered, theme),
          ),
        ],
      ),
    );
  }
}

// ── List item discriminated union ──────────────────────────────────────────────

class _ListItem {
  final bool isHeader;
  final String? label;
  final WalletTransaction? tx;

  const _ListItem.header(this.label)
      : isHeader = true,
        tx = null;
  const _ListItem.tx(this.tx)
      : isHeader = false,
        label = null;
}

// ── Date group header widget ───────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  final String label;
  final ThemeData theme;

  const _DateHeader({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 4),
          Divider(
            height: 1,
            thickness: 1,
            color: theme.colorScheme.outlineVariant,
          ),
        ],
      ),
    );
  }
}

// ── Analytics tile ─────────────────────────────────────────────────────────────

class _AnalyticsTile extends StatelessWidget {
  final IconData icon;
  final double amount;
  final Color color;

  const _AnalyticsTile({
    required this.icon,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '₱${_fmt(amount.abs())}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Custom funnel / filter icon ────────────────────────────────────────────────

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

// ── Filter bottom-sheet ────────────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  final _FilterMode current;
  const _FilterSheet({required this.current});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late _FilterMode _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
  }

  static const _options = [
    (_FilterMode.daily, 'Daily', Icons.today_outlined),
    (_FilterMode.weekly, 'Weekly', Icons.view_week_outlined),
    (_FilterMode.monthly, 'Monthly', Icons.calendar_month_outlined),
    (_FilterMode.yearly, 'Yearly', Icons.calendar_today_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Filter by Period',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ..._options.map((opt) {
            final (mode, label, icon) = opt;
            final isSelected = _selected == mode;
            return RadioListTile<_FilterMode>(
              value: mode,
              groupValue: _selected,
              onChanged: (v) => setState(() => _selected = v!),
              secondary: Icon(
                icon,
                color: isSelected ? theme.colorScheme.primary : null,
              ),
              title: Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? theme.colorScheme.primary : null,
                ),
              ),
              contentPadding: EdgeInsets.zero,
            );
          }),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _selected),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Apply'),
            ),
          ),
        ],
      ),
    );
  }
}
