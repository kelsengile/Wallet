import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants.dart';
import '../core/failures.dart';
import '../core/screens/settings.dart';
import '../core/themes.dart';
import '../core/utils.dart';
import '../database/helper.dart';
import 'finance.dart' show showReminderEditor;

const List<String> _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const List<String> _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday',
  'Friday', 'Saturday', 'Sunday',
];

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final _db = DatabaseHelper.instance;

  /// The chosen day (date only). The grid shows this day's month.
  late DateTime _selected = _today();
  List<ReminderItem> _reminders = const [];
  String? _error;

  DateTime _today() {
    final n = Utils.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _load();
    _db.changes.addListener(_load);
  }

  @override
  void dispose() {
    _db.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await _db.getReminders();
      if (!mounted) return;
      setState(() {
        _reminders = items;
        _error = null;
      });
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      if (mounted) setState(() => _error = const UnknownFailure().message);
    }
  }

  /// Moves to the same day of another month (or its last day).
  void _shiftMonth(int by) {
    final first = DateTime(_selected.year, _selected.month + by);
    final last = DateTime(first.year, first.month + 1, 0).day;
    setState(() {
      _selected = DateTime(
        first.year,
        first.month,
        math.min(_selected.day, last),
      );
    });
  }

  void _select(DateTime d) {
    HapticFeedback.selectionClick();
    setState(() => _selected = d);
  }

  // ---------- Calendar ----------

  /// The row of spiral rings that sits across the top edge of the page.
  Widget _rings(double width, Color fg, Color bg) {
    final count = math.max(4, ((width - 32) / 17).floor());
    return SizedBox(
      height: 40,
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                width: 9,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: Colors.grey, width: 2.5),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _leftSide(Color fg) {
    final theme = Theme.of(context);
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Tap the big date to jump back to today.
      onTap: () => setState(() => _selected = _today()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Calendar'.tr,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: muted,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _months[_selected.month - 1],
              maxLines: 1,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${_selected.day}',
              maxLines: 1,
              style: TextStyle(
                fontSize: 68,
                height: 1.05,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _weekdays[_selected.weekday - 1],
              maxLines: 1,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayCell(int day, int days, Color fg, Color bg) {
    if (day < 1 || day > days) return const SizedBox(height: 26);
    final date = DateTime(_selected.year, _selected.month, day);
    final isSel = date == _selected;
    final isToday = date == _today();
    final isSunday = date.weekday == DateTime.sunday;
    final hasReminder = _reminders.any((r) => Utils.isSameDay(r.dueDate, date));
    final textColor = isSel
        ? bg
        : (isSunday ? AppSettings.instance.expenseColor : fg);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _select(date),
      child: SizedBox(
        height: 26,
        child: Center(
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSel ? fg : null,
              border: isToday && !isSel ? Border.all(color: fg, width: 1.5) : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: (isSel || isToday)
                        ? FontWeight.w800
                        : FontWeight.w500,
                    color: textColor,
                  ),
                ),
                if (hasReminder)
                  Positioned(
                    bottom: 1,
                    child: Container(
                      width: 3.5,
                      height: 3.5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSel
                            ? bg
                            : AppSettings.instance.reminderColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rightSide(Color fg, Color bg) {
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    final lead = DateTime(_selected.year, _selected.month, 1).weekday - 1;
    final days = DateTime(_selected.year, _selected.month + 1, 0).day;
    final rows = ((lead + days) / 7).ceil();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // < 2026 >
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            InkResponse(
              radius: 16,
              onTap: () => _shiftMonth(-1),
              child: Icon(Icons.chevron_left, size: 20, color: muted),
            ),
            const SizedBox(width: 4),
            Text(
              '${_selected.year}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
            const SizedBox(width: 4),
            InkResponse(
              radius: 16,
              onTap: () => _shiftMonth(1),
              child: Icon(Icons.chevron_right, size: 20, color: muted),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceXs),
        // M T W T F S S
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i],
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: i == 6
                          ? AppSettings.instance.expenseColor
                          : muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(child: _dayCell(r * 7 + c - lead + 1, days, fg, bg)),
            ],
          ),
      ],
    );
  }

  /// The whole spiral calendar: rings on top, page underneath.
  Widget _calendar(Color fg, Color bg) {
    final hole = Color.alphaBlend(Colors.black.withValues(alpha: 0.35), bg);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceMd),
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          clipBehavior: Clip.none,
          children: [
            // Page
            Container(
              margin: const EdgeInsets.only(top: 25),
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spaceMd,
                32,
                AppConstants.spaceMd,
                AppConstants.spaceMd,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(
                  color: fg.withValues(alpha: AppConstants.dividerAlpha),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: _leftSide(fg)),
                  const SizedBox(width: AppConstants.spaceSm),
                  Expanded(flex: 6, child: _rightSide(fg, bg)),
                ],
              ),
            ),
            // Punched holes (behind the rings)
            Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: SizedBox(
                height: 16,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 0;
                          i < math.max(4, ((c.maxWidth - 32) / 17).floor());
                          i++)
                        Container(
                          width: 9,
                          height: 16,
                          decoration: BoxDecoration(
                            color: hole,
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Spiral rings, half above and half below the top edge
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _rings(c.maxWidth, fg, bg),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Selected day ----------

  Widget _reminderRow(ReminderItem r, Color fg, Color bg) {
    final s = AppSettings.instance;
    final color = r.type == 'income' ? s.incomeColor : s.expenseColor;
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceSm),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showReminderEditor(context, r),
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spaceSmMd),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: s.reminderColor.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.notifications_active,
                    size: 22,
                    color: s.reminderColor,
                  ),
                ),
                const SizedBox(width: AppConstants.spaceSmMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                      Text(
                        [
                          r.categoryName,
                          Utils.formatTime(r.dueDate),
                        ].whereType<String>().join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppConstants.spaceSm),
                Text(
                  '${r.type == 'income' ? '+' : '−'}'
                  '${Utils.formatCurrency(r.amount, symbol: AppConstants.currencySymbol)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _daySection(Color fg, Color bg) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final list = [
      for (final r in _reminders)
        if (Utils.isSameDay(r.dueDate, _selected)) r,
    ];
    final isToday = _selected == _today();
    final title =
        '${isToday ? 'Today' : '${_months[_selected.month - 1].substring(0, 3)} ${_selected.day}'}'
        ',  ${_weekdays[_selected.weekday - 1]}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMd,
        AppConstants.spaceLg,
        AppConstants.spaceMd,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${list.length}',
                style: TextStyle(color: muted, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceXs),
          Divider(
            height: 1,
            thickness: 1,
            color: theme.colorScheme.onSurface.withValues(
              alpha: AppConstants.dividerAlpha,
            ),
          ),
          const SizedBox(height: AppConstants.spaceSmMd),
          if (_error != null)
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppConstants.spaceLg),
              child: Column(
                children: [
                  Icon(
                    Icons.event_available_outlined,
                    size: AppConstants.emptyStateIconSize,
                    color: muted,
                  ),
                  const SizedBox(height: AppConstants.spaceSm),
                  Text(
                    'Nothing scheduled',
                    style: theme.textTheme.titleMedium?.copyWith(color: muted),
                  ),
                ],
              ),
            )
          else
            for (final r in list) _reminderRow(r, fg, bg),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;

    // Status bar + app bar height.
    final topInset = MediaQuery.viewPaddingOf(context).top + kToolbarHeight;

    // How far the rectangle extends below the app bar. Change this to make
    // the rectangle taller or shorter.
    const extra = 60.0;
    final headerH = topInset + extra;

    // Half of the ring length (rings are 30 tall) sits over the rectangle.
    const ringOverlap = 10.0;

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            // The rectangle behind the app bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: headerH,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bg,
                  border: Border(
                    bottom: BorderSide(
                      color: fg.withValues(alpha: AppConstants.dividerAlpha),
                    ),
                  ),
                ),
              ),
            ),
            // The calendar, pulled up so the rings hang from its bottom edge
            Padding(
              padding: EdgeInsets.only(top: headerH - ringOverlap),
              child: _calendar(fg, bg),
            ),
          ],
        ),
        _daySection(fg, bg),
      ],
    );
  }
}