import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../models/account_model.dart';
import '../models/category_model.dart';
import '../database/database_helper.dart';
import '../currency.dart';

// ── Formatter ──────────────────────────────────────────────────────────────────

final _currencyFmt = NumberFormat('#,##0.00', 'en_PH');
String _fmt(double v) => _currencyFmt.format(v);

// ── Ref extractor ─────────────────────────────────────────────────────────────

String? _extractRef(String? note) {
  if (note == null) return null;
  final match = RegExp(r'__ref:([^_]+)__').firstMatch(note);
  return match?.group(1);
}

String _cleanNote(String? note) =>
    (note ?? '').replaceAll(RegExp(r'\s*__ref:[^_]+__'), '').trim();

// ── Public API ────────────────────────────────────────────────────────────────

/// Shows a receipt-style centered dialog for any transaction type.
///
/// [tx] is the transaction to display. For transfers, pass either leg —
/// the dialog will resolve the paired account automatically.
///
/// [accounts] and [txCategories] / [accountTypes] / [accountCategories] are
/// the same lists you already pass to [WalletTransaction.showDialog]; they are
/// forwarded to the edit form when the pencil icon is tapped.
///
/// [onEdited] is called with the updated transaction after a successful edit,
/// so the caller can persist it. Pass `null` to make the receipt read-only.
///
/// Returns the updated [WalletTransaction] if an edit was saved, `null` otherwise.
Future<WalletTransaction?> showTransactionReceipt(
  BuildContext context, {
  required WalletTransaction tx,
  required List<Account> accounts,
  required List<WalletCategory> txCategories,
  required List<WalletCategory> accountTypes,
  required List<WalletCategory> accountCategories,
  List<String>? typeOrder,
  String? transferTitle,
  Future<WalletTransaction?> Function(WalletTransaction)? onEdited,
  Future<void> Function(TransferResult result, WalletTransaction outLeg,
          WalletTransaction inLeg)?
      onTransferEdited,
}) {
  return showDialog<WalletTransaction>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _TransactionReceiptDialog(
      tx: tx,
      accounts: accounts,
      txCategories: txCategories,
      accountTypes: accountTypes,
      accountCategories: accountCategories,
      typeOrder: typeOrder,
      transferTitle: transferTitle,
      onEdited: onEdited,
      onTransferEdited: onTransferEdited,
    ),
  );
}

// ── Receipt dialog widget ─────────────────────────────────────────────────────

class _TransactionReceiptDialog extends StatefulWidget {
  final WalletTransaction tx;
  final List<Account> accounts;
  final List<WalletCategory> txCategories;
  final List<WalletCategory> accountTypes;
  final List<WalletCategory> accountCategories;
  final List<String>? typeOrder;
  final String? transferTitle;
  final Future<WalletTransaction?> Function(WalletTransaction)? onEdited;
  final Future<void> Function(TransferResult result, WalletTransaction outLeg,
      WalletTransaction inLeg)? onTransferEdited;

  const _TransactionReceiptDialog({
    required this.tx,
    required this.accounts,
    required this.txCategories,
    required this.accountTypes,
    required this.accountCategories,
    this.typeOrder,
    this.transferTitle,
    this.onEdited,
    this.onTransferEdited,
  });

  @override
  State<_TransactionReceiptDialog> createState() =>
      _TransactionReceiptDialogState();
}

class _TransactionReceiptDialogState extends State<_TransactionReceiptDialog> {
  // Live transaction — may be updated after an edit.
  late WalletTransaction _tx;

  // Paired transfer leg (for transfer_out / transfer_in)
  WalletTransaction? _pairedLeg;
  bool _loadingPaired = false;

  @override
  void initState() {
    super.initState();
    _tx = widget.tx;
    if (_tx.type == 'transfer_out' || _tx.type == 'transfer_in') {
      _loadPairedLeg();
    }
  }

