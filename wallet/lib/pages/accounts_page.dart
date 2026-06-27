import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../currency.dart';
import '../database/database_helper.dart';
import '../models/account_model.dart';
import '../models/transaction_model.dart';
import '../models/category_model.dart';
import '../widgets/transaction_receipt_dialog.dart';

// ── Number formatter ───────────────────────────────────────────────────────────

final _currencyFmt = NumberFormat('#,##0.00', 'en_PH');

String _fmt(double v) => _currencyFmt.format(v);

// ── Type metadata ──────────────────────────────────────────────────────────────
//
// All account-type colors, icons, gradients, and labels now come from the
// CategoryRegistry (loaded from the DB), so changes in the Category Manager
// are immediately reflected on account cards. The registry is stored in a
// module-level notifier so widgets at any depth can rebuild when it updates.

// ── Filter modes (shared with _AccountDetailSheet) ────────────────────────────
enum _FilterMode { daily, weekly, monthly, yearly, allTime, custom }

final _registryNotifier =
    ValueNotifier<CategoryRegistry>(CategoryRegistry.empty());

/// True while a receipt dialog or edit-account dialog is open.
/// When true, account cards in the carousel cannot be flipped.
final _cardFlipLockedNotifier = ValueNotifier<bool>(false);

/// Loads the latest registry from the DB and pushes it into [_registryNotifier].
Future<void> _refreshRegistry() async {
  final reg = await DatabaseHelper.instance.getCategoryRegistry();
  _registryNotifier.value = reg;
}

// ── Page ───────────────────────────────────────────────────────────────────────

class AccountsPage extends StatefulWidget {
  final VoidCallback? onNavigateToAnalytics;

  const AccountsPage({super.key, this.onNavigateToAnalytics});

  @override
  State<AccountsPage> createState() => AccountsPageState();
}

class AccountsPageState extends State<AccountsPage> {
  final _db = DatabaseHelper.instance;
  List<Account> _accounts = [];
  Map<String, List<Account>> _grouped = {};

  /// Ordered list of account type keys — user can reorder these.
  List<String> _typeOrder = [];

  double _totalBalance = 0;
  double _totalIncome = 0;
  double _totalExpenses = 0;
  bool _loading = true;

  /// Whether reorder mode is active (drag handles visible, drag delay short)
  bool _reorderMode = false;

  /// Which type section is currently being dragged (for section drag)
  String? _draggingSectionType;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> refresh() => _loadAccounts();

  Future<void> _loadAccounts() async {
    // Accounts are fetched in most-recent-transaction order so that within
    // each type section the card with the latest activity appears first.
    final accounts = await _db.getAccountsSortedByLatestTransaction();
    final income = await _db.getTotalIncome();
    final expenses = await _db.getTotalExpenses();
    await _refreshRegistry(); // keep the registry in sync with DB
    if (!mounted) return;

    final grouped = <String, List<Account>>{};
    double total = 0;
    for (final a in accounts) {
      total += a.balance;
      (grouped[a.type] ??= []).add(a);
    }

    // On first load, restore persisted type order from DB.
    // On subsequent loads, keep the in-memory order (already updated by drag).
    List<String> newOrder;
    if (_typeOrder.isEmpty) {
      final saved = await _db.getTypeOrder();
      if (saved != null) {
        newOrder = saved;
      } else {
        // First-ever run: seed order from the categories table sort_order
        // so it matches the Category Manager sequence, not transaction recency.
        final registryTypes = _registryNotifier.value.accountTypes
            .map((c) => c.name)
            .where((t) => grouped.containsKey(t))
            .toList();
        // Append any account types that exist but aren't in the registry yet.
        final extra =
            grouped.keys.where((t) => !registryTypes.contains(t)).toList();
        newOrder = [...registryTypes, ...extra];
      }
    } else {
      newOrder = List.of(_typeOrder);
    }

    // Remove types no longer present, append any new types not yet in order.
    newOrder = newOrder.where((t) => grouped.containsKey(t)).toList();
    for (final t in grouped.keys) {
      if (!newOrder.contains(t)) newOrder.add(t);
    }

    setState(() {
      _accounts = accounts;
      _grouped = grouped;
      _typeOrder = newOrder;
      _totalBalance = total;
      _totalIncome = income;
      _totalExpenses = expenses;
      _loading = false;
    });
  }

  /// Instantly updates the balance of [accountId] by [delta] in the UI
  /// without a DB round-trip. Call this right after inserting a transaction
  /// so the account card reflects the new balance immediately.
  void applyBalanceDelta(int accountId, double delta) {
    setState(() {
      _accounts = _accounts.map((a) {
        if (a.id != accountId) return a;
        return a.copyWith(balance: a.balance + delta);
      }).toList();

      // Rebuild _grouped from the updated _accounts list.
      final grouped = <String, List<Account>>{};
      double total = 0;
      for (final a in _accounts) {
        total += a.balance;
        (grouped[a.type] ??= []).add(a);
      }
      _grouped = grouped;
      _totalBalance = total;

      if (delta > 0) {
        _totalIncome += delta;
      } else {
        _totalExpenses += -delta;
      }
    });
  }

  /// Convenience for a transfer: debits [fromId] and credits [toId].
  void applyTransferDelta(int fromId, int toId, double amount) {
    setState(() {
      _accounts = _accounts.map((a) {
        if (a.id == fromId) return a.copyWith(balance: a.balance - amount);
        if (a.id == toId) return a.copyWith(balance: a.balance + amount);
        return a;
      }).toList();

      final grouped = <String, List<Account>>{};
      double total = 0;
      for (final a in _accounts) {
        total += a.balance;
        (grouped[a.type] ??= []).add(a);
      }
      _grouped = grouped;
      _totalBalance = total;
      // Net balance unchanged for a transfer, but individual cards update.
    });
  }

  void _showAddAccountDialog({Account? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _AccountFormSheet(
        existing: existing,
        onSave: (account) async {
          if (existing != null) {
            await _db.updateAccount(account);
          } else {
            await _db.insertAccount(account);
          }
          if (ctx.mounted) Navigator.pop(ctx);
          _loadAccounts();
        },
      ),
    );
  }

  Future<void> _deleteAccount(Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteAccountDialog(account: account),
    );
    if (confirmed == true && account.id != null) {
      await _db.deleteAccount(account.id!);
      _loadAccounts();
    }
  }

  void _showAccountDetail(Account account) {
    final cardKey = GlobalKey<_FloatingDetailCardState>();

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (dialogCtx, _, __) {
        return _AccountDetailDialog(
          account: account,
          cardKey: cardKey,
          onTransactionChanged: _loadAccounts,
          onEditAccount: (a, detailCtx) {
            _cardFlipLockedNotifier.value = true;
            _showEditAndRefreshDetail(
              a,
              detailCtx,
              cardKey: cardKey,
              onClose: () {
                cardKey.currentState?.undimForReceipt();
                _cardFlipLockedNotifier.value = false;
              },
            );
          },
          onReceiptOpen: () => cardKey.currentState?.dimForReceipt(),
          onReceiptClose: () => cardKey.currentState?.undimForReceipt(),
          onEditOpen: () {
            cardKey.currentState?.dimForReceipt();
            _cardFlipLockedNotifier.value = true;
          },
        );
      },
    );
  }

  void _showEditAndRefreshDetail(
    Account account,
    BuildContext detailCtx, {
    GlobalKey<_FloatingDetailCardState>? cardKey,
    VoidCallback? onClose,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _AccountFormSheet(
        existing: account,
        onSave: (updated) async {
          await _db.updateAccount(updated);
          // Push the updated account to the floating card immediately so it
          // reflects the new data (name, note header/body, color, etc.) without
          // waiting for the overlay to be removed and rebuilt.
          cardKey?.currentState?.updateAccount(updated);
          // Refresh registry so color-sensitive widgets rebuild everywhere.
          await _refreshRegistry();
          if (ctx.mounted) Navigator.pop(ctx); // close edit form
          if (detailCtx.mounted) Navigator.pop(detailCtx); // close detail sheet
          _loadAccounts(); // reload cards list
        },
        onDelete: () async {
          if (detailCtx.mounted) Navigator.pop(detailCtx); // close detail sheet
          _loadAccounts();
        },
      ),
    ).whenComplete(() => onClose?.call());
  }

  // ── Card dragged to a different section (type change) ──────────────────────

  Future<void> _moveCardToType(Account account, String newType) async {
    if (account.type == newType) return;
    final colorHex = _registryNotifier.value.typeColorHex(newType);
    final updated = account.copyWith(
      type: newType,
      colorHex: colorHex,
    );
    await _db.updateAccount(updated);
    _loadAccounts();
  }

  // ── Section reorder ────────────────────────────────────────────────────────

  void _onSectionReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _typeOrder.removeAt(oldIndex);
      _typeOrder.insert(newIndex, item);
    });
    // Persist the new order so it survives app restarts.
    _db.saveTypeOrder(_typeOrder);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // ── Pinned hero — does not scroll ─────────────────────────────
        _TotalBalanceHero(
          totalBalance: _totalBalance,
          accountCount: _accounts.length,
          totalIncome: _totalIncome,
          totalExpenses: _totalExpenses,
          onAddAccount: _showAddAccountDialog,
          onNavigateToAnalytics: widget.onNavigateToAnalytics,
        ),

        // ── "My Accounts" header — pinned, does not scroll ────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('My Accounts',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  IconButton(
                    onPressed: _reorderMode ? null : _showAddAccountDialog,
                    icon: const Icon(Icons.add),
                    tooltip: 'Add account',
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                  ),
                  // Reorder mode toggle
                  if (_accounts.isNotEmpty)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: _reorderMode
                            ? theme.colorScheme.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: IconButton(
                        onPressed: () =>
                            setState(() => _reorderMode = !_reorderMode),
                        icon: Icon(
                          _reorderMode
                              ? Icons.check_rounded
                              : Icons.reorder_rounded,
                          size: 20,
                          color: _reorderMode
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        tooltip: _reorderMode
                            ? 'Done reordering'
                            : 'Reorder sections & cards',
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        // ── Scrollable accounts list ───────────────────────────────────
        Expanded(
          child: CustomScrollView(
            slivers: [
              // ── Empty state ───────────────────────────────────────────────
              if (_accounts.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.account_balance_wallet_outlined,
                            size: 56, color: theme.colorScheme.outlineVariant),
                        const SizedBox(height: 12),
                        Text('No accounts yet',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(color: theme.colorScheme.outline)),
                        const SizedBox(height: 4),
                        Text('Tap " + " to create your first account',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outlineVariant)),
                      ],
                    ),
                  ),
                )
              else
                // ── Reorderable list of type sections ──────────────────────
                SliverToBoxAdapter(
                  child: _DraggableSectionList(
                    typeOrder: _typeOrder,
                    grouped: _grouped,
                    draggingSectionType: _draggingSectionType,
                    reorderMode: _reorderMode,
                    onSectionReorder: _onSectionReorder,
                    onSectionDragStart: (t) =>
                        setState(() => _draggingSectionType = t),
                    onSectionDragEnd: () =>
                        setState(() => _draggingSectionType = null),
                    onCardMoveToType: _moveCardToType,
                    onCardTap: _showAccountDetail,
                    onCardDelete: _deleteAccount,
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Draggable section list ─────────────────────────────────────────────────────
//
// Handles reordering of type sections (long-press 2 s → drag).
// Each section internally allows card reordering and cross-section card drops.

class _DraggableSectionList extends StatefulWidget {
  final List<String> typeOrder;
  final Map<String, List<Account>> grouped;
  final String? draggingSectionType;
  final bool reorderMode;
  final void Function(int oldIndex, int newIndex) onSectionReorder;
  final void Function(String type) onSectionDragStart;
  final VoidCallback onSectionDragEnd;
  final void Function(Account account, String newType) onCardMoveToType;
  final void Function(Account) onCardTap;
  final void Function(Account) onCardDelete;

  const _DraggableSectionList({
    required this.typeOrder,
    required this.grouped,
    required this.draggingSectionType,
    required this.reorderMode,
    required this.onSectionReorder,
    required this.onSectionDragStart,
    required this.onSectionDragEnd,
    required this.onCardMoveToType,
    required this.onCardTap,
    required this.onCardDelete,
  });

  @override
  State<_DraggableSectionList> createState() => _DraggableSectionListState();
}

class _DraggableSectionListState extends State<_DraggableSectionList> {
  // Which section index is being hovered for drop target highlight
  int? _hoverSectionIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < widget.typeOrder.length; i++)
          _buildSectionWithDrop(i),
        // Drop zone after the last section (to move a section to the end)
        if (widget.draggingSectionType != null)
          _SectionDropZone(
            highlight: _hoverSectionIndex == widget.typeOrder.length,
            onWillAccept: (_) => true,
            onAccept: (_) {
              final fromIndex =
                  widget.typeOrder.indexOf(widget.draggingSectionType!);
              widget.onSectionReorder(fromIndex, widget.typeOrder.length);
              setState(() => _hoverSectionIndex = null);
            },
            onHover: (over) => setState(() =>
                _hoverSectionIndex = over ? widget.typeOrder.length : null),
          ),
      ],
    );
  }

  Widget _buildSectionWithDrop(int index) {
    final type = widget.typeOrder[index];
    final accounts = widget.grouped[type] ?? [];
    final isBeingDragged = widget.draggingSectionType == type;

    return Column(
      key: ValueKey('section_col_$type'),
      children: [
        // ── Drop zone above each section (for section reordering) ────
        if (widget.draggingSectionType != null &&
            widget.draggingSectionType != type)
          _SectionDropZone(
            highlight: _hoverSectionIndex == index,
            onWillAccept: (_) => true,
            onAccept: (_) {
              final fromIndex =
                  widget.typeOrder.indexOf(widget.draggingSectionType!);
              widget.onSectionReorder(fromIndex, index);
              setState(() => _hoverSectionIndex = null);
            },
            onHover: (over) =>
                setState(() => _hoverSectionIndex = over ? index : null),
          ),

        // ── The section itself ────────────────────────────────────────
        _DraggableSectionTile(
          type: type,
          accounts: accounts,
          isBeingDragged: isBeingDragged,
          reorderMode: widget.reorderMode,
          onSectionDragStart: () => widget.onSectionDragStart(type),
          onSectionDragEnd: widget.onSectionDragEnd,
          onCardDropped: (card) => widget.onCardMoveToType(card, type),
          onCardTap: widget.onCardTap,
          onCardDelete: widget.onCardDelete,
        ),
      ],
    );
  }
}

