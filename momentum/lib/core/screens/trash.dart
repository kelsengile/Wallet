import 'package:flutter/material.dart';

import '../../database/helper.dart';
import '../../features/finance.dart';
import '../constants.dart';
import '../failures.dart';
import '../themes.dart';
import '../utils.dart';
import 'settings.dart';

// ------------------------------------------------------------------
// Shared confirmation pop-up (also used by the Database screen)
// ------------------------------------------------------------------

/// One line of "what will happen" shown inside a confirmation pop-up.
class ConfirmPoint {
  final IconData icon;
  final String text;
  const ConfirmPoint(this.icon, this.text);
}

/// Spiky (zigzag) edge between the colored top and the body of a pop-up.
class _ZigzagPainter extends CustomPainter {
  final Color top;
  final Color body;
  const _ZigzagPainter(this.top, this.body);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = body);
    final count = (size.width / 18).round().clamp(1, 1000);
    final w = size.width / count;
    final path = Path()..moveTo(0, 0);
    for (var i = 0; i < count; i++) {
      path.lineTo(w * i + w / 2, size.height);
      path.lineTo(w * (i + 1), 0);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = top);
  }

  @override
  bool shouldRepaint(_ZigzagPainter old) =>
      old.top != top || old.body != body;
}

/// The confirmation pop-up of the app.
///  - [destructive] = true: red top (Settings > Delete color), red chip and
///    red confirm button.
///  - [destructive] = false: accent + glyph colors of the theme.
/// [chipIcon] + [chipText] show the affected item. [points] explain what
/// will happen. Returns true only when the confirm button is tapped.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required String confirmLabel,
  IconData? confirmIcon,
  bool destructive = false,
  String cancelLabel = 'Cancel',
  Widget? chipIcon,
  String? chipText,
  List<ConfirmPoint> points = const [],
}) async {
  final accent = AppTheme.accentOf(context);
  final fg = accent.foreground;
  final bg = accent.background;
  final tone = destructive ? AppSettings.instance.deleteColor : fg;
  final headerBg = destructive
      ? tone
      : Color.alphaBlend(fg.withValues(alpha: 0.16), bg);
  final headerFg = destructive ? Colors.white : fg;
  final muted = fg.withValues(alpha: AppConstants.mutedAlpha);

  final ok = await showDialog<bool>(
    context: context,
    barrierColor: AppConstants.popupBarrier,
    builder: (ctx) => Dialog(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ----- Top -----
            Container(
              color: headerBg,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
              child: Column(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: headerFg.withValues(alpha: 0.18),
                      border: destructive
                          ? null
                          : Border.all(color: headerFg, width: 2.5),
                    ),
                    child: Icon(icon, size: 32, color: headerFg),
                  ),
                  const SizedBox(height: AppConstants.spaceMd),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: headerFg,
                    ),
                  ),
                ],
              ),
            ),
            // ----- Spiky divider between the top and the body -----
            SizedBox(
              height: 10,
              width: double.infinity,
              child: CustomPaint(painter: _ZigzagPainter(headerBg, bg)),
            ),
            // ----- Body -----
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (chipText != null) ...[
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: tone.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (chipIcon != null) ...[
                              chipIcon,
                              const SizedBox(width: AppConstants.spaceSm),
                            ],
                            Flexible(
                              child: Text(
                                chipText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: tone,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppConstants.spaceMd),
                  ],
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, height: 1.4, color: muted),
                  ),
                  if (points.isNotEmpty) ...[
                    const SizedBox(height: AppConstants.spaceMd),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spaceSmMd,
                        vertical: AppConstants.spaceSm,
                      ),
                      decoration: BoxDecoration(
                        color: tone.withValues(
                          alpha: destructive ? 0.10 : AppConstants.tintAlpha,
                        ),
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusMd,
                        ),
                      ),
                      child: Column(
                        children: [
                          for (final p in points)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(p.icon, size: 18, color: tone),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      p.text,
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.3,
                                        color: fg,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppConstants.spaceLg),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: const StadiumBorder(),
                            foregroundColor: fg,
                            side: BorderSide(color: fg.withValues(alpha: 0.5)),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: Text(
                            cancelLabel,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: const StadiumBorder(),
                            backgroundColor: destructive ? tone : fg,
                            foregroundColor: destructive
                                ? Colors.white
                                : AppTheme.onColor(fg),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(true),
                          icon: confirmIcon == null
                              ? const SizedBox.shrink()
                              : Icon(confirmIcon, size: 20),
                          label: Text(
                            confirmLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}

// ------------------------------------------------------------------
// Trash screen
// ------------------------------------------------------------------

const List<String> _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Everything that was deleted but not yet removed for good.
/// Searchable, grouped by the day it was deleted, and emptied
/// automatically at the end of every month.
/// Swipe right = restore, swipe left = delete forever.
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final _db = DatabaseHelper.instance;
  final _search = TextEditingController();
  List<TrashItem> _all = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
    _db.changes.addListener(_load);
  }

  @override
  void dispose() {
    _db.changes.removeListener(_load);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // Anything deleted in an earlier month is removed for good.
      await _db.purgeExpiredTrash();
      final items = await _db.getTrashItems();
      if (!mounted) return;
      setState(() {
        _all = items;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn\'t load the trash.';
      });
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _perform(Future<void> Function() action, String done) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      _say(done);
      return true;
    } catch (error) {
      _say(error is Failure ? error.message : 'Something went wrong.');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- Labels ----------

  String _kindLabel(TrashItem i) {
    if (i.kind == TrashKind.account) return 'Account';
    final t = i.txType ?? 'transaction';
    return t[0].toUpperCase() + t.substring(1);
  }

  Color _colorOf(TrashItem i, Color fg) {
    final s = AppSettings.instance;
    switch (i.txType) {
      case 'income':
        return s.incomeColor;
      case 'expense':
        return s.expenseColor;
      case 'transfer':
        return s.transferColor;
      default:
        return fg;
    }
  }

  String? _amountText(TrashItem i) {
    final a = i.amount;
    if (a == null) return null;
    final money = Utils.formatCurrency(a, symbol: AppConstants.currencySymbol);
    switch (i.txType) {
      case 'income':
        return '+$money';
      case 'expense':
        return '−$money';
      case 'transfer':
        return '±$money';
      default:
        return money;
    }
  }

  String _detailOf(TrashItem i) {
    if (i.kind == TrashKind.account) {
      return [i.typeName, i.categoryName].whereType<String>().join(' · ');
    }
    if (i.txType == 'transfer') {
      return '${i.accountName ?? ''} → ${i.toAccountName ?? ''}';
    }
    return [i.categoryName, i.accountName].whereType<String>().join(' · ');
  }

  String _time12(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _dayLabel(DateTime? d) {
    if (d == null) return 'Earlier';
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final day = DateTime.utc(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${_weekdays[d.weekday - 1]}, ${Utils.formatDate(d)}';
  }

  Widget _iconFor(TrashItem i, Color color, double size) {
    if (i.kind == TrashKind.account) {
      return accountTypeIconWidget(
        i.typeName ?? '',
        i.iconKey,
        size: size,
        color: color,
      );
    }
    if (i.txType == 'transfer') {
      return Icon(Icons.swap_horiz, size: size, color: color);
    }
    return categoryIconWidget(i.iconKey, size: size, color: color);
  }

  // ---------- Search + grouping ----------

  List<TrashItem> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    final tokens = q.split(RegExp(r'\s+'));
    return [
      for (final i in _all)
        if (_matches(i, tokens)) i,
    ];
  }

  bool _matches(TrashItem i, List<String> tokens) {
    final hay = <String?>[
      i.title,
      i.subtitle,
      i.categoryName,
      i.accountName,
      i.toAccountName,
      i.typeName,
      i.note,
      i.amount?.toStringAsFixed(2),
      _kindLabel(i),
    ].whereType<String>().join(' ').toLowerCase();
    return tokens.every((t) => hay.contains(t));
  }

  List<(String, List<TrashItem>)> _groups(List<TrashItem> items) {
    final out = <(String, List<TrashItem>)>[];
    String? last;
    for (final i in items) {
      final label = _dayLabel(i.deletedAt);
      if (label != last) {
        out.add((label, <TrashItem>[]));
        last = label;
      }
      out.last.$2.add(i);
    }
    return out;
  }

  // ---------- Actions ----------

  Future<bool> _restore(TrashItem item) => _perform(
    () => _db.restoreTrashItem(item),
    item.kind == TrashKind.account
        ? '"${item.title}" restored.'
        : 'Transaction restored.',
  );

  Future<bool> _deleteForever(TrashItem item) async {
    final isAccount = item.kind == TrashKind.account;
    final ok = await showConfirmDialog(
      context,
      destructive: true,
      icon: Icons.delete_forever,
      title: isAccount ? 'Delete account forever' : 'Delete forever',
      chipIcon: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: _iconFor(item, AppSettings.instance.deleteColor, 20),
      ),
      chipText: item.title,
      message:
          'This ${isAccount ? 'account' : _kindLabel(item).toLowerCase()} '
          'will be permanently deleted.',
      points: [
        if (isAccount)
          const ConfirmPoint(
            Icons.receipt_long_outlined,
            'All transactions of this account are deleted too.',
          ),
        const ConfirmPoint(
          Icons.warning_amber_rounded,
          'This can\'t be undone.',
        ),
      ],
      confirmLabel: 'Delete',
      confirmIcon: Icons.delete,
    );
    if (!ok) return false;
    return _perform(() => _db.deleteTrashItemForever(item), 'Deleted forever.');
  }

  Future<void> _emptyTrash() async {
    final accounts = _all.where((i) => i.kind == TrashKind.account).length;
    final txs = _all.length - accounts;
    final ok = await showConfirmDialog(
      context,
      destructive: true,
      icon: Icons.delete_sweep_outlined,
      title: 'Empty trash',
      message: 'Everything in the trash will be permanently deleted.',
      points: [
        if (accounts > 0)
          ConfirmPoint(
            Icons.account_balance_wallet_outlined,
            '$accounts ${accounts == 1 ? 'account' : 'accounts'} '
            'and all their transactions',
          ),
        if (txs > 0)
          ConfirmPoint(
            Icons.receipt_long_outlined,
            '$txs ${txs == 1 ? 'transaction' : 'transactions'}',
          ),
        const ConfirmPoint(
          Icons.warning_amber_rounded,
          'This can\'t be undone.',
        ),
      ],
      confirmLabel: 'Empty trash',
      confirmIcon: Icons.delete_sweep_outlined,
    );
    if (ok) await _perform(_db.emptyTrash, 'Trash emptied.');
  }

  // ---------- Pieces ----------

  Widget _searchBar(Color fg, Color bg) {
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMd,
        AppConstants.spaceSm,
        AppConstants.spaceMd,
        AppConstants.spaceXs,
      ),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: TextField(
          controller: _search,
          style: TextStyle(color: fg),
          cursorColor: fg,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search trash',
            hintStyle: TextStyle(color: muted),
            prefixIcon: Icon(Icons.search, color: muted),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close, color: muted),
                    onPressed: _search.clear,
                  ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _banner(Color fg, Color bg) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month + 1, 0);
    final left = DateTime.utc(end.year, end.month, end.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
        .inDays;
    final text = left == 0
        ? 'The trash is emptied automatically at the end of today.'
        : 'The trash is emptied automatically on ${Utils.formatDate(end)} '
              '($left ${left == 1 ? 'day' : 'days'} left).';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMd,
        AppConstants.spaceSm,
        AppConstants.spaceMd,
        AppConstants.spaceMd,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceSmMd,
          vertical: AppConstants.spaceSmMd,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_delete_outlined, size: 20, color: fg),
            const SizedBox(width: AppConstants.spaceSmMd),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  color: fg.withValues(alpha: AppConstants.mutedAlpha),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: color,
      ),
    ),
  );

  Widget _row(TrashItem item, Color fg, Color bg) {
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    final color = _colorOf(item, fg);
    final detail = _detailOf(item);
    final amount = _amountText(item);
    final deleted = item.deletedAt;
    final note = item.note?.trim() ?? '';

    final content = ColoredBox(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spaceSmMd,
          AppConstants.spaceSmMd,
          AppConstants.spaceXs,
          AppConstants.spaceSmMd,
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: _iconFor(item, color, 24)),
            ),
            const SizedBox(width: AppConstants.spaceSmMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _pill(_kindLabel(item), color),
                      if (deleted != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Deleted ${_time12(deleted)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (amount != null) ...[
              const SizedBox(width: AppConstants.spaceSm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    amount,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: item.kind == TrashKind.account ? fg : color,
                    ),
                  ),
                ),
              ),
            ],
            PopupMenuButton<String>(
              enabled: !_busy,
              color: bg,
              icon: Icon(Icons.more_vert, color: muted),
              onSelected: (v) {
                if (v == 'restore') {
                  _restore(item);
                } else {
                  _deleteForever(item);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem<String>(
                  value: 'restore',
                  child: Row(
                    children: [
                      Icon(Icons.restore_from_trash, color: fg),
                      const SizedBox(width: 10),
                      Text('Restore', style: TextStyle(color: fg)),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_forever_outlined,
                        color: AppSettings.instance.deleteColor,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Delete forever',
                        style: TextStyle(
                          color: AppSettings.instance.deleteColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('${item.kind.name}-${item.id}'),
      confirmDismiss: (dir) => dir == DismissDirection.startToEnd
          ? _restore(item)
          : _deleteForever(item),
      onDismissed: (_) => setState(() {
        _all = [
          for (final x in _all)
            if (!(x.kind == item.kind && x.id == item.id)) x,
        ];
      }),
      background: Container(
        color: AppSettings.instance.doneColor,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: AppConstants.spaceLg),
        child: const Icon(Icons.restore_from_trash, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: AppSettings.instance.deleteColor,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppConstants.spaceLg),
        child: const Icon(Icons.delete_forever, color: Colors.white),
      ),
      child: content,
    );
  }

  Widget _dayHeader(String label, int count) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMd + AppConstants.spaceXs,
        AppConstants.spaceMd,
        AppConstants.spaceMd,
        AppConstants.spaceSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: onSurface,
              ),
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 13,
              color: onSurface.withValues(alpha: AppConstants.mutedAlpha),
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupCard(List<TrashItem> items, Color fg, Color bg) {
    final divider = Color.lerp(bg, fg, AppConstants.dividerBlend)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceMd),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: AppConstants.spaceMd,
                  endIndent: AppConstants.spaceMd,
                  color: divider,
                ),
              _row(items[i], fg, bg),
            ],
          ],
        ),
      ),
    );
  }

  Widget _empty(IconData icon, String text) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppConstants.emptyStateIconSize, color: muted),
          const SizedBox(height: AppConstants.spaceSm),
          Text(text, style: theme.textTheme.titleMedium?.copyWith(color: muted)),
        ],
      ),
    );
  }

  Widget _body(Color fg, Color bg) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_all.isEmpty) return _empty(Icons.delete_outline, 'Trash is empty');

    final filtered = _filtered;
    final groups = _groups(filtered);

    return Column(
      children: [
        _searchBar(fg, bg),
        Expanded(
          child: filtered.isEmpty
              ? _empty(
                  Icons.search_off,
                  'No results for "${_search.text.trim()}"',
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: AppConstants.spaceMd),
                  children: [
                    for (final g in groups) ...[
                      _dayHeader(g.$1, g.$2.length),
                      _groupCard(g.$2, fg, bg),
                    ],
                  ],
                ),
        ),
        // Fixed at the bottom of the screen, it doesn't scroll with the list.
        SafeArea(top: false, child: _banner(fg, bg)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline),
            SizedBox(width: AppConstants.spaceSm),
            Text('Trash'),
          ],
        ),
        actions: [
          if (_all.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Empty trash',
              onPressed: _busy ? null : _emptyTrash,
            ),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(AppConstants.progressBarHeight),
                child: LinearProgressIndicator(
                  minHeight: AppConstants.progressBarHeight,
                ),
              )
            : null,
      ),
      body: _body(accent.foreground, accent.background),
    );
  }
}