  Future<void> _loadPairedLeg() async {
    setState(() => _loadingPaired = true);
    final ref = _extractRef(_tx.note);
    if (ref != null) {
      final all = await DatabaseHelper.instance.getAllTransactions();
      final paired = all
          .where((t) {
            if (t.id == _tx.id) return false;
            if (_tx.type == 'transfer_out') return t.type == 'transfer_in';
            return t.type == 'transfer_out';
          })
          .where((t) => t.note?.contains('__ref:$ref') ?? false)
          .firstOrNull;
      if (mounted) setState(() => _pairedLeg = paired);
    }
    if (mounted) setState(() => _loadingPaired = false);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  bool get _isTransfer =>
      _tx.type == 'transfer_out' || _tx.type == 'transfer_in';
  bool get _isIncome => _tx.type == 'income';

  // ignore: unused_element
  Account _resolveAccount(int? id) => widget.accounts.firstWhere(
        (a) => a.id == id,
        orElse: () => Account(
            name: 'Unknown', balance: 0, type: '', colorHex: '', icon: ''),
      );

  WalletCategory? _resolveCategory(String name) =>
      widget.txCategories.cast<WalletCategory?>().firstWhere(
            (c) => c?.name == name,
            orElse: () => null,
          );

  Color _typeColor(ThemeData theme) {
    if (_isTransfer) return const Color(0xFF2563EB);
    if (_isIncome) return Colors.green.shade600;
    return Colors.red.shade600;
  }

  Color _typeBgColor() {
    if (_isTransfer) return const Color(0xFFDBEAFE);
    if (_isIncome) return Colors.green.shade50;
    return Colors.red.shade50;
  }

  // ── Open edit form ────────────────────────────────────────────────────────

  Future<void> _openEdit() async {
    if (_isTransfer) {
      await _openTransferEdit();
      return;
    }

    final updated = await WalletTransaction.showDialog(
      context,
      accounts: widget.accounts,
      categories: widget.txCategories,
      accountTypes: widget.accountTypes,
      accountCategories: widget.accountCategories,
      existing: _tx,
      type: _tx.type,
      typeOrder: widget.typeOrder,
    );

    if (updated == null || !mounted) return;

    WalletTransaction? saved;
    if (widget.onEdited != null) {
      saved = await widget.onEdited!(updated);
    }

    setState(() => _tx = saved ?? updated);
    if (mounted) Navigator.pop(context, _tx);
  }

  Future<void> _openTransferEdit() async {
    // Determine which leg is out and which is in.
    final outLeg = _tx.type == 'transfer_out' ? _tx : (_pairedLeg ?? _tx);
    final inLeg = _tx.type == 'transfer_in' ? _tx : (_pairedLeg ?? _tx);

    final result = await WalletTransactionTransfer.showTransferDialog(
      context,
      accounts: widget.accounts,
      accountTypes: widget.accountTypes,
      typeOrder: widget.typeOrder,
      existing: outLeg,
      existingPaired: inLeg,
    );

    if (result == null || !mounted) return;

    if (widget.onTransferEdited != null) {
      await widget.onTransferEdited!(result, outLeg, inLeg);
    }

    // Reload the paired leg so the receipt reflects the change.
    await _loadPairedLeg();

    // Update the displayed leg with the new amount/note.
    final ref = result.existingRef ?? '';
    final noteWithRef = result.note.isEmpty
        ? '__ref:${ref}__'
        : '${result.note} __ref:${ref}__';
    setState(() {
      _tx = _tx.copyWith(
        amount: result.amount,
        note: noteWithRef,
        accountId: _tx.type == 'transfer_out'
            ? result.fromAccountId
            : result.toAccountId,
      );
    });

    if (mounted) Navigator.pop(context, _tx);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor = _typeColor(theme);
    final typeBg = _typeBgColor();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Receipt card ────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
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
                  // ── Coloured header ────────────────────────────────────
                  _ReceiptHeader(
                    tx: _tx,
                    typeColor: typeColor,
                    typeBg: typeBg,
                    isTransfer: _isTransfer,
                    isIncome: _isIncome,
                    accounts: widget.accounts,
                    pairedLeg: _pairedLeg,
                    loadingPaired: _loadingPaired,
                    txCategories: widget.txCategories,
                    transferTitle: widget.transferTitle,
                  ),

                  // ── Serrated divider ───────────────────────────────────
                  _SerratedDivider(
                    color: theme.colorScheme.surface,
                    bgColor: typeBg,
                  ),

                  // ── Body rows ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: _ReceiptBody(
                      tx: _tx,
                      accounts: widget.accounts,
                      pairedLeg: _pairedLeg,
                      isTransfer: _isTransfer,
                      theme: theme,
                      typeColor: typeColor,
                      resolveCategory: _resolveCategory,
                    ),
                  ),