// ── Section drop zone (shown between sections during section drag) ────────────

class _SectionDropZone extends StatelessWidget {
  final bool highlight;
  final bool Function(String?) onWillAccept;
  final void Function(String?) onAccept;
  final void Function(bool) onHover;

  const _SectionDropZone({
    required this.highlight,
    required this.onWillAccept,
    required this.onAccept,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => onWillAccept(d.data),
      onAcceptWithDetails: (d) => onAccept(d.data),
      onMove: (_) => onHover(true),
      onLeave: (_) => onHover(false),
      builder: (_, candidateData, ___) {
        final active = highlight || candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: active ? 52 : 36,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? color.withValues(alpha: 0.7)
                  : color.withValues(alpha: 0.2),
              width: active ? 2 : 1.5,
              strokeAlign: BorderSide.strokeAlignCenter,
            ),
          ),
          alignment: Alignment.center,
          child: active
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.south_rounded, size: 13, color: color),
                    const SizedBox(width: 5),
                    Text(
                      'Drop section here',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 32,
                      height: 2,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

// ── Draggable section tile ─────────────────────────────────────────────────────

class _DraggableSectionTile extends StatefulWidget {
  final String type;
  final List<Account> accounts;
  final bool isBeingDragged;
  final bool reorderMode;
  final VoidCallback onSectionDragStart;
  final VoidCallback onSectionDragEnd;
  final void Function(Account) onCardDropped;
  final void Function(Account) onCardTap;
  final void Function(Account) onCardDelete;

  const _DraggableSectionTile({
    required this.type,
    required this.accounts,
    required this.isBeingDragged,
    required this.reorderMode,
    required this.onSectionDragStart,
    required this.onSectionDragEnd,
    required this.onCardDropped,
    required this.onCardTap,
    required this.onCardDelete,
  });

  @override
  State<_DraggableSectionTile> createState() => _DraggableSectionTileState();
}

class _DraggableSectionTileState extends State<_DraggableSectionTile> {
  bool _isDropTarget = false;

  Color _resolveTypeColor(BuildContext context) {
    final reg = _registryNotifier.value;
    final cat = reg.findAccountType(widget.type);
    if (cat != null) return cat.color;
    if (widget.accounts.isNotEmpty) {
      return colorFromHex(widget.accounts.first.colorHex);
    }
    return Theme.of(context).colorScheme.primary;
  }

  // Full section header row, shared by normal and collapsed builds
  Widget _buildHeader(BuildContext context, Color typeColor) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: widget.reorderMode
                  ? typeColor.withValues(alpha: 0.25)
                  : typeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_registryNotifier.value.typeIcon(widget.type),
                color: typeColor, size: 15),
          ),
          const SizedBox(width: 8),
          Text(
            _registryNotifier.value.typeLabel(widget.type),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: widget.reorderMode ? 1.0 : 0.3,
            child: Icon(
              Icons.drag_indicator,
              size: widget.reorderMode ? 22 : 16,
              color: widget.reorderMode
                  ? typeColor
                  : theme.colorScheme.outlineVariant,
            ),
          ),
        ],
      ),
    );
  }

  // Normal full-size content (header + carousel)
  Widget _buildSectionContent() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, _resolveTypeColor(context)),
          const SizedBox(height: 12),
          _DraggableCardCarousel(
            type: widget.type,
            accounts: widget.accounts,
            reorderMode: widget.reorderMode,
            onCardTap: widget.onCardTap,
            onCardDelete: widget.onCardDelete,
          ),
        ],
      ),
    );
  }

  // Compact header-only view used in the drag feedback ghost
  Widget _buildCompactContent() {
    final typeColor = _resolveTypeColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: _buildHeader(context, typeColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CategoryRegistry>(
      valueListenable: _registryNotifier,
      builder: (context, _, __) {
        final typeColor = _resolveTypeColor(context);

        // Inner content with drop-target highlight
        Widget sectionBody = AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: _isDropTarget
                ? Border.all(color: typeColor, width: 2)
                : Border.all(color: Colors.transparent, width: 2),
            color: _isDropTarget
                ? typeColor.withValues(alpha: 0.07)
                : Colors.transparent,
          ),
          child: _buildSectionContent(),
        );

        // Section reorder: only active in reorderMode; short 400 ms delay
        if (widget.reorderMode) {
          return LongPressDraggable<String>(
            data: widget.type,
            delay: const Duration(milliseconds: 400),
            onDragStarted: () {
              widget.onSectionDragStart();
              HapticFeedback.heavyImpact();
            },
            onDragEnd: (_) => widget.onSectionDragEnd(),
            onDraggableCanceled: (_, __) => widget.onSectionDragEnd(),
            // Feedback: compact header-only card that fits within the drop slots
            feedback: Material(
              color: Colors.transparent,
              child: Opacity(
                opacity: 0.95,
                child: SizedBox(
                  width: MediaQuery.of(context).size.width - 32,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: typeColor.withValues(alpha: 0.45),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                      border: Border.all(color: typeColor, width: 2),
                    ),
                    child: _buildCompactContent(),
                  ),
                ),
              ),
            ),
            // childWhenDragging: collapse height to 0 so the space disappears
            childWhenDragging: const SizedBox(height: 0),
            child: sectionBody,
          );
        }

        return sectionBody;
      },
    );
  }
}

// ── Draggable card carousel ────────────────────────────────────────────────────
//
// A horizontal list of account cards that can be reordered by long-press drag.
// Cards can also be dragged to other type sections.

// ── Draggable card carousel ────────────────────────────────────────────────────
//
// Horizontal list of account cards ordered by latest transaction date.
// Cards can still be dragged to other type sections (cross-section move).
// Within-section reordering is removed — order comes from the DB query.

class _DraggableCardCarousel extends StatefulWidget {
  final String type;
  final List<Account> accounts;
  final bool reorderMode;
  final void Function(Account) onCardTap;
  final void Function(Account) onCardDelete;

  const _DraggableCardCarousel({
    required this.type,
    required this.accounts,
    required this.reorderMode,
    required this.onCardTap,
    required this.onCardDelete,
  });

  @override
  State<_DraggableCardCarousel> createState() => _DraggableCardCarouselState();
}

