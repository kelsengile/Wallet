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

  Color _typeColor(ThemeData theme) =>
      _isIncome ? Colors.green.shade600 : Colors.red.shade600;

  Color _typeBgColor() => _isIncome ? Colors.green.shade50 : Colors.red.shade50;

  bool get _isOverdue {
    final due = DateTime.tryParse(_reminder.dueDate);
    if (due == null) return false;
    final now = DateTime.now();
    return due.isBefore(DateTime(now.year, now.month, now.day));
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
    final typeBg = _typeBgColor();
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Receipt card ────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: isDark ? theme.colorScheme.surfaceContainer : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Colored header ───────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
                    decoration: BoxDecoration(
                      color:
                          isDark ? typeColor.withValues(alpha: 0.25) : typeBg,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Bell badge
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFF59E0B).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _reminder.isDone
                                ? Icons.notifications_off_outlined
                                : Icons.notifications_active_rounded,
                            color: const Color(0xFFF59E0B),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // "REMINDER" label
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B)
                                      .withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'REMINDER',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                    color: const Color(0xFFF59E0B),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _reminder.title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: typeColor,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Overdue chip
                              if (_isOverdue && !_reminder.isDone)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.orange.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.warning_amber_rounded,
                                          size: 12,
                                          color: Colors.orange.shade700),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Overdue',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.orange.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (_reminder.isDone)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle_rounded,
                                          size: 12,
                                          color: Colors.green.shade700),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Done',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Body ────────────────────────────────────────────────
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      child: _ReminderReceiptBody(
                        reminder: _reminder,
                        accounts: widget.accounts,
                        txCategories: widget.txCategories,
                        theme: theme,
                        typeColor: typeColor,
                      ),
                    ),
                  ),

                  // ── Action buttons ───────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Mark done / undo done
                        if (!_reminder.isDone)
                          SizedBox(
                            width: double.infinity,
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
                                backgroundColor: Colors.green.shade600,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        if (!_reminder.isDone) const SizedBox(height: 8),
                        Row(
                          children: [
                            // Delete
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final confirm = await _confirmDelete(context);
                                  if (!confirm || !context.mounted) return;
                                  if (widget.onDelete != null) {
                                    await widget.onDelete!(_reminder);
                                  }
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }
                                },
                                icon:
                                    const Icon(Icons.delete_outline, size: 18),
                                label: const Text('Delete'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red.shade600,
                                  side: BorderSide(color: Colors.red.shade200),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 11),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Edit
                            Expanded(
                              child: FilledButton.icon(
                                onPressed:
                                    widget.onEdited != null ? _openEdit : null,
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                label: const Text('Edit'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFF59E0B),
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 11),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
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

          // ── Close button ─────────────────────────────────────────────────
          Positioned(
            top: -14,
            right: -14,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: theme.colorScheme.outlineVariant, width: 1.5),
                ),
                child: Icon(
                  Icons.close,
                  size: 18,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

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
        ? DateFormat('MMM d, yyyy')
            .format(DateTime.tryParse(reminder.dueDate) ?? DateTime.now())
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