                  // ── Close button ──────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Pencil FAB (top-right, outside the card) ───────────────────
          if (widget.onEdited != null || widget.onTransferEdited != null)
            Positioned(
              top: -14,
              right: -14,
              child: GestureDetector(
                onTap: _openEdit,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: typeColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: typeColor.withValues(alpha: 0.45),
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
}

// ── Receipt header ─────────────────────────────────────────────────────────────

class _ReceiptHeader extends StatelessWidget {
  final WalletTransaction tx;
  final Color typeColor;
  final Color typeBg;
  final bool isTransfer;
  final bool isIncome;
  final List<Account> accounts;
  final WalletTransaction? pairedLeg;
  final bool loadingPaired;
  final List<WalletCategory> txCategories;
  final String? transferTitle;

  const _ReceiptHeader({
    required this.tx,
    required this.typeColor,
    required this.typeBg,
    required this.isTransfer,
    required this.isIncome,
    required this.accounts,
    required this.pairedLeg,
    required this.loadingPaired,
    required this.txCategories,
    this.transferTitle,
  });

  // ignore: unused_element
  Account _resolve(int? id) => accounts.firstWhere(
        (a) => a.id == id,
        orElse: () => Account(
            name: 'Unknown', balance: 0, type: '', colorHex: '', icon: ''),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // ── Icon
    IconData icon;

    String title;
    Color titleColor;
    if (isTransfer) {
      final isOut = tx.type == 'transfer_out';
      icon = isOut ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
      title = transferTitle ?? (isOut ? 'Transfer Out' : 'Transfer In');
      titleColor = typeColor;
    } else {
      final cat = txCategories.cast<WalletCategory?>().firstWhere(
            (c) => c?.name == tx.category,
            orElse: () => null,
          );
      icon = cat?.iconData ?? iconForKey(tx.category);
      title = _typeLabel(tx.type);
      titleColor = typeColor;
    }

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

          // Title
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: titleColor,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'income':
        return 'Income';
      case 'expense':
        return 'Expense';
      case 'transfer_out':
        return 'Transfer Out';
      case 'transfer_in':
        return 'Transfer In';
      default:
        return type;
    }
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

// ── Receipt body rows ──────────────────────────────────────────────────────────

class _ReceiptBody extends StatelessWidget {
  final WalletTransaction tx;
  final List<Account> accounts;
  final WalletTransaction? pairedLeg;
  final bool isTransfer;
  final ThemeData theme;
  final Color typeColor;
  final WalletCategory? Function(String) resolveCategory;

  const _ReceiptBody({
    required this.tx,
    required this.accounts,
    required this.pairedLeg,
    required this.isTransfer,
    required this.theme,
    required this.typeColor,
    required this.resolveCategory,
  });

  Account _resolve(int? id) => accounts.firstWhere(
        (a) => a.id == id,
        orElse: () => Account(
            name: 'Unknown', balance: 0, type: '', colorHex: '', icon: ''),
      );

  @override
  Widget build(BuildContext context) {
    final userNote = _cleanNote(tx.note);
    final dateStr = tx.date.length >= 10
        ? DateFormat('MMM d, yyyy • h:mm a')
            .format(DateTime.tryParse(tx.date) ?? DateTime.now())
        : tx.date;

    final rows = <Widget>[];

    // ── Dashed rule at top ─────────────────────────────────────────────────
    rows.add(const SizedBox(height: 8));
    rows.add(_DashedDivider());
    rows.add(const SizedBox(height: 12));

    if (isTransfer) {
      // From account
      final fromAcct = tx.type == 'transfer_out'
          ? _resolve(tx.accountId)
          : (pairedLeg != null
              ? _resolve(pairedLeg!.accountId)
              : _resolve(null));
      // To account
      final toAcct = tx.type == 'transfer_in'
          ? _resolve(tx.accountId)
          : (pairedLeg != null
              ? _resolve(pairedLeg!.accountId)
              : _resolve(null));

      rows.add(_ReceiptRow(label: 'From', value: fromAcct.name, theme: theme));
      rows.add(_ReceiptRow(label: 'To', value: toAcct.name, theme: theme));
    } else {
      final account = _resolve(tx.accountId);
      final cat = resolveCategory(tx.category);

      rows.add(_ReceiptRow(
        label: 'Account',
        value: account.name,
        theme: theme,
      ));
      rows.add(_ReceiptRow(
        label: 'Category',
        value: tx.category,
        valueIcon: cat?.iconData,
        valueIconColor: typeColor,
        theme: theme,
      ));
    }

    rows.add(_ReceiptRow(label: 'Date', value: dateStr, theme: theme));

    // Note
    if (userNote.isNotEmpty) {
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
                  userNote,
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

    // ── Total row ──────────────────────────────────────────────────────────
    rows.add(Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'TOTAL',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: theme.colorScheme.onSurface,
          ),
        ),
        Text(
          '${currencySymbolNotifier.value}${_fmt(tx.amount)}',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: typeColor,
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

// ── Receipt row ────────────────────────────────────────────────────────────────

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? valueIcon;
  final Color? valueIconColor;
  final TextStyle? valueStyle;
  final ThemeData theme;

  const _ReceiptRow({
    required this.label,
    required this.value,
    required this.theme,
    this.valueIcon,
    this.valueIconColor,
    // ignore: unused_element_parameter
    this.valueStyle,
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
                    style: valueStyle ??
                        theme.textTheme.bodySmall?.copyWith(
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