class _DraggableCardCarouselState extends State<_DraggableCardCarousel> {
  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final typeColor = widget.accounts.isNotEmpty
        ? colorFromHex(widget.accounts.first.colorHex)
        : _registryNotifier.value.typeColor(widget.type);
    final n = widget.accounts.length;

    return SizedBox(
      height: 172,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        cacheExtent: 520,
        itemCount: n,
        itemBuilder: (_, i) {
          final a = widget.accounts[i];

          // ── REORDER MODE: inert card, no gesture handling ─────────────
          if (widget.reorderMode) {
            return Padding(
              padding: const EdgeInsets.only(right: 14),
              child: _AccountCardInert(account: a),
            );
          }

          // ── NORMAL MODE ───────────────────────────────────────────────
          return Padding(
            padding: const EdgeInsets.only(right: 14),
            child: _AccountCard(
              key: ValueKey('card_\${a.id}'),
              account: a,
              onTap: () => widget.onCardTap(a),
              onDelete: () => widget.onCardDelete(a),
            ),
          );
        },
      ),
    );
  }
}

// ── Hero header ────────────────────────────────────────────────────────────────

class _TotalBalanceHero extends StatelessWidget {
  final double totalBalance;
  final int accountCount;
  final double totalIncome;
  final double totalExpenses;
  final VoidCallback onAddAccount;
  final VoidCallback? onNavigateToAnalytics;

  const _TotalBalanceHero({
    required this.totalBalance,
    required this.accountCount,
    required this.totalIncome,
    required this.totalExpenses,
    required this.onAddAccount,
    this.onNavigateToAnalytics,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final tertiary = theme.colorScheme.tertiary;
    final isDark = theme.brightness == Brightness.dark;
    // Extend gradient behind the transparent top nav bar overlay.
    final topPadding = MediaQuery.paddingOf(context).top;

    final heroGradientColors = isDark
        ? [
            const Color(0xFF2A2A2E),
            const Color(0xFF3A3A40),
          ]
        : [primary, tertiary];

    final heroShadowColor = isDark
        ? Colors.black.withValues(alpha: 0.40)
        : primary.withValues(alpha: 0.35);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, topPadding + 80, 20, 36),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: heroGradientColors,
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: heroShadowColor,
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Balance',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.white70, letterSpacing: 0.5),
              ),
              Text(
                '$accountCount account${accountCount != 1 ? 's' : ''}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${currencySymbolNotifier.value} ${_fmt(totalBalance)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1.5,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onNavigateToAnalytics,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _IncomeExpenseCompact(
                        icon: Icons.arrow_upward,
                        amount: totalIncome,
                        color: const Color(0xFF4ADE80),
                      ),
                      Container(
                        width: 1,
                        height: 10,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                      _IncomeExpenseCompact(
                        icon: Icons.arrow_downward,
                        amount: totalExpenses,
                        color: const Color(0xFFF87171),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IncomeExpenseCompact extends StatelessWidget {
  final IconData icon;
  final double amount;
  final Color color;

  const _IncomeExpenseCompact({
    required this.icon,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 10),
        const SizedBox(width: 3),
        Text(
          '${currencySymbolNotifier.value} ${_fmt(amount)}',
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Polygon card clippers ─────────────────────────────────────────────────────
//
// Used when an account type has a polygon corner style (octagon / dodecagon).
// Applied via ClipPath wrapping the card Container.

class _OctagonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const cut = 22.0;
    return Path()
      ..moveTo(cut, 0)
      ..lineTo(size.width - cut, 0)
      ..lineTo(size.width, cut)
      ..lineTo(size.width, size.height - cut)
      ..lineTo(size.width - cut, size.height)
      ..lineTo(cut, size.height)
      ..lineTo(0, size.height - cut)
      ..lineTo(0, cut)
      ..close();
  }

  @override
  bool shouldReclip(_OctagonClipper old) => false;
}

class _DodecagonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    // Double-chamfer: two stair-step cuts per corner.
    // a = outer cut (first notch), b = inner cut (second notch, half the size).
    const a = 18.0;
    const b = 9.0;
    return Path()
      // Top edge: left corner double-chamfer → right corner double-chamfer
      ..moveTo(a, 0)
      ..lineTo(w - a, 0)
      // Top-right corner: step in, then step down
      ..lineTo(w - b, b)
      ..lineTo(w, b)
      // Right edge
      ..lineTo(w, h - b)
      // Bottom-right corner
      ..lineTo(w - b, h - b)
      ..lineTo(w - a, h)
      // Bottom edge
      ..lineTo(a, h)
      // Bottom-left corner
      ..lineTo(b, h - b)
      ..lineTo(0, h - b)
      // Left edge
      ..lineTo(0, b)
      // Top-left corner
      ..lineTo(b, b)
      ..close();
  }

  @override
  bool shouldReclip(_DodecagonClipper old) => false;
}

/// Wraps [child] with the correct clip for [cornerStyle] if it is a polygon
/// style, otherwise returns [child] unchanged.
Widget _applyCornerClip(String cornerStyle, Widget child) {
  switch (cornerStyle) {
    case kCornerStyleOctagon:
      return ClipPath(clipper: _OctagonClipper(), child: child);
    case kCornerStyleDodecagon:
      return ClipPath(clipper: _DodecagonClipper(), child: child);
    default:
      return child;
  }
}

// ── Account card (inert) ───────────────────────────────────────────────────────
//
// Pure visual card with zero gesture handling. Used in reorder mode as the
// LongPressDraggable child/feedback/ghost so there is no gesture conflict
// with the AnimationController inside _AccountCard.

class _AccountCardInert extends StatelessWidget {
  final Account account;
  const _AccountCardInert({required this.account});

  @override
  Widget build(BuildContext context) {
    final accountColor = account.colorHex.isNotEmpty
        ? colorFromHex(account.colorHex)
        : const Color(0xFF6366F1);
    final gradients = gradientForColor(accountColor);
    final registry = _registryNotifier.value;
    final cornerStyle = registry.typeCornerStyle(account.type);
    final br = registry.cardBorderRadius(account.type);

    Widget card = Container(
      width: 255,
      height: 155,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradients,
        ),
        borderRadius: isClipperCornerStyle(cornerStyle) ? null : br,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -22,
            top: -22,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.09),
              ),
            ),
          ),
          Positioned(
            left: -10,
            bottom: -22,
            child: Container(
              width: 75,
              height: 75,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    account.name,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${currencySymbolNotifier.value} ${_fmt(account.balance)}',
                  style: TextStyle(
                    color: account.balance >= 0
                        ? Colors.white
                        : Colors.red.shade200,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    account.category.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // Apply clipping: polygon styles use CustomClipper, others use ClipRRect.
    if (isClipperCornerStyle(cornerStyle)) {
      card = _applyCornerClip(cornerStyle, card);
    } else {
      card = ClipRRect(borderRadius: br, child: card);
    }
    return card;
  }
}

// ── Account card ───────────────────────────────────────────────────────────────
//
// Tap        → flip the card (front ↔ back)
// Long-press → view detail (opens _AccountDetailSheet which has edit button)
// Drag       → handled by LongPressDraggable in reorder mode (uses _AccountCardInert)

class _AccountCard extends StatefulWidget {
  final Account account;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _AccountCard({
    super.key,
    required this.account,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  bool _showingFront = true;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _anim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _flip() {
    if (_ctrl.isAnimating) return;
    // Do not allow flipping while a receipt or edit-account dialog is open.
    if (_cardFlipLockedNotifier.value) return;
    if (_showingFront) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
    setState(() => _showingFront = !_showingFront);
  }

  @override
  Widget build(BuildContext context) {
    final accountColor = widget.account.colorHex.isNotEmpty
        ? colorFromHex(widget.account.colorHex)
        : const Color(0xFF6366F1);
    final gradients = gradientForColor(accountColor);
    final registry = _registryNotifier.value;
    final cornerStyle = registry.typeCornerStyle(widget.account.type);
    final br = registry.cardBorderRadius(widget.account.type);

    // ── Front face ────────────────────────────────────────────────────────
    Widget frontFace = Container(
      width: 255,
      height: 155,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradients,
        ),
        borderRadius: isClipperCornerStyle(cornerStyle) ? null : br,
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            right: -22,
            top: -22,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.09),
              ),
            ),
          ),
          Positioned(
            left: -10,
            bottom: -22,
            child: Container(
              width: 75,
              height: 75,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          // Category icon (top-right corner)
          Positioned(
            top: 12,
            right: 12,
            child: ValueListenableBuilder<CategoryRegistry>(
              valueListenable: _registryNotifier,
              builder: (context, registry, _) {
                final catEntry = registry.accountCategories
                    .where((c) => c.name == widget.account.category)
                    .firstOrNull;
                final catIcon = catEntry?.iconData ?? Icons.folder_outlined;
                return Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(catIcon, color: Colors.white70, size: 15),
                );
              },
            ),
          ),
          // Card body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 36),
                  child: Text(
                    widget.account.name,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${currencySymbolNotifier.value} ${_fmt(widget.account.balance)}',
                  style: TextStyle(
                    color: widget.account.balance >= 0
                        ? Colors.white
                        : Colors.red.shade200,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.account.category.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // ── Back face ─────────────────────────────────────────────────────────
    Widget backFace = Container(
      width: 255,
      height: 155,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomRight,
          end: Alignment.topLeft,
          colors: gradients,
        ),
        borderRadius: isClipperCornerStyle(cornerStyle) ? null : br,
      ),
      child: Stack(
        children: [
          // Decorative circles (mirrored)
          Positioned(
            left: -22,
            top: -22,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.09),
              ),
            ),
          ),
          Positioned(
            right: -10,
            bottom: -22,
            child: Container(
              width: 75,
              height: 75,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          // Magnetic stripe bar
          Positioned(
            top: 28,
            left: 0,
            right: 0,
            child: Container(
              height: 32,
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
          // Back content
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 76, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Note header inside the signature strip box
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        (widget.account.noteHeader ?? '').isNotEmpty
                            ? widget.account.noteHeader!
                            : widget.account.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if ((widget.account.noteBody ?? '').isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        widget.account.noteBody!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 9,
                          fontWeight: FontWeight.w400,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
                // Type icon + tap-to-view button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ValueListenableBuilder<CategoryRegistry>(
                      valueListenable: _registryNotifier,
                      builder: (context, registry, _) {
                        return Icon(
                          registry.typeIcon(widget.account.type),
                          color: Colors.white70,
                          size: 14,
                        );
                      },
                    ),
                    GestureDetector(
                      onTap: widget.onTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.open_in_new,
                            size: 9, color: Colors.white),
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

    // Apply clipping to both faces
    if (isClipperCornerStyle(cornerStyle)) {
      frontFace = _applyCornerClip(cornerStyle, frontFace);
      backFace = _applyCornerClip(cornerStyle, backFace);
    } else {
      frontFace = ClipRRect(borderRadius: br, child: frontFace);
      backFace = ClipRRect(borderRadius: br, child: backFace);
    }

    return GestureDetector(
      onTap: _flip,
      onLongPress: widget.onTap,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, __) {
          final angle = _anim.value * math.pi;
          final isFrontVisible = angle <= math.pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: isFrontVisible
                ? frontFace
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: backFace,
                  ),
          );
        },
      ),
    );
  }
}

