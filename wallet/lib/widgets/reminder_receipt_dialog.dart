import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/reminder_model.dart';
import '../models/account_model.dart';
import '../models/category_model.dart';
import '../currency.dart';

// ── Formatter ──────────────────────────────────────────────────────────────────

final _currencyFmt = NumberFormat('#,##0.00', 'en_PH');
String _fmt(double v) => _currencyFmt.format(v);

// ── Public API ────────────────────────────────────────────────────────────────

/// Shows a receipt-style dialog for a [ReminderTransaction].
///
/// [onEdited]   — called with the updated reminder after a successful edit.
/// [onDone]     — called when the user taps "Mark as Done".
/// [onDelete]   — called when the user taps the delete button.
///
/// Returns the updated [ReminderTransaction] if the reminder was edited, or
/// `null` if the dialog was dismissed without changes.
Future<ReminderTransaction?> showReminderReceipt(
  BuildContext context, {
  required ReminderTransaction reminder,
  required List<Account> accounts,
  required List<WalletCategory> txCategories,
  required List<WalletCategory> accountTypes,
  required List<WalletCategory> accountCategories,
  List<String>? typeOrder,
  Future<ReminderTransaction?> Function(ReminderTransaction)? onEdited,
  Future<void> Function(ReminderTransaction)? onDone,
  Future<void> Function(ReminderTransaction)? onDelete,
}) {
  return showDialog<ReminderTransaction>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _ReminderReceiptDialog(
      reminder: reminder,
      accounts: accounts,
      txCategories: txCategories,
      accountTypes: accountTypes,
      accountCategories: accountCategories,
      typeOrder: typeOrder,
      onEdited: onEdited,
      onDone: onDone,
      onDelete: onDelete,
    ),
  );
}

// ── Dialog widget ─────────────────────────────────────────────────────────────

class _ReminderReceiptDialog extends StatefulWidget {
  final ReminderTransaction reminder;
  final List<Account> accounts;
  final List<WalletCategory> txCategories;
  final List<WalletCategory> accountTypes;
  final List<WalletCategory> accountCategories;
  final List<String>? typeOrder;
  final Future<ReminderTransaction?> Function(ReminderTransaction)? onEdited;
  final Future<void> Function(ReminderTransaction)? onDone;
  final Future<void> Function(ReminderTransaction)? onDelete;

  const _ReminderReceiptDialog({
    required this.reminder,
    required this.accounts,
    required this.txCategories,
    required this.accountTypes,
    required this.accountCategories,
    this.typeOrder,
    this.onEdited,
    this.onDone,
    this.onDelete,
  });

  @override
  State<_ReminderReceiptDialog> createState() => _ReminderReceiptDialogState();
}

class _ReminderReceiptDialogState extends State<_ReminderReceiptDialog> {
  late ReminderTransaction _reminder;

  @override
  void initState() {
    super.initState();
    _reminder = widget.reminder;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool get _isIncome => _reminder.type == 'income';

  Color _typeColor(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return isDark ? const Color(0xFFFFD54F) : Colors.amber.shade700;
  }

  Color _typeBgColor(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return isDark
        ? const Color(0xFF3A2E00) // dark amber tint
        : Colors.amber.shade50;
  }

  // FAB uses a deeper amber so it reads as a button, not a neon glow.
  Color _fabColor(ThemeData theme) {
    if (theme.brightness != Brightness.dark) return _typeColor(theme);
    return const Color.fromARGB(255, 180, 171, 9); // amber-700 equivalent
  }

  // ── Open edit ─────────────────────────────────────────────────────────────

  Future<void> _openEdit() async {
    final updated = await ReminderTransaction.showDialog(
      context,
      accounts: widget.accounts,
      categories: widget.txCategories,
      accountTypes: widget.accountTypes,
      accountCategories: widget.accountCategories,
      existing: _reminder,
      typeOrder: widget.typeOrder,
    );

    if (updated == null || !mounted) return;

    ReminderTransaction? saved;
    if (widget.onEdited != null) {
      saved = await widget.onEdited!(updated);
    }

    setState(() => _reminder = saved ?? updated);
    if (mounted) Navigator.pop(context, _reminder);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor = _typeColor(theme);
    final typeBg = _typeBgColor(theme);
    final fabColor = _fabColor(theme);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Receipt card ──────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.45 : 0.18),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Coloured header ──────────────────────────────────────
                  _ReminderReceiptHeader(
                    reminder: _reminder,
                    typeColor: typeColor,
                    typeBg: typeBg,
                    isIncome: _isIncome,
                    txCategories: widget.txCategories,
                  ),

                  // ── Serrated divider ─────────────────────────────────────
                  _SerratedDivider(
                    color: theme.colorScheme.surface,
                    bgColor: typeBg,
                  ),

                  // ── Body rows ────────────────────────────────────────────
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      child: _ReminderReceiptBody(
                        reminder: _reminder,
                        accounts: widget.accounts,
                        txCategories: widget.txCategories,
                        theme: theme,
                        typeColor: typeColor,
                      ),
                    ),
                  ),

                  // ── Bottom action row ────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        // Mark as Done (only when not already done)
                        if (!_reminder.isDone)
                          SizedBox(
                            child: FilledButton.icon(
                              onPressed: () async {
                                if (widget.onDone != null) {
                                  await widget.onDone!(_reminder);
                                }
                                if (context.mounted) {
                                  Navigator.pop(context);
                                }
                              },
                              icon: const Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 18),
                              label: const Text('Mark as Done'),
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    theme.brightness == Brightness.dark
                                        ? const Color(0xFF166534)
                                        : Colors.green.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Pencil FAB (top-right, outside the card) ──────────────────────
          if (widget.onEdited != null)
            Positioned(
              top: -14,
              right: -14,
              child: GestureDetector(
                onTap: _openEdit,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: fabColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: fabColor.withValues(alpha: 0.45),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.edit_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete reminder?'),
            content: const Text('This reminder will be permanently deleted.'),
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
        ) ??
        false;
  }
}

// ── Receipt header ─────────────────────────────────────────────────────────────

class _ReminderReceiptHeader extends StatelessWidget {
  final ReminderTransaction reminder;
  final Color typeColor;
  final Color typeBg;
  final bool isIncome;
  final List<WalletCategory> txCategories;

  const _ReminderReceiptHeader({
    required this.reminder,
    required this.typeColor,
    required this.typeBg,
    required this.isIncome,
    required this.txCategories,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cat = txCategories.cast<WalletCategory?>().firstWhere(
          (c) => c?.name == reminder.category,
          orElse: () => null,
        );
    final icon = cat?.iconData ?? Icons.notifications_active_rounded;

    // Overdue chip colors
    final overdueText =
        isDark ? const Color(0xFFFFB74D) : Colors.orange.shade700;
    final overdueBg = isDark
        ? Colors.orange.withValues(alpha: 0.20)
        : Colors.orange.withValues(alpha: 0.15);

    // Done chip colors
    final doneText = isDark ? const Color(0xFF4ADE80) : Colors.green.shade700;
    final doneBg = isDark
        ? Colors.green.withValues(alpha: 0.20)
        : Colors.green.withValues(alpha: 0.15);

    return Container(
      width: double.infinity,
      color: typeBg,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      child: Column(
        children: [
          // Icon circle
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                  color: typeColor.withValues(alpha: 0.35), width: 2),
            ),
            child: Icon(icon, color: typeColor, size: 30),
          ),
          const SizedBox(height: 14),

          // Reminder title
          if (reminder.title.isNotEmpty) ...[
            Text(
              reminder.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
          ],

          // Type label + status chips
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Reminder',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: typeColor,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),

          if (_isOverdue(reminder) && !reminder.isDone) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: overdueBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 12, color: overdueText),
                  const SizedBox(width: 4),
                  Text(
                    'Overdue',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: overdueText,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (reminder.isDone) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: doneBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 12, color: doneText),
                  const SizedBox(width: 4),
                  Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: doneText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isOverdue(ReminderTransaction r) {
    final due = DateTime.tryParse(r.dueDate);
    if (due == null) return false;
    final now = DateTime.now();
    return due.isBefore(DateTime(now.year, now.month, now.day));
  }
}

// ── Serrated divider ───────────────────────────────────────────────────────────
//
// Creates the classic receipt "tear" edge between the header and the body.

class _SerratedDivider extends StatelessWidget {
  final Color color; // card surface color (the "cut-out")
  final Color bgColor; // header background color

  const _SerratedDivider({required this.color, required this.bgColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: CustomPaint(
        painter: _SerratedPainter(surfaceColor: color, bgColor: bgColor),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SerratedPainter extends CustomPainter {
  final Color surfaceColor;
  final Color bgColor;

  const _SerratedPainter({required this.surfaceColor, required this.bgColor});

  @override
  void paint(Canvas canvas, Size size) {
    // Fill top half with header bg color
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height / 2),
      Paint()..color = bgColor,
    );
    // Fill bottom half with card surface
    canvas.drawRect(
      Rect.fromLTWH(0, size.height / 2, size.width, size.height / 2),
      Paint()..color = surfaceColor,
    );

    // Draw scalloped circles along the middle
    const r = 9.0;
    final paint = Paint()..color = surfaceColor;
    double x = -r;
    while (x < size.width + r) {
      canvas.drawCircle(Offset(x, size.height / 2), r, paint);
      x += r * 2;
    }
  }

  @override
  bool shouldRepaint(_SerratedPainter old) =>
      old.surfaceColor != surfaceColor || old.bgColor != bgColor;
}

// ── Receipt body ──────────────────────────────────────────────────────────────

class _ReminderReceiptBody extends StatelessWidget {
  final ReminderTransaction reminder;
  final List<Account> accounts;
  final List<WalletCategory> txCategories;
  final ThemeData theme;
  final Color typeColor;

  const _ReminderReceiptBody({
    required this.reminder,
    required this.accounts,
    required this.txCategories,
    required this.theme,
    required this.typeColor,
  });

  Account _resolveAccount(int? id) => accounts.firstWhere(
        (a) => a.id == id,
        orElse: () => Account(
            name: 'Unknown', balance: 0, type: '', colorHex: '', icon: ''),
      );

  WalletCategory? _resolveCategory(String name) =>
      txCategories.cast<WalletCategory?>().firstWhere(
            (c) => c?.name == name,
            orElse: () => null,
          );

  @override
  Widget build(BuildContext context) {
    final dueDateStr = reminder.dueDate.length >= 10
        ? () {
            final dt = DateTime.tryParse(reminder.dueDate) ?? DateTime.now();
            return DateFormat('MMM d, yyyy, EEE').format(dt);
          }()
        : reminder.dueDate;

    final cat = _resolveCategory(reminder.category);
    final rows = <Widget>[];

    rows.add(const SizedBox(height: 8));
    rows.add(_DashedDivider());
    rows.add(const SizedBox(height: 12));

    // Type
    rows.add(_ReceiptRow(
      label: 'Type',
      value: reminder.type == 'income' ? 'Income' : 'Expense',
      theme: theme,
    ));

    // Category
    rows.add(_ReceiptRow(
      label: 'Category',
      value: reminder.category,
      valueIcon: cat?.iconData,
      valueIconColor: typeColor,
      theme: theme,
    ));

    // Due date
    rows.add(_ReceiptRow(
      label: 'Due date',
      value: dueDateStr,
      theme: theme,
    ));

    // Repeat
    if (reminder.repeat != ReminderRepeat.none) {
      rows.add(_ReceiptRow(
        label: 'Repeat',
        value: reminder.repeat.label,
        valueIcon: reminder.repeat.icon,
        valueIconColor: typeColor,
        theme: theme,
      ));
    }

    // Account
    if (reminder.accountId != null) {
      final acct = _resolveAccount(reminder.accountId);
      rows.add(_ReceiptRow(
        label: 'Account',
        value: acct.name,
        theme: theme,
      ));
    }

    // Note
    if (reminder.note != null && reminder.note!.isNotEmpty) {
      rows.add(const SizedBox(height: 4));
      rows.add(_DashedDivider());
      rows.add(const SizedBox(height: 8));
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  'Note',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reminder.note!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      );
    }

    rows.add(const SizedBox(height: 12));
    rows.add(_DashedDivider());
    rows.add(const SizedBox(height: 16));

    // ── Amount row ─────────────────────────────────────────────────────────
    final hasAmount = reminder.amount > 0;
    rows.add(Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'AMOUNT',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: theme.colorScheme.onSurface,
          ),
        ),
        Text(
          hasAmount
              ? '${currencySymbolNotifier.value}${_fmt(reminder.amount)}'
              : '—',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: hasAmount ? typeColor : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ));
    rows.add(const SizedBox(height: 16));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }
}

// ── Reusable receipt row ───────────────────────────────────────────────────────

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? valueIcon;
  final Color? valueIconColor;
  final ThemeData theme;

  const _ReceiptRow({
    required this.label,
    required this.value,
    required this.theme,
    this.valueIcon,
    this.valueIconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (valueIcon != null) ...[
                  Icon(valueIcon, size: 12, color: valueIconColor),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    value,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dashed divider ─────────────────────────────────────────────────────────────

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedLinePainter(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
      child: const SizedBox(width: double.infinity, height: 1),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashW = 5.0;
    const gapW = 4.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashW, 0), paint);
      x += dashW + gapW;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}