// ── Account add/edit form sheet ────────────────────────────────────────────────
//
// Extracted from the inline StatefulBuilder that used to live inside
// _showAddAccountDialog.  The key performance benefit: TextFields now have
// their own element subtree, so typing a character only rebuilds the
// TextField itself — NOT the Wrap of AnimatedContainer type/category tiles.
// Previously every keystroke called setS() on the whole bottom-sheet tree,
// forcing all 7 type tiles and 7 category chips to re-layout.

class _AccountFormSheet extends StatefulWidget {
  final Account? existing;
  final Future<void> Function(Account) onSave;
  final Future<void> Function()? onDelete;

  const _AccountFormSheet({this.existing, required this.onSave, this.onDelete});

  @override
  State<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends State<_AccountFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _balanceCtrl;
  late final TextEditingController _noteHeaderCtrl;
  late final TextEditingController _noteBodyCtrl;
  String? _selectedType;
  String? _selectedCategory;

  static const int _noteHeaderMaxChars = 30;
  static const int _noteBodyMaxChars = 120;

  // Loaded from DB so the form always reflects whatever the user has configured
  // in the Category Manager.
  List<WalletCategory> _accountTypes = [];
  List<WalletCategory> _accountCategoryItems = [];
  bool _registryLoaded = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _balanceCtrl = TextEditingController(
      text: e != null ? e.balance.toStringAsFixed(2) : '',
    );
    _noteHeaderCtrl = TextEditingController(text: e?.noteHeader ?? '');
    _noteBodyCtrl = TextEditingController(text: e?.noteBody ?? '');
    _selectedType = e?.type; // null = unset (new account)
    _selectedCategory = e?.category; // null = unset (new account)
    _loadRegistry();
  }

  Future<void> _loadRegistry() async {
    final registry = await DatabaseHelper.instance.getCategoryRegistry();
    if (!mounted) return;
    setState(() {
      _accountTypes = registry.accountTypes;
      _accountCategoryItems = registry.accountCategories;
      // For edit mode: snap to a valid value if the stored type/category was
      // deleted from the registry. For new accounts the values are null and
      // should stay null until the user actively picks.
      if (_selectedType != null &&
          _accountTypes.isNotEmpty &&
          !_accountTypes.any((t) => t.name == _selectedType)) {
        _selectedType = registry.defaultAccountType;
      }
      if (_selectedCategory != null &&
          _accountCategoryItems.isNotEmpty &&
          !_accountCategoryItems.any((c) => c.name == _selectedCategory)) {
        _selectedCategory = registry.defaultAccountCategory;
      }
      _registryLoaded = true;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    _noteHeaderCtrl.dispose();
    _noteBodyCtrl.dispose();
    super.dispose();
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;

    return SingleChildScrollView(
      // Use viewInsets here (inside the sheet) rather than outside — this
      // scopes the MediaQuery dependency to only this scroll view.
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            isEdit ? 'Edit Account' : 'New Account',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // ── Name field — isolated: typing here only rebuilds this widget ──
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Account Name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.label_outline),
            ),
          ),
          const SizedBox(height: 12),

          // Initial balance (add only)
          if (!isEdit) ...[
            TextField(
              controller: _balanceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
              ],
              decoration: InputDecoration(
                labelText: 'Initial Balance (${currencySymbolNotifier.value})',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Type & Category — side-by-side picker buttons ─────────────────
          if (!_registryLoaded)
            const Center(child: CircularProgressIndicator())
          else
            Row(
              children: [
                // Account Type button
                Expanded(
                  child: _PickerButton(
                    label: 'Type',
                    value: _selectedType != null
                        ? _capitalize(_selectedType!)
                        : null,
                    icon: _selectedType != null
                        ? _accountTypes
                            .firstWhere(
                              (t) => t.name == _selectedType,
                              orElse: () => _accountTypes.isNotEmpty
                                  ? _accountTypes.first
                                  : WalletCategory(
                                      name: _selectedType!,
                                      groupType: kCategoryGroupAccountType,
                                      icon: 'wallet',
                                      colorHex: '#6366F1',
                                    ),
                            )
                            .iconData
                        : null,
                    color: _selectedType != null
                        ? _accountTypes
                            .firstWhere(
                              (t) => t.name == _selectedType,
                              orElse: () => _accountTypes.isNotEmpty
                                  ? _accountTypes.first
                                  : WalletCategory(
                                      name: _selectedType!,
                                      groupType: kCategoryGroupAccountType,
                                      icon: 'wallet',
                                      colorHex: '#6366F1',
                                    ),
                            )
                            .color
                        : null,
                    onTap: () async {
                      final picked = await showModalBottomSheet<String>(
                        context: context,
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (ctx) => _TypePickerSheet(
                          title: 'Type',
                          items: _accountTypes,
                          selected: _selectedType,
                          capitalize: _capitalize,
                        ),
                      );
                      if (picked != null) {
                        setState(() => _selectedType = picked);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                // Category button
                Expanded(
                  child: _PickerButton(
                    label: 'Category',
                    value: _selectedCategory != null
                        ? _capitalize(_selectedCategory!)
                        : null,
                    icon: _selectedCategory != null
                        ? _accountCategoryItems
                            .firstWhere(
                              (c) => c.name == _selectedCategory,
                              orElse: () => _accountCategoryItems.isNotEmpty
                                  ? _accountCategoryItems.first
                                  : WalletCategory(
                                      name: _selectedCategory!,
                                      groupType: 'account_category',
                                      icon: 'folder',
                                      colorHex: '#6366F1',
                                    ),
                            )
                            .iconData
                        : null,
                    color: theme.colorScheme.primary,
                    onTap: () async {
                      final picked = await showModalBottomSheet<String>(
                        context: context,
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (ctx) => _CategoryPickerSheet(
                          title: 'Category',
                          items: _accountCategoryItems,
                          selected: _selectedCategory,
                          accentColor: theme.colorScheme.primary,
                          capitalize: _capitalize,
                        ),
                      );
                      if (picked != null) {
                        setState(() => _selectedCategory = picked);
                      }
                    },
                  ),
                ),
              ],
            ),
          const SizedBox(height: 20),

          // ── Note section ──────────────────────────────────────────────
          _NoteBox(
            headerController: _noteHeaderCtrl,
            bodyController: _noteBodyCtrl,
            headerMaxChars: _noteHeaderMaxChars,
            bodyMaxChars: _noteBodyMaxChars,
          ),
          const SizedBox(height: 20),

          // Submit
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: Icon(isEdit ? Icons.save : Icons.add),
              label: Text(isEdit ? 'Save Changes' : 'Add Account'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                if (_nameCtrl.text.trim().isEmpty) return;
                if (_selectedType == null || _selectedCategory == null) return;
                // Resolve the hex for the selected type from the loaded registry.
                final typeHex = _accountTypes
                    .firstWhere(
                      (t) => t.name == _selectedType,
                      orElse: () => _accountTypes.isNotEmpty
                          ? _accountTypes.first
                          : WalletCategory(
                              name: _selectedType!,
                              groupType: kCategoryGroupAccountType,
                              icon: 'wallet',
                              colorHex: '#6366F1',
                            ),
                    )
                    .colorHex;
                final account = isEdit
                    ? widget.existing!.copyWith(
                        name: _nameCtrl.text.trim(),
                        type: _selectedType!,
                        category: _selectedCategory!,
                        colorHex: typeHex,
                        noteHeader: _noteHeaderCtrl.text.trim(),
                        noteBody: _noteBodyCtrl.text.trim(),
                      )
                    : Account(
                        name: _nameCtrl.text.trim(),
                        balance:
                            double.tryParse(_balanceCtrl.text.trim()) ?? 0.0,
                        type: _selectedType!,
                        category: _selectedCategory!,
                        colorHex: typeHex,
                        icon: 'wallet',
                        noteHeader: _noteHeaderCtrl.text.trim(),
                        noteBody: _noteBodyCtrl.text.trim(),
                      );
                await widget.onSave(account);
              },
            ),
          ),

          // Delete button — only shown when editing an existing account
          if (isEdit && widget.existing?.id != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text(
                  'Delete Account',
                  style: TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Colors.red, width: 1.5),
                ),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => _DeleteAccountDialog(
                      account: widget.existing!,
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    await DatabaseHelper.instance
                        .deleteAccount(widget.existing!.id!);
                    if (context.mounted) Navigator.pop(context);
                    await widget.onDelete?.call();
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Picker button (shows selected value, opens a sub-modal) ───────────────────

class _PickerButton extends StatelessWidget {
  final String label;
  final String? value; // null = nothing picked yet
  final IconData? icon; // null = nothing picked yet
  final Color? color; // null = use outline/muted style
  final VoidCallback onTap;

  const _PickerButton({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSet = value != null;
    final iconColor = isSet
        ? color ?? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: theme.colorScheme.outline),
          ),
          prefixIcon: Icon(
            isSet ? icon : Icons.touch_app_outlined,
            color: iconColor,
            size: 18,
          ),
          suffixIcon: Icon(
            Icons.expand_more_rounded,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        ),
        isEmpty: !isSet,
        child: isSet
            ? Text(
                value!,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

// ── Combined note box (header + divider + body in one container) ───────────────
//
// Renders as a single OutlineInputBorder-style box with a floating "Note" label,
// matching the other form fields. The header and body are separated by a short
// divider that does not touch the left/right edges. Only the header row has an
// icon (notes/lines icon); the body row has none.

class _NoteBox extends StatefulWidget {
  final TextEditingController headerController;
  final TextEditingController bodyController;
  final int headerMaxChars;
  final int bodyMaxChars;

  const _NoteBox({
    required this.headerController,
    required this.bodyController,
    required this.headerMaxChars,
    required this.bodyMaxChars,
  });

  @override
  State<_NoteBox> createState() => _NoteBoxState();
}

class _NoteBoxState extends State<_NoteBox> {
  late int _headerCount;
  late int _bodyCount;
  final _headerFocus = FocusNode();
  final _bodyFocus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _headerCount = widget.headerController.text.length;
    _bodyCount = widget.bodyController.text.length;
    widget.headerController.addListener(_onHeaderChanged);
    widget.bodyController.addListener(_onBodyChanged);
    _headerFocus.addListener(_onFocusChanged);
    _bodyFocus.addListener(_onFocusChanged);
  }

  void _onHeaderChanged() {
    final n = widget.headerController.text.length;
    if (n != _headerCount) setState(() => _headerCount = n);
  }

  void _onBodyChanged() {
    final n = widget.bodyController.text.length;
    if (n != _bodyCount) setState(() => _bodyCount = n);
  }

  void _onFocusChanged() {
    final nowFocused = _headerFocus.hasFocus || _bodyFocus.hasFocus;
    if (nowFocused != _focused) setState(() => _focused = nowFocused);
  }

  @override
  void dispose() {
    widget.headerController.removeListener(_onHeaderChanged);
    widget.bodyController.removeListener(_onBodyChanged);
    _headerFocus.removeListener(_onFocusChanged);
    _bodyFocus.removeListener(_onFocusChanged);
    _headerFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  Color _counterColor(BuildContext context, int count, int max) {
    final remaining = max - count;
    if (remaining == 0) return Colors.red;
    if (remaining <= 10) return Colors.orange;
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Match OutlineInputBorder colours exactly
    final borderColor = _focused ? colorScheme.primary : colorScheme.outline;
    final borderWidth = _focused ? 2.0 : 1.0;
    final labelColor =
        _focused ? colorScheme.primary : colorScheme.onSurfaceVariant;

    // Whether any content exists (controls floating label like TextField does)
    final hasContent = _headerCount > 0 || _bodyCount > 0;
    final labelFloated = _focused || hasContent;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── Outlined container ───────────────────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header input row ─────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.notes_rounded,
                        size: 18, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: widget.headerController,
                        focusNode: _headerFocus,
                        maxLines: 1,
                        maxLength: widget.headerMaxChars,
                        buildCounter: (_,
                                {required currentLength,
                                required isFocused,
                                maxLength}) =>
                            null,
                        textCapitalization: TextCapitalization.sentences,
                        style: theme.textTheme.bodyMedium,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                          isDense: true,
                        ),
                      ),
                    ),
                    Text(
                      '$_headerCount / ${widget.headerMaxChars}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _counterColor(
                            context, _headerCount, widget.headerMaxChars),
                        fontWeight: (widget.headerMaxChars - _headerCount) <= 10
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Inset divider (does not touch the outer border) ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Divider(
                    height: 1, thickness: 1, color: colorScheme.outlineVariant),
              ),

              // ── Body input row ───────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: widget.bodyController,
                        focusNode: _bodyFocus,
                        maxLines: 3,
                        minLines: 2,
                        maxLength: widget.bodyMaxChars,
                        buildCounter: (_,
                                {required currentLength,
                                required isFocused,
                                maxLength}) =>
                            null,
                        textCapitalization: TextCapitalization.sentences,
                        style: theme.textTheme.bodyMedium,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                          isDense: true,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        '$_bodyCount / ${widget.bodyMaxChars}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: _counterColor(
                              context, _bodyCount, widget.bodyMaxChars),
                          fontWeight: (widget.bodyMaxChars - _bodyCount) <= 10
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Floating "Note" label — sits on top of the border ───────
        Positioned(
          left: labelFloated ? 10 : 42,
          top: labelFloated ? -10 : 14,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: labelFloated
                ? theme.textTheme.bodySmall!.copyWith(
                    color: labelColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  )
                : theme.textTheme.bodyMedium!.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            child: Container(
              // White/surface background to cut through the border line
              color: theme.colorScheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: const Text('Note'),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Account Type picker sheet ──────────────────────────────────────────────────

class _TypePickerSheet extends StatelessWidget {
  final String title;
  final List<WalletCategory> items;
  final String? selected;
  final String Function(String) capitalize;

  const _TypePickerSheet({
    required this.title,
    required this.items,
    required this.selected,
    required this.capitalize,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: items.map((t) {
                final isSelected = t.name == selected;
                final color = t.color;
                return GestureDetector(
                  onTap: () => Navigator.pop(context, t.name),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withValues(alpha: 0.15)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? color : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(t.iconData,
                            color: isSelected
                                ? color
                                : theme.colorScheme.onSurfaceVariant,
                            size: 18),
                        const SizedBox(width: 8),
                        Text(
                          capitalize(t.name),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? color
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.check_circle_rounded,
                              size: 15, color: color),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Account Category picker sheet ──────────────────────────────────────────────

class _CategoryPickerSheet extends StatelessWidget {
  final String title;
  final List<WalletCategory> items;
  final String? selected;
  final Color accentColor;
  final String Function(String) capitalize;

  const _CategoryPickerSheet({
    required this.title,
    required this.items,
    required this.selected,
    required this.accentColor,
    required this.capitalize,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: items.map((cat) {
                final isSelected = cat.name == selected;
                return GestureDetector(
                  onTap: () => Navigator.pop(context, cat.name),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? accentColor.withValues(alpha: 0.12)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? accentColor : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          capitalize(cat.name),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? accentColor
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.check_circle_rounded,
                              size: 15, color: accentColor),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Draggable sheet panel ──────────────────────────────────────────────────────
//
// Wraps the sheet content so the user can drag it downward to dismiss.
// A drag of >80 px (or fling velocity >400) triggers the dismiss callback.

class _DraggableSheetPanel extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onDismiss;

  const _DraggableSheetPanel({
    required this.child,
    required this.onDismiss,
  });

  @override
  State<_DraggableSheetPanel> createState() => _DraggableSheetPanelState();
}

class _DraggableSheetPanelState extends State<_DraggableSheetPanel>
    with SingleTickerProviderStateMixin {
  // Tracks the raw finger offset while dragging.
  double _dragOffset = 0;
  bool _dismissing = false;

  // Spring-back animation used when the user releases without dismissing.
  late final AnimationController _snapCtrl;
  late Animation<double> _snapAnim;

  static const double _dismissThreshold = 100.0;
  static const double _dismissVelocity = 600.0;
  static const double _sheetHeightFraction = 0.70;
  // Rubber-band resistance: the sheet moves at 40 % of finger speed so it
  // feels like it has weight without snapping stiffly.
  static const double _dragResistance = 0.55;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (_dismissing) return;
    _snapCtrl.stop();
    setState(() {
      _dragOffset = (_dragOffset + d.delta.dy * _dragResistance)
          .clamp(0.0, double.infinity);
    });
  }

  Future<void> _onVerticalDragEnd(DragEndDetails d) async {
    if (_dismissing) return;
    final velocity = d.primaryVelocity ?? 0;

    if (_dragOffset > _dismissThreshold || velocity > _dismissVelocity) {
      _dismissing = true;
      await widget.onDismiss();
    } else {
      // Spring back to resting position with a bouncy curve.
      _snapAnim = Tween<double>(begin: _dragOffset, end: 0).animate(
        CurvedAnimation(parent: _snapCtrl, curve: Curves.elasticOut),
      )..addListener(() => setState(() => _dragOffset = _snapAnim.value));
      _snapCtrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final sheetH = screenH * _sheetHeightFraction + bottomPad;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: GestureDetector(
          onTap: () {}, // absorb taps so they don't bubble to scrim
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          child: Container(
            height: sheetH,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomPad),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Account detail dialog ──────────────────────────────────────────────────────
//
// Replaces the old OverlayEntry + showModalBottomSheet pattern.
// Both the floating card and the sheet content live in the same Stack so the
// card is a plain widget at the same tree level as the sheet — no Overlay needed.
// The card still slides in from the top using _FloatingDetailCard's own animation.

class _AccountDetailDialog extends StatefulWidget {
  final Account account;
  final GlobalKey<_FloatingDetailCardState> cardKey;
  final VoidCallback? onTransactionChanged;
  final void Function(Account, BuildContext)? onEditAccount;
  final VoidCallback? onReceiptOpen;
  final VoidCallback? onReceiptClose;
  final VoidCallback? onEditOpen;

  const _AccountDetailDialog({
    required this.account,
    required this.cardKey,
    this.onTransactionChanged,
    this.onEditAccount,
    this.onReceiptOpen,
    this.onReceiptClose,
    this.onEditOpen,
  });

  @override
  State<_AccountDetailDialog> createState() => _AccountDetailDialogState();
}

class _AccountDetailDialogState extends State<_AccountDetailDialog> {
  Future<void> _dismiss() async {
    await widget.cardKey.currentState?.animateOut();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // ── Scrim — tapping it dismisses the dialog ───────────────────────
          Positioned.fill(
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(color: Colors.black54),
            ),
          ),

          // ── Bottom sheet panel ────────────────────────────────────────────
          _DraggableSheetPanel(
            onDismiss: _dismiss,
            child: _AccountDetailSheet(
              account: widget.account,
              onTransactionChanged: widget.onTransactionChanged,
              onEditAccount: (a) => widget.onEditAccount?.call(a, context),
              onReceiptOpen: widget.onReceiptOpen,
              onReceiptClose: widget.onReceiptClose,
              onEditOpen: widget.onEditOpen,
            ),
          ),

          // ── Floating card — slides in from top ────────────────────────────
          _FloatingDetailCard(
            key: widget.cardKey,
            account: widget.account,
            onDismiss: _dismiss,
          ),
        ],
      ),
    );
  }
}

// ── Overlay card: floats above the bottom sheet, completely outside its tree ───────
//
// Now a plain Stack child in _AccountDetailDialog rather than an OverlayEntry.
// Positioned so the card sits near the top of the screen and slides in from above.

class _FloatingDetailCard extends StatefulWidget {
  final Account account;

  /// Called when the dialog should be closed (barrier tapped while card is visible).
  final Future<void> Function()? onDismiss;
  const _FloatingDetailCard({super.key, required this.account, this.onDismiss});

  @override
  State<_FloatingDetailCard> createState() => _FloatingDetailCardState();
}

class _FloatingDetailCardState extends State<_FloatingDetailCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  bool _receiptOpen = false;

  /// The account shown on the card. Updated via [updateAccount] after an edit.
  late Account _account;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    // Slides in from above (negative Y = above the final position)
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _slideCtrl,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    // Start the entry animation immediately.
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  /// Called by [AccountsPageState] before the overlay entry is removed so the
  /// card slides back up before disappearing.
  Future<void> animateOut() async {
    if (!mounted) return;
    await _slideCtrl.reverse();
  }

  /// Called after the user saves edits so the floating card reflects the
  /// latest account data without needing to close and reopen the sheet.
  void updateAccount(Account updated) {
    if (!mounted) return;
    setState(() => _account = updated);
  }

  void dimForReceipt() {
    if (!mounted) return;
    setState(() => _receiptOpen = true);
  }

  void undimForReceipt() {
    if (!mounted) return;
    setState(() => _receiptOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    const cardH = 230.0;
    const cardW = 350.0;
    final screenW = MediaQuery.sizeOf(context).width;
    const topPadding = 56.0;
    final registry = _registryNotifier.value;
    final cornerStyle = registry.typeCornerStyle(_account.type);
    final br = registry.cardBorderRadius(_account.type);

    // Scrim shape: polygon styles use a large radius fallback, others use the
    // real card border radius so the overlay perfectly hugs the card edges.
    final scrimDecoration = BoxDecoration(
      color: Colors.black,
      borderRadius:
          isClipperCornerStyle(cornerStyle) ? BorderRadius.circular(20) : br,
    );

    return Positioned(
      top: topPadding,
      left: (screenW - cardW) / 2,
      width: cardW,
      height: cardH,
      child: SlideTransition(
        position: _slideAnim,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Material(
            color: Colors.transparent,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _DetailFlipCard(account: _account),
                // Dark scrim layered on top when receipt is open.
                // IgnorePointer so the scrim never swallows taps.
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _receiptOpen ? 0.45 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      decoration: scrimDecoration,
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
}

// ── Flippable card shown above the detail sheet ───────────────────────────────
//
// Mirrors _AccountCard's flip animation but is self-contained (no onTap→detail,
// no onLongPress→edit). Tap to flip front ↔ back.

class _DetailFlipCard extends StatefulWidget {
  final Account account;
  const _DetailFlipCard({required this.account});

  @override
  State<_DetailFlipCard> createState() => _DetailFlipCardState();
}

class _DetailFlipCardState extends State<_DetailFlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  bool _showingFront = true;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _anim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _flip() {
    if (_ctrl.isAnimating) return;
    if (_showingFront) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
    setState(() => _showingFront = !_showingFront);
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final accountColor = account.colorHex.isNotEmpty
        ? colorFromHex(account.colorHex)
        : const Color(0xFF6366F1);
    final gradients = gradientForColor(accountColor);
    final registry = _registryNotifier.value;
    final cornerStyle = registry.typeCornerStyle(account.type);
    final br = registry.cardBorderRadius(account.type);

    // ── Front face (same design as _AccountCard, bigger: 350×230) ─────────
    const cardW = 350.0;
    const cardH = 230.0;

    Widget frontFace = Container(
      width: cardW,
      height: cardH,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradients,
        ),
        borderRadius: isClipperCornerStyle(cornerStyle) ? null : br,
        boxShadow: [
          BoxShadow(
            color: accountColor.withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -22,
            top: -22,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.09),
              ),
            ),
          ),
          Positioned(
            left: -10,
            bottom: -22,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: ValueListenableBuilder<CategoryRegistry>(
              valueListenable: _registryNotifier,
              builder: (context, reg, _) {
                final catEntry = reg.accountCategories
                    .where((c) => c.name == account.category)
                    .firstOrNull;
                final catIcon = catEntry?.iconData ?? Icons.folder_outlined;
                return Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(catIcon, color: Colors.white70, size: 17),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 40),
                  child: Text(
                    account.name,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 2),
                ValueListenableBuilder<String>(
                  valueListenable: currencySymbolNotifier,
                  builder: (_, sym, __) => Text(
                    '$sym ${_fmt(account.balance)}',
                    style: TextStyle(
                      color: account.balance >= 0
                          ? Colors.white
                          : Colors.red.shade200,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    account.category.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // ── Back face ─────────────────────────────────────────────────────────
    Widget backFace = Container(
      width: cardW,
      height: cardH,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomRight,
          end: Alignment.topLeft,
          colors: gradients,
        ),
        borderRadius: isClipperCornerStyle(cornerStyle) ? null : br,
        boxShadow: [
          BoxShadow(
            color: accountColor.withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: -22,
            top: -22,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.09),
              ),
            ),
          ),
          Positioned(
            right: -10,
            bottom: -22,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            top: 32,
            left: 0,
            right: 0,
            child: Container(
              height: 38,
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 86, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Note header in the signature strip box, note body below
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              (account.noteHeader ?? '').isNotEmpty
                                  ? account.noteHeader!
                                  : account.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.lock_outline,
                              size: 12,
                              color: Colors.white.withValues(alpha: 0.6)),
                        ],
                      ),
                    ),
                    if ((account.noteBody ?? '').isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        account.noteBody!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
                ValueListenableBuilder<CategoryRegistry>(
                  valueListenable: _registryNotifier,
                  builder: (context, reg, _) {
                    return Row(
                      children: [
                        Icon(
                          reg.typeIcon(account.type),
                          color: Colors.white70,
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          reg.typeLabel(account.type).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // Apply clipping
    if (isClipperCornerStyle(cornerStyle)) {
      frontFace = _applyCornerClip(cornerStyle, frontFace);
      backFace = _applyCornerClip(cornerStyle, backFace);
    } else {
      frontFace = ClipRRect(borderRadius: br, child: frontFace);
      backFace = ClipRRect(borderRadius: br, child: backFace);
    }

    return GestureDetector(
      onTap: _flip,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, __) {
          final angle = _anim.value * math.pi;
          final isFrontVisible = angle <= math.pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: isFrontVisible
                ? frontFace
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: backFace,
                  ),
          );
        },
      ),
    );
  }
}

// ── Account detail bottom sheet ────────────────────────────────────────────────

class _AccountDetailSheet extends StatefulWidget {
  final Account account;
  final VoidCallback? onTransactionChanged;
  final void Function(Account)? onEditAccount;
  final VoidCallback? onReceiptOpen;
  final VoidCallback? onReceiptClose;
  final VoidCallback? onEditOpen;

  const _AccountDetailSheet({
    required this.account,
    this.onTransactionChanged,
    this.onEditAccount,
    this.onReceiptOpen,
    this.onReceiptClose,
    this.onEditOpen,
  });

  @override
  State<_AccountDetailSheet> createState() => _AccountDetailSheetState();
}

class _AccountDetailSheetState extends State<_AccountDetailSheet> {
  List<WalletTransaction> _transactions = [];
  List<Account> _allAccounts = [];
  List<WalletTransaction> _allTransferTxs = [];
  List<WalletCategory> _txCategories = [];
  List<WalletCategory> _accountTypes = [];
  List<WalletCategory> _accountCategories = [];
  bool _loading = true;

  // ── Per-account filter cache (survives sheet close/reopen within session) ──
  static final Map<
      int,
      ({
        _FilterMode mode,
        DateTime anchor,
        DateTime? customStart,
        DateTime? customEnd,
      })> _filterCache = {};

  // ── Date filter state ─────────────────────────────────────────────────────
  _FilterMode _filterMode = _FilterMode.monthly;
  DateTime _anchor = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _customStart;
  DateTime? _customEnd;

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

  // ignore: unused_element
  String get _filterLabel {
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
            return '${DateFormat('MMM d').format(s)} – ${DateFormat('MMM d, yyyy').format(e)}';
          case _FilterMode.monthly:
            return DateFormat('MMMM yyyy').format(s);
          case _FilterMode.yearly:
            return s.year.toString();
          default:
            return '';
        }
    }
  }

  Future<void> _pickPeriod(Color accentColor) async {
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
        accentColor: accentColor,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _filterMode = result.mode;
      _anchor = result.anchor;
      _customStart = result.customStart;
      _customEnd = result.customEnd;
    });
    _filterCache[widget.account.id!] = (
      mode: _filterMode,
      anchor: _anchor,
      customStart: _customStart,
      customEnd: _customEnd,
    );
  }

  // ── Filtered transactions ─────────────────────────────────────────────────
  List<WalletTransaction> get _filteredTransactions {
    final start = _periodStart;
    final end = _periodEnd;
    return _transactions.where((tx) {
      final d = DateTime.tryParse(tx.date);
      return d != null && !d.isBefore(start) && d.isBefore(end);
    }).toList();
  }

  // ── Transfer pair helper ──────────────────────────────────────────────────
  static String? _extractRef(String? note) {
    if (note == null) return null;
    final match = RegExp(r'__ref:([^_]+)__').firstMatch(note);
    return match?.group(1);
  }

  double get _accountIncome => _filteredTransactions
      .where((t) => t.type == 'income')
      .fold(0.0, (sum, t) => sum + t.amount);

  double get _accountExpenses => _filteredTransactions
      .where((t) => t.type == 'expense')
      .fold(0.0, (sum, t) => sum + t.amount);

  @override
  void initState() {
    super.initState();
    final cached = _filterCache[widget.account.id];
    if (cached != null) {
      _filterMode = cached.mode;
      _anchor = cached.anchor;
      _customStart = cached.customStart;
      _customEnd = cached.customEnd;
    }
    _load();
  }

  Future<void> _load() async {
    final txs = await DatabaseHelper.instance
        .getTransactionsByAccount(widget.account.id!);
    final accounts = await DatabaseHelper.instance.getAllAccounts();
    final allTxs = await DatabaseHelper.instance.getAllTransactions();
    final registry = await DatabaseHelper.instance.getCategoryRegistry();
    if (mounted) {
      setState(() {
        _transactions = txs;
        _allAccounts = accounts;
        _allTransferTxs = allTxs
            .where((t) => t.type == 'transfer_out' || t.type == 'transfer_in')
            .toList();
        _txCategories = registry.selectableTransactionCategories;
        _accountTypes = registry.accountTypes;
        _accountCategories = registry.accountCategories;
        _loading = false;
      });
    }
  }

  Future<void> _editTransaction(WalletTransaction existing,
      {String? transferTitle}) async {
    widget.onReceiptOpen?.call();
    _cardFlipLockedNotifier.value = true;
    await showTransactionReceipt(
      context,
      tx: existing,
      accounts: _allAccounts,
      txCategories: _txCategories,
      accountTypes: _accountTypes,
      accountCategories: _accountCategories,
      transferTitle: transferTitle,
      onEdited: (updated) async {
        await DatabaseHelper.instance.updateTransaction(existing, updated);
        await _load();
        widget.onTransactionChanged?.call();
        return updated;
      },
      onTransferEdited: (result, outLeg, inLeg) async {
        final ref =
            result.existingRef ?? '${DateTime.now().millisecondsSinceEpoch}';
        await DatabaseHelper.instance.updateTransfer(
          outLegId: outLeg.id!,
          inLegId: inLeg.id!,
          oldFromAccountId: outLeg.accountId!,
          oldToAccountId: inLeg.accountId!,
          oldAmount: outLeg.amount,
          newFromAccountId: result.fromAccountId,
          newToAccountId: result.toAccountId,
          newAmount: result.amount,
          date: result.date,
          refId: ref,
          note: result.note,
        );
        await _load();
        widget.onTransactionChanged?.call();
      },
    );
    widget.onReceiptClose?.call();
    _cardFlipLockedNotifier.value = false;
  }

  // Transfer info is now handled by showTransactionReceipt inside _editTransaction.
  void _showTransferInfo(WalletTransaction tx, {String? transferTitle}) =>
      _editTransaction(tx, transferTitle: transferTitle);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor = _registryNotifier.value.typeColor(widget.account.type) !=
            const Color(0xFF6366F1)
        ? _registryNotifier.value.typeColor(widget.account.type)
        : (widget.account.colorHex.isNotEmpty
            ? colorFromHex(widget.account.colorHex)
            : theme.colorScheme.primary);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        children: [
          // ── Drag handle ──────────────────────────────
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _registryNotifier.value.typeIcon(widget.account.type),
                  color: typeColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onLongPress: () async {
                        widget.onEditOpen?.call();
                        widget.onEditAccount?.call(widget.account);
                        await _load();
                      },
                      child: Text(widget.account.name,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    Row(
                      children: [
                        Text(
                          _registryNotifier.value
                              .typeLabel(widget.account.type)
                              .toUpperCase(),
                          style: TextStyle(
                              fontSize: 11,
                              color: typeColor,
                              fontWeight: FontWeight.bold),
                        ),
                        if (widget.account.category.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            '· ${_capitalize(widget.account.category)}',
                            style: TextStyle(
                                fontSize: 11, color: theme.colorScheme.outline),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${currencySymbolNotifier.value} ${_fmt(widget.account.balance)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: widget.account.balance >= 0
                          ? Colors.green.shade700
                          : Colors.red,
                    ),
                  ),
                  if (!_loading) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _AccountStatChip(
                          icon: Icons.arrow_upward,
                          amount: _accountIncome,
                          color: Colors.green,
                        ),
                        Container(
                          width: 1,
                          height: 10,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          color: theme.colorScheme.outlineVariant,
                        ),
                        _AccountStatChip(
                          icon: Icons.arrow_downward,
                          amount: _accountExpenses,
                          color: Colors.red,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── Transactions label (tappable → opens date filter) ─────────
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => _pickPeriod(typeColor),
                child: Text(
                  'Transactions',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.70),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredTransactions.isEmpty
                    ? Center(
                        child: Text(
                          _transactions.isEmpty
                              ? 'No transactions for this account'
                              : 'No transactions for this period.',
                          style: TextStyle(color: theme.colorScheme.outline),
                        ),
                      )
                    : _buildGroupedList(_filteredTransactions, theme),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTransaction(WalletTransaction tx) async {
    await DatabaseHelper.instance.deleteTransaction(tx);
    await _load();
    widget.onTransactionChanged?.call();
  }

  Future<void> _deleteTransfer(
      WalletTransaction outTx, WalletTransaction inTx) async {
    await DatabaseHelper.instance.deleteTransfer(outTx, inTx);
    await _load();
    widget.onTransactionChanged?.call();
  }

  Widget _buildGroupedList(List<WalletTransaction> txs, ThemeData theme) {
    // ── Group by calendar date "yyyy-MM-dd", sorted DESC ───────────────────
    final Map<String, List<WalletTransaction>> groups = {};
    for (final tx in txs) {
      final key = tx.date.length >= 10 ? tx.date.substring(0, 10) : tx.date;
      groups.putIfAbsent(key, () => []).add(tx);
    }
    final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    // ── Build flat item list: header + collapsed transfer pairs ────────────
    final items = <_TxItem>[];
    for (final key in keys) {
      final d = DateTime.tryParse(key);
      if (d != null) {
        // e.g. "Jun 9, Monday"
        final label = DateFormat('MMM d, EEEE').format(d);
        items.add(_TxItem.header(label));
      }

      final dayTxs = groups[key]!;
      final emittedRefs = <String>{};
      final unmatchedIns = <WalletTransaction>[
        ...dayTxs.where(
            (t) => t.type == 'transfer_in' && _extractRef(t.note) == null),
      ];
      final skippedIds = <int>{};

      for (final tx in dayTxs) {
        if (skippedIds.contains(tx.id)) continue;

        if (tx.type == 'transfer_out' || tx.type == 'transfer_in') {
          final ref = _extractRef(tx.note);
          if (ref != null) {
            if (emittedRefs.contains(ref)) continue;
            emittedRefs.add(ref);
            final WalletTransaction outLeg;
            final WalletTransaction inLeg;
            if (tx.type == 'transfer_out') {
              outLeg = tx;
              // Look in dayTxs first, then fall back to the global transfer list
              inLeg = dayTxs.firstWhere(
                (t) => t.type == 'transfer_in' && _extractRef(t.note) == ref,
                orElse: () => _allTransferTxs.firstWhere(
                  (t) => t.type == 'transfer_in' && _extractRef(t.note) == ref,
                  orElse: () => tx,
                ),
              );
            } else {
              // Look in dayTxs first, then fall back to the global transfer list
              final out = dayTxs.firstWhere(
                (t) => t.type == 'transfer_out' && _extractRef(t.note) == ref,
                orElse: () => _allTransferTxs.firstWhere(
                  (t) => t.type == 'transfer_out' && _extractRef(t.note) == ref,
                  orElse: () => tx,
                ),
              );
              outLeg = out;
              inLeg = tx;
            }
            items.add(_TxItem.transfer(outLeg, inLeg));
          } else if (tx.type == 'transfer_out') {
            final matchIdx = unmatchedIns.indexWhere(
                (t) => t.amount == tx.amount && !skippedIds.contains(t.id));
            if (matchIdx != -1) {
              final inLeg = unmatchedIns[matchIdx];
              skippedIds.add(inLeg.id!);
              items.add(_TxItem.transfer(tx, inLeg));
            } else {
              items.add(_TxItem.tx(tx));
            }
          } else {
            items.add(_TxItem.tx(tx));
          }
        } else {
          items.add(_TxItem.tx(tx));
        }
      }
    }

    // Compute which item indices are the last transaction in their day group.
    final lastInGroupIndices = <int>{};
    for (int i = 0; i < items.length; i++) {
      if (items[i].isHeader) continue;
      final isLast = i == items.length - 1 || items[i + 1].isHeader;
      if (isLast) lastInGroupIndices.add(i);
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        final showDivider = !lastInGroupIndices.contains(i);

        // ── Date header ───────────────────────────────────────────────────
        if (item.isHeader) {
          return Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label!,
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

        // ── Merged transfer card ──────────────────────────────────────────
        if (item.isTransfer) {
          final outTx = item.transferOut!;
          final inTx = item.transferIn!;
          final fromAccount = _allAccounts
              .firstWhere((a) => a.id == outTx.accountId,
                  orElse: () => Account(
                      name: 'Unknown',
                      balance: 0,
                      type: '',
                      colorHex: '',
                      icon: ''))
              .name;
          final toAccount = _allAccounts
              .firstWhere((a) => a.id == inTx.accountId,
                  orElse: () => Account(
                      name: 'Unknown',
                      balance: 0,
                      type: '',
                      colorHex: '',
                      icon: ''))
              .name;

          // Determine direction relative to the currently open account
          final isTransferOut = outTx.accountId == widget.account.id;
          final transferLabel = isTransferOut ? 'Transfer Out' : 'Transfer In';
          final transferAmountPrefix = isTransferOut ? '−' : '+';
          final transferColor = Theme.of(context).colorScheme.primary;
          final transferBgColor =
              Theme.of(context).colorScheme.primaryContainer;
          final transferFgColor =
              Theme.of(context).colorScheme.onPrimaryContainer;
          final transferIcon = isTransferOut
              ? Icons.arrow_upward_rounded
              : Icons.arrow_downward_rounded;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                color: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                clipBehavior: Clip.antiAlias,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Dismissible(
                    key: Key('acct_transfer_${outTx.id}_${inTx.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    confirmDismiss: (_) async => true,
                    onDismissed: (_) async {
                      await _deleteTransfer(outTx, inTx);
                    },
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      onTap: () => _showTransferInfo(outTx,
                          transferTitle: transferLabel),
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: transferBgColor,
                        child: Icon(
                          transferIcon,
                          size: 20,
                          color: transferFgColor,
                        ),
                      ),
                      title: Text(
                        transferLabel,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      subtitle: Text(
                        '$fromAccount → $toAccount',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Text(
                        '$transferAmountPrefix ${currencySymbolNotifier.value}${_fmt(outTx.amount)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: transferColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (showDivider)
                Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 12,
                  endIndent: 12,
                  color: Colors.grey.withValues(alpha: 0.25),
                ),
            ],
          );
        }

        // ── Regular transaction card ──────────────────────────────────────
        final tx = item.tx!;
        final isIncome = tx.type == 'income';
        final rowColor =
            isIncome ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
        final bgColor = isIncome
            ? const Color(0xFF22C55E).withValues(alpha: 0.15)
            : const Color(0xFFEF4444).withValues(alpha: 0.15);
        final amountPrefix = isIncome ? '+' : '−';
        final txCatIcon = _txCategories
                .cast<WalletCategory?>()
                .firstWhere((c) => c?.name == tx.category, orElse: () => null)
                ?.iconData ??
            iconForKey(tx.category);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              clipBehavior: Clip.antiAlias,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Dismissible(
                  key: Key('acct_tx_${tx.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => _deleteTransaction(tx),
                  child: ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    onTap: () => _editTransaction(tx),
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundColor: bgColor,
                      child: Icon(
                        txCatIcon,
                        size: 20,
                        color: rowColor,
                      ),
                    ),
                    title: Text(
                      tx.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    subtitle: Text(
                      tx.category,
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Text(
                      '$amountPrefix ${currencySymbolNotifier.value}${_fmt(tx.amount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: rowColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (showDivider)
              Divider(
                height: 1,
                thickness: 0.5,
                indent: 12,
                endIndent: 12,
                color: Colors.grey.withValues(alpha: 0.25),
              ),
          ],
        );
      },
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ── Delete Account Dialog ─────────────────────────────────────────────────────

class _DeleteAccountDialog extends StatelessWidget {
  final Account account;

  const _DeleteAccountDialog({required this.account});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeIcon = _registryNotifier.value.typeIcon(account.type);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Red header banner ──────────────────────────────────────────
          Container(
            width: double.infinity,
            color: Colors.red.shade600,
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_forever_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Delete Account',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),

          // ── Body ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Column(
              children: [
                // Account name pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.red.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(typeIcon, size: 15, color: Colors.red.shade700),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          account.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.red.shade700,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'All transactions linked to this account will be permanently removed. This action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),

          // ── Actions ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.delete_rounded, size: 17),
                    label: const Text('Delete'),
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
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

// ── Local _TxItem discriminated union (for _AccountDetailSheet) ───────────────

class _TxItem {
  final bool isHeader;
  final bool isTransfer;
  final String? label;
  final WalletTransaction? tx;
  final WalletTransaction? transferOut;
  final WalletTransaction? transferIn;

  const _TxItem.header(this.label)
      : isHeader = true,
        isTransfer = false,
        tx = null,
        transferOut = null,
        transferIn = null;

  const _TxItem.tx(this.tx)
      : isHeader = false,
        isTransfer = false,
        label = null,
        transferOut = null,
        transferIn = null;

  const _TxItem.transfer(this.transferOut, this.transferIn)
      : isHeader = false,
        isTransfer = true,
        label = null,
        tx = null;
}

class _AccountStatChip extends StatelessWidget {
  final IconData icon;
  final double amount;
  final Color color;

  const _AccountStatChip({
    required this.icon,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 10),
        const SizedBox(width: 3),
        Text(
          '${currencySymbolNotifier.value} ${_fmt(amount)}',
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Period picker dialog (mirrored from HistoryPage) ──────────────────────────

class _PeriodPickerDialog extends StatefulWidget {
  final _FilterMode currentMode;
  final DateTime currentAnchor;
  final DateTime? customStart;
  final DateTime? customEnd;
  final Color? accentColor;

  const _PeriodPickerDialog({
    required this.currentMode,
    required this.currentAnchor,
    this.customStart,
    this.customEnd,
    this.accentColor,
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
          _anchor = DateTime(d.year, d.month, d.day);
          break;
        case _FilterMode.weekly:
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

  List<DateTime?> _calendarDays() {
    final firstDay = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final daysInMonth =
        DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    final leadingBlanks = firstDay.weekday - 1;
    return [
      ...List<DateTime?>.filled(leadingBlanks, null),
      ...List.generate(daysInMonth,
          (i) => DateTime(_calendarMonth.year, _calendarMonth.month, i + 1)),
    ];
  }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.accentColor ?? theme.colorScheme.primary;
    final now = DateTime.now();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Mode tabs ────────────────────────────────────────────────
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
                                  ? accent
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

            // ── Nav row + calendar (fixed height so dialog never resizes) ──
            SizedBox(
              height: 308,
              child: Column(
                children: [
                  // Nav header row — hidden for allTime but kept for spacing
                  Opacity(
                    opacity: _mode == _FilterMode.allTime ? 0.0 : 1.0,
                    child: IgnorePointer(
                      ignoring: _mode == _FilterMode.allTime,
                      child: Builder(builder: (_) {
                        final decadeStart =
                            (_calendarMonth.year - 1) ~/ 10 * 10 + 1;
                        final String navLabel;
                        final VoidCallback onBack;
                        final VoidCallback? onForward;

                        switch (_mode) {
                          case _FilterMode.monthly:
                            navLabel = '${_calendarMonth.year}';
                            onBack = () => setState(() => _calendarMonth =
                                DateTime(_calendarMonth.year - 1,
                                    _calendarMonth.month));
                            onForward = _calendarMonth.year >= now.year
                                ? null
                                : () => setState(() => _calendarMonth =
                                    DateTime(_calendarMonth.year + 1,
                                        _calendarMonth.month));
                          case _FilterMode.yearly:
                            navLabel = '$decadeStart – ${decadeStart + 9}';
                            onBack = () => setState(() => _calendarMonth =
                                DateTime(_calendarMonth.year - 10, 1));
                            onForward = decadeStart + 9 >= now.year
                                ? null
                                : () => setState(() => _calendarMonth =
                                    DateTime(_calendarMonth.year + 10, 1));
                          default:
                            navLabel = _calendarMonthLabel();
                            onBack = () => setState(() => _calendarMonth =
                                DateTime(_calendarMonth.year,
                                    _calendarMonth.month - 1));
                            onForward = (_calendarMonth.year > now.year ||
                                    (_calendarMonth.year == now.year &&
                                        _calendarMonth.month >= now.month))
                                ? null
                                : () => setState(() => _calendarMonth =
                                    DateTime(_calendarMonth.year,
                                        _calendarMonth.month + 1));
                        }

                        return Row(
                          children: [
                            IconButton(
                              onPressed: onBack,
                              icon: const Icon(Icons.chevron_left),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              iconSize: 20,
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  navLabel,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: onForward,
                              icon: Icon(
                                Icons.chevron_right,
                                color: onForward != null
                                    ? null
                                    : theme.colorScheme.onSurface
                                        .withValues(alpha: 0.25),
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              iconSize: 20,
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ── Picker body (fills remaining fixed space) ───────────
                  Expanded(
                    child: _mode == _FilterMode.allTime
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.all_inclusive,
                                size: 48,
                                color: accent.withValues(alpha: 0.35),
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
                          )
                        : Column(
                            children: [
                              // Monthly grid: month tiles
                              if (_mode == _FilterMode.monthly)
                                Builder(builder: (_) {
                                  return GridView.count(
                                    crossAxisCount: 4,
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    childAspectRatio: 2.0,
                                    children: List.generate(12, (i) {
                                      final month = i + 1;
                                      final d =
                                          DateTime(_calendarMonth.year, month);
                                      final isFuture = d.isAfter(
                                          DateTime(now.year, now.month));
                                      final isSelected =
                                          _anchor.year == _calendarMonth.year &&
                                              _anchor.month == month;
                                      final isCurrentMonth =
                                          now.year == _calendarMonth.year &&
                                              now.month == month;
                                      final textColor = isFuture
                                          ? theme.colorScheme.onSurface
                                              .withValues(alpha: 0.25)
                                          : isSelected
                                              ? accent
                                              : isCurrentMonth
                                                  ? accent
                                                  : theme.colorScheme.onSurface;
                                      return GestureDetector(
                                        onTap: isFuture
                                            ? null
                                            : () => _onDayTapped(d),
                                        child: Container(
                                          margin: const EdgeInsets.all(3),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? accent.withValues(alpha: 0.15)
                                                : null,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Center(
                                            child: Text(
                                              DateFormat('MMM').format(d),
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight:
                                                    isSelected || isCurrentMonth
                                                        ? FontWeight.w700
                                                        : FontWeight.w500,
                                                color: textColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                  );
                                })
                              else if (_mode == _FilterMode.yearly)
                                Builder(builder: (_) {
                                  final rowSizes = [4, 4, 2];
                                  Widget yearCell(int yr) {
                                    final isFuture = yr > now.year;
                                    final isSelected = _anchor.year == yr;
                                    final isCurrentYear = now.year == yr;
                                    final textColor = isFuture
                                        ? theme.colorScheme.onSurface
                                            .withValues(alpha: 0.25)
                                        : isSelected
                                            ? accent
                                            : isCurrentYear
                                                ? accent
                                                : theme.colorScheme.onSurface;
                                    return Expanded(
                                      child: GestureDetector(
                                        onTap: isFuture
                                            ? null
                                            : () => _onDayTapped(DateTime(yr)),
                                        child: Container(
                                          height: 44,
                                          margin: const EdgeInsets.all(3),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? accent.withValues(alpha: 0.15)
                                                : null,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Center(
                                            child: Text(
                                              '$yr',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight:
                                                    isSelected || isCurrentYear
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

                                  final localDecadeStart =
                                      (_calendarMonth.year - 1) ~/ 10 * 10 + 1;
                                  int offset = 0;
                                  return Column(
                                    children: rowSizes.map((count) {
                                      final start = offset;
                                      offset += count;
                                      if (count < 4) {
                                        return Row(children: [
                                          const Expanded(child: SizedBox()),
                                          ...List.generate(
                                              count,
                                              (i) => yearCell(localDecadeStart +
                                                  start +
                                                  i)),
                                          const Expanded(child: SizedBox()),
                                        ]);
                                      }
                                      return Row(
                                        children: List.generate(
                                            count,
                                            (i) => yearCell(
                                                localDecadeStart + start + i)),
                                      );
                                    }).toList(),
                                  );
                                })
                              else ...[
                                // Daily / Weekly / Custom: weekday header + day grid
                                Row(
                                  children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                                      .map((d) {
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
                                          final isFuture = d.isAfter(now);
                                          final highlighted =
                                              !isFuture && _isHighlighted(d);
                                          final isToday = _isSameDay(d, now);
                                          Color? bgColor;
                                          Color textColor =
                                              theme.colorScheme.onSurface;
                                          if (highlighted) {
                                            bgColor =
                                                accent.withValues(alpha: 0.15);
                                            textColor = accent;
                                          } else if (isToday) {
                                            textColor = accent;
                                          }
                                          if (isFuture) {
                                            textColor = theme
                                                .colorScheme.onSurface
                                                .withValues(alpha: 0.25);
                                          }
                                          return Expanded(
                                            child: GestureDetector(
                                              onTap: isFuture
                                                  ? null
                                                  : () => _onDayTapped(d),
                                              child: Container(
                                                height: 36,
                                                decoration: BoxDecoration(
                                                  color: bgColor,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    '${d.day}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          highlighted || isToday
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
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Selected period label ────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _selectedLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Actions ──────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent),
                    ),
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
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                    ),
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
