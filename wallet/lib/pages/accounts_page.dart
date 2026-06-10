import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/account_model.dart';
import '../models/transaction_model.dart';

// ── Number formatter ───────────────────────────────────────────────────────────

final _currencyFmt = NumberFormat('#,##0.00', 'en_PH');

String _fmt(double v) => _currencyFmt.format(v);

// ── Type metadata ──────────────────────────────────────────────────────────────

const _typeColors = {
  'cash': Color(0xFF22C55E),
  'bank': Color(0xFF3B82F6),
  'e-wallet': Color(0xFFA855F7),
  'credit': Color(0xFFEF4444),
  'loan': Color(0xFFF97316),
  'investment': Color(0xFF0EA5E9),
  'savings': Color(0xFF14B8A6),
};

const _typeIcons = {
  'cash': Icons.payments_outlined,
  'bank': Icons.account_balance_outlined,
  'e-wallet': Icons.phone_android_outlined,
  'credit': Icons.credit_card_outlined,
  'loan': Icons.handshake_outlined,
  'investment': Icons.trending_up_outlined,
  'savings': Icons.savings_outlined,
};

const _typeGradients = {
  'cash': [Color(0xFF16A34A), Color(0xFF4ADE80)],
  'bank': [Color(0xFF1D4ED8), Color(0xFF60A5FA)],
  'e-wallet': [Color(0xFF7C3AED), Color(0xFFC084FC)],
  'credit': [Color(0xFFB91C1C), Color(0xFFF87171)],
  'loan': [Color(0xFFC2410C), Color(0xFFFB923C)],
  'investment': [Color(0xFF0369A1), Color(0xFF38BDF8)],
  'savings': [Color(0xFF0F766E), Color(0xFF2DD4BF)],
};

const _typeLabels = {
  'cash': 'Cash',
  'bank': 'Bank',
  'e-wallet': 'E-Wallet',
  'credit': 'Credits',
  'loan': 'Loans',
  'investment': 'Investments',
  'savings': 'Savings',
};

const _typeColorHexMap = {
  'cash': '#22C55E',
  'bank': '#3B82F6',
  'e-wallet': '#A855F7',
  'credit': '#EF4444',
  'loan': '#F97316',
  'investment': '#0EA5E9',
  'savings': '#14B8A6',
};

const _allTypes = [
  'cash',
  'bank',
  'e-wallet',
  'credit',
  'loan',
  'investment',
  'savings'
];

// ── Page ───────────────────────────────────────────────────────────────────────

class AccountsPage extends StatefulWidget {
  final VoidCallback? onNavigateToAnalytics;

  const AccountsPage({super.key, this.onNavigateToAnalytics});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
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

  Future<void> _loadAccounts() async {
    final accounts = await _db.getAccountsSortedByLatestTransaction();
    final income = await _db.getTotalIncome();
    final expenses = await _db.getTotalExpenses();
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
      newOrder = saved ?? [];
    } else {
      newOrder = List.of(_typeOrder);
    }

    // Remove types no longer present, append any new types not yet in order.
    newOrder = newOrder.where((t) => grouped.containsKey(t)).toList();
    final presentTypes = _allTypes.where((t) => grouped.containsKey(t));
    for (final t in presentTypes) {
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
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: Text(
            'Delete "${account.name}" and all its transactions? This cannot be undone.'),
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
    );
    if (confirmed == true && account.id != null) {
      await _db.deleteAccount(account.id!);
      _loadAccounts();
    }
  }

  void _showAccountDetail(Account account) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _AccountDetailSheet(
        account: account,
        onTransactionChanged: _loadAccounts,
        onEditAccount: (a) => _showAddAccountDialog(existing: a),
      ),
    );
  }

  // ── Card dragged to a different section (type change) ──────────────────────

  Future<void> _moveCardToType(Account account, String newType) async {
    if (account.type == newType) return;
    final updated = account.copyWith(
      type: newType,
      colorHex: _typeColorHexMap[newType] ?? '#6366F1',
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

    return RefreshIndicator(
      onRefresh: _loadAccounts,
      child: CustomScrollView(
        slivers: [
          // ── Hero header ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _TotalBalanceHero(
              totalBalance: _totalBalance,
              accountCount: _accounts.length,
              totalIncome: _totalIncome,
              totalExpenses: _totalExpenses,
              onAddAccount: _showAddAccountDialog,
              onNavigateToAnalytics: widget.onNavigateToAnalytics,
            ),
          ),

          // ── "My Accounts" label ───────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
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
          ),

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
                onCardLongPress: (_) {},
                onCardDelete: _deleteAccount,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
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
  final void Function(Account) onCardLongPress;
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
    required this.onCardLongPress,
    required this.onCardDelete,
  });

  @override
  State<_DraggableSectionList> createState() => _DraggableSectionListState();
}

class _DraggableSectionListState extends State<_DraggableSectionList> {
  // Which section index is being hovered for drop target highlight
  int? _hoverSectionIndex;
  // Whether a card drag is in progress (to highlight drop zones)
  bool _cardDragActive = false;
  Account? _draggingCard;

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
          cardDragActive: _cardDragActive,
          draggingCard: _draggingCard,
          onSectionDragStart: () => widget.onSectionDragStart(type),
          onSectionDragEnd: widget.onSectionDragEnd,
          onCardDragStart: (card) {
            setState(() {
              _cardDragActive = true;
              _draggingCard = card;
            });
          },
          onCardDragEnd: () {
            setState(() {
              _cardDragActive = false;
              _draggingCard = null;
            });
          },
          onCardDropped: (card) => widget.onCardMoveToType(card, type),
          onCardTap: widget.onCardTap,
          onCardLongPress: widget.onCardLongPress,
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
  final bool cardDragActive;
  final Account? draggingCard;
  final VoidCallback onSectionDragStart;
  final VoidCallback onSectionDragEnd;
  final void Function(Account) onCardDragStart;
  final VoidCallback onCardDragEnd;
  final void Function(Account) onCardDropped;
  final void Function(Account) onCardTap;
  final void Function(Account) onCardLongPress;
  final void Function(Account) onCardDelete;

  const _DraggableSectionTile({
    required this.type,
    required this.accounts,
    required this.isBeingDragged,
    required this.reorderMode,
    required this.cardDragActive,
    required this.draggingCard,
    required this.onSectionDragStart,
    required this.onSectionDragEnd,
    required this.onCardDragStart,
    required this.onCardDragEnd,
    required this.onCardDropped,
    required this.onCardTap,
    required this.onCardLongPress,
    required this.onCardDelete,
  });

  @override
  State<_DraggableSectionTile> createState() => _DraggableSectionTileState();
}

class _DraggableSectionTileState extends State<_DraggableSectionTile> {
  bool _isDropTarget = false;

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
            child: Icon(_typeIcons[widget.type] ?? Icons.wallet,
                color: typeColor, size: 15),
          ),
          const SizedBox(width: 8),
          Text(
            _typeLabels[widget.type] ?? widget.type,
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
          _buildHeader(
              context,
              _typeColors[widget.type] ??
                  Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          _DraggableCardCarousel(
            type: widget.type,
            accounts: widget.accounts,
            reorderMode: widget.reorderMode,
            onCardDragStart: widget.onCardDragStart,
            onCardDragEnd: widget.onCardDragEnd,
            onCardTap: widget.onCardTap,
            onCardLongPress: widget.onCardLongPress,
            onCardDelete: widget.onCardDelete,
          ),
        ],
      ),
    );
  }

  // Compact header-only view used in the drag feedback ghost
  Widget _buildCompactContent() {
    final theme = Theme.of(context);
    final typeColor = _typeColors[widget.type] ?? theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: _buildHeader(context, typeColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor = _typeColors[widget.type] ?? theme.colorScheme.primary;

    final isCardDropTarget = widget.cardDragActive &&
        widget.draggingCard != null &&
        widget.draggingCard!.type != widget.type;

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

    // Card drop target wrapper
    if (isCardDropTarget) {
      sectionBody = DragTarget<Account>(
        onWillAcceptWithDetails: (d) => d.data.type != widget.type,
        onAcceptWithDetails: (d) {
          widget.onCardDropped(d.data);
          setState(() => _isDropTarget = false);
        },
        onMove: (_) {
          if (!_isDropTarget) setState(() => _isDropTarget = true);
        },
        onLeave: (_) => setState(() => _isDropTarget = false),
        builder: (_, candidateData, __) => sectionBody,
      );
    }

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
                  color: theme.colorScheme.surface,
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
  final void Function(Account) onCardDragStart;
  final VoidCallback onCardDragEnd;
  final void Function(Account) onCardTap;
  final void Function(Account) onCardLongPress;
  final void Function(Account) onCardDelete;

  const _DraggableCardCarousel({
    required this.type,
    required this.accounts,
    required this.reorderMode,
    required this.onCardDragStart,
    required this.onCardDragEnd,
    required this.onCardTap,
    required this.onCardLongPress,
    required this.onCardDelete,
  });

  @override
  State<_DraggableCardCarousel> createState() => _DraggableCardCarouselState();
}

class _DraggableCardCarouselState extends State<_DraggableCardCarousel> {
  @override
  Widget build(BuildContext context) {
    final typeColor =
        _typeColors[widget.type] ?? Theme.of(context).colorScheme.primary;
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

          // ── REORDER MODE: draggable for cross-section drops ────────────
          if (widget.reorderMode) {
            return Padding(
              padding: const EdgeInsets.only(right: 14),
              child: LongPressDraggable<Account>(
                key: ValueKey('card_drag_\${a.id}'),
                data: a,
                delay: const Duration(milliseconds: 400),
                onDragStarted: () {
                  widget.onCardDragStart(a);
                  HapticFeedback.mediumImpact();
                },
                onDragEnd: (_) => widget.onCardDragEnd(),
                onDraggableCanceled: (_, __) => widget.onCardDragEnd(),
                feedback: Material(
                  color: Colors.transparent,
                  child: Opacity(
                    opacity: 0.95,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: typeColor.withValues(alpha: 0.45),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ],
                        border: Border.all(color: typeColor, width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: _AccountCardInert(account: a),
                      ),
                    ),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.0,
                  child: _AccountCardInert(account: a),
                ),
                child: _AccountCardInert(account: a),
              ),
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary, tertiary],
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.35),
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
                '₱ ${_fmt(totalBalance)}',
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
          '₱ ${_fmt(amount)}',
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

// ── Account card (inert) ───────────────────────────────────────────────────────
//
// Pure visual card with zero gesture handling. Used in reorder mode as the
// LongPressDraggable child/feedback/ghost so there is no gesture conflict
// with the AnimationController inside _AccountCard.

class _AccountCardInert extends StatelessWidget {
  final Account account;
  const _AccountCardInert({required this.account});

  BorderRadius _borderRadius() {
    switch (account.type) {
      case 'cash':
        return BorderRadius.zero;
      case 'e-wallet':
        return BorderRadius.circular(24);
      default:
        return BorderRadius.circular(18);
    }
  }

  bool get _isEwallet => account.type == 'e-wallet';

  @override
  Widget build(BuildContext context) {
    final gradients = _typeGradients[account.type] ??
        [const Color(0xFF6366F1), const Color(0xFF818CF8)];
    final br = _borderRadius();

    Widget card = Container(
      width: 255,
      height: 155,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradients,
        ),
        borderRadius: _isEwallet ? null : br,
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
                  '₱ ${_fmt(account.balance)}',
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

    if (_isEwallet) {
      card = ClipPath(clipper: _OctagonClipper(), child: card);
    }
    return card;
  }
}

// ── Account card ───────────────────────────────────────────────────────────────
//
// Tap    → view detail (opens _AccountDetailSheet which has edit button)
// Delete → small trash icon button on the card
// Drag   → handled by LongPressDraggable in reorder mode (uses _AccountCardInert)
//
// Deliberately StatelessWidget — no AnimationController — so it can be safely
// swapped into and out of LongPressDraggable without ticker conflicts.

class _AccountCard extends StatelessWidget {
  final Account account;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _AccountCard({
    super.key,
    required this.account,
    required this.onTap,
    required this.onDelete,
  });

  BorderRadius _borderRadius() {
    switch (account.type) {
      case 'cash':
        return BorderRadius.zero;
      case 'e-wallet':
        return BorderRadius.circular(24);
      default:
        return BorderRadius.circular(18);
    }
  }

  bool get _isEwallet => account.type == 'e-wallet';

  @override
  Widget build(BuildContext context) {
    final gradients = _typeGradients[account.type] ??
        [const Color(0xFF6366F1), const Color(0xFF818CF8)];
    final br = _borderRadius();

    Widget card = Container(
      width: 255,
      height: 155,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradients,
        ),
        borderRadius: _isEwallet ? null : br,
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
          // Delete button
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(Icons.delete_outline,
                    color: Colors.white70, size: 15),
              ),
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
                  '₱ ${_fmt(account.balance)}',
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

    if (_isEwallet) {
      card = ClipPath(clipper: _OctagonClipper(), child: card);
    }

    return GestureDetector(onTap: onTap, child: card);
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

  const _AccountFormSheet({this.existing, required this.onSave});

  @override
  State<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends State<_AccountFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _balanceCtrl;
  late String _selectedType;
  late String _selectedCategory;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _balanceCtrl = TextEditingController(
      text: e != null ? e.balance.toStringAsFixed(2) : '',
    );
    _selectedType = e?.type ?? 'cash';
    _selectedCategory = e?.category ?? 'personal';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
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
              decoration: const InputDecoration(
                labelText: 'Initial Balance (₱)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Type picker — only rebuilds when _selectedType changes ────────
          Text('Account Type', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _allTypes.map((t) {
              final selected = _selectedType == t;
              final color = _typeColors[t]!;
              return GestureDetector(
                onTap: () => setState(() => _selectedType = t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: (MediaQuery.sizeOf(context).width - 40 - 24) / 4,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: 0.15)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? color : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(_typeIcons[t],
                          color: selected ? color : null, size: 20),
                      const SizedBox(height: 3),
                      Text(
                        _typeLabels[t]!,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: selected ? color : null,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // ── Category picker — same isolation benefit ───────────────────────
          Text('Category', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kAccountCategories.map((cat) {
              final selected = _selectedCategory == cat;
              final color = theme.colorScheme.primary;
              return GestureDetector(
                onTap: () => setState(() => _selectedCategory = cat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: 0.12)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? color : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    _capitalize(cat),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? color : null,
                    ),
                  ),
                ),
              );
            }).toList(),
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
                final account = isEdit
                    ? widget.existing!.copyWith(
                        name: _nameCtrl.text.trim(),
                        type: _selectedType,
                        category: _selectedCategory,
                        colorHex: _typeColorHexMap[_selectedType] ?? '#6366F1',
                      )
                    : Account(
                        name: _nameCtrl.text.trim(),
                        balance:
                            double.tryParse(_balanceCtrl.text.trim()) ?? 0.0,
                        type: _selectedType,
                        category: _selectedCategory,
                        colorHex: _typeColorHexMap[_selectedType] ?? '#6366F1',
                        icon: 'wallet',
                      );
                await widget.onSave(account);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Octagon clipper ────────────────────────────────────────────────────────────
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

// ── Account detail bottom sheet ────────────────────────────────────────────────

class _AccountDetailSheet extends StatefulWidget {
  final Account account;
  final VoidCallback? onTransactionChanged;
  final void Function(Account)? onEditAccount;

  const _AccountDetailSheet({
    required this.account,
    this.onTransactionChanged,
    this.onEditAccount,
  });

  @override
  State<_AccountDetailSheet> createState() => _AccountDetailSheetState();
}

class _AccountDetailSheetState extends State<_AccountDetailSheet> {
  List<WalletTransaction> _transactions = [];
  List<Account> _allAccounts = [];
  List<WalletTransaction> _allTransferTxs = []; // for resolving transfer pairs
  bool _loading = true;

  double get _accountIncome => _transactions
      .where((t) => t.type == 'income')
      .fold(0.0, (sum, t) => sum + t.amount);

  double get _accountExpenses => _transactions
      .where((t) => t.type == 'expense')
      .fold(0.0, (sum, t) => sum + t.amount);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final txs = await DatabaseHelper.instance
        .getTransactionsByAccount(widget.account.id!);
    final accounts = await DatabaseHelper.instance.getAllAccounts();
    final allTxs = await DatabaseHelper.instance.getAllTransactions();
    if (mounted) {
      setState(() {
        _transactions = txs;
        _allAccounts = accounts;
        _allTransferTxs = allTxs
            .where((t) => t.type == 'transfer_out' || t.type == 'transfer_in')
            .toList();
        _loading = false;
      });
    }
  }

  Future<void> _editTransaction(WalletTransaction existing) async {
    if (existing.type == 'transfer_out' || existing.type == 'transfer_in') {
      _showTransferInfo(existing);
      return;
    }
    final updated = await WalletTransaction.showDialog(
      context,
      accounts: _allAccounts,
      existing: existing,
    );
    if (updated == null) return;
    await DatabaseHelper.instance.updateTransaction(existing, updated);
    await _load();
    widget.onTransactionChanged?.call();
  }

  void _showTransferInfo(WalletTransaction tx) {
    const teal = Color(0xFF0D9488);
    final isOut = tx.type == 'transfer_out';
    final rawNote = tx.note ?? '';
    final userNote = rawNote.replaceAll(RegExp(r'\s*__ref:[^_]+__'), '').trim();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isOut ? Icons.arrow_upward : Icons.arrow_downward,
                      color: teal,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isOut ? 'Transfer Out' : 'Transfer In',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          widget.account.name,
                          style: TextStyle(
                              color: theme.colorScheme.outline, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${isOut ? '−' : '+'}₱${_fmt(tx.amount)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isOut ? Colors.red : teal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (userNote.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.note_outlined),
                  title: const Text('Note'),
                  subtitle: Text(userNote),
                  contentPadding: EdgeInsets.zero,
                ),
              ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Date'),
                subtitle: Text(
                    tx.date.length >= 10 ? tx.date.substring(0, 10) : tx.date),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor =
        _typeColors[widget.account.type] ?? theme.colorScheme.primary;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(
          children: [
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
                    _typeIcons[widget.account.type] ??
                        Icons.account_balance_wallet,
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
                            (_typeLabels[widget.account.type] ??
                                    widget.account.type)
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
                                  fontSize: 11,
                                  color: theme.colorScheme.outline),
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
                      '₱ ${_fmt(widget.account.balance)}',
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
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Transactions',
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.outline)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _transactions.isEmpty
                      ? Center(
                          child: Text('No transactions for this account',
                              style:
                                  TextStyle(color: theme.colorScheme.outline)))
                      : ListView.separated(
                          controller: scrollCtrl,
                          itemCount: _transactions.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) {
                            final tx = _transactions[i];
                            final isIncome = tx.type == 'income';
                            final isTransferOut = tx.type == 'transfer_out';
                            final isTransferIn = tx.type == 'transfer_in';
                            final isTransfer = isTransferOut || isTransferIn;
                            const teal = Color(0xFF0D9488);
                            final rowColor = isTransfer
                                ? teal
                                : isIncome
                                    ? Colors.green
                                    : Colors.red;
                            final bgColor = isTransfer
                                ? const Color(0xFFCCFBF1)
                                : isIncome
                                    ? Colors.green.shade100
                                    : Colors.red.shade100;
                            final amountPrefix = isTransferOut
                                ? '−'
                                : isTransferIn
                                    ? '+'
                                    : isIncome
                                        ? '+'
                                        : '−';

                            // For transfers: find the paired account
                            String subtitle =
                                '${tx.category} • ${tx.date.substring(0, 10)}';
                            if (isTransfer) {
                              // Extract ref from note to find paired leg
                              final refMatch = RegExp(r'__ref:([^_]+)__')
                                  .firstMatch(tx.note ?? '');
                              final ref = refMatch?.group(1);
                              if (ref != null) {
                                // Search all transfer transactions for the paired leg
                                final paired = _allTransferTxs.firstWhere(
                                  (t) =>
                                      t.id != tx.id &&
                                      (t.type == 'transfer_out' ||
                                          t.type == 'transfer_in') &&
                                      (t.note?.contains('__ref:$ref') ?? false),
                                  orElse: () => tx,
                                );
                                // If we didn't find the pair in same account, search all accounts
                                final pairedAccount = _allAccounts.firstWhere(
                                  (a) => a.id == paired.accountId,
                                  orElse: () => Account(
                                      name: 'Unknown',
                                      balance: 0,
                                      type: '',
                                      colorHex: '',
                                      icon: ''),
                                );
                                final thisAccount = widget.account.name;
                                if (isTransferOut) {
                                  subtitle =
                                      '$thisAccount → ${pairedAccount.name}';
                                } else {
                                  subtitle =
                                      '${pairedAccount.name} → $thisAccount';
                                }
                              } else {
                                subtitle = isTransferOut
                                    ? 'Transfer Out'
                                    : 'Transfer In';
                              }
                            }

                            return ListTile(
                              onTap: () => _editTransaction(tx),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              tileColor: theme
                                  .colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              leading: CircleAvatar(
                                backgroundColor: bgColor,
                                radius: 18,
                                child: Icon(
                                  isTransfer
                                      ? (isTransferOut
                                          ? Icons.arrow_upward
                                          : Icons.arrow_downward)
                                      : (isIncome
                                          ? Icons.arrow_downward
                                          : Icons.arrow_upward),
                                  color: rowColor,
                                  size: 16,
                                ),
                              ),
                              title: Text(
                                  isTransfer
                                      ? (isTransferOut
                                          ? 'Transfer Out'
                                          : 'Transfer In')
                                      : tx.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              subtitle: Text(subtitle,
                                  style: const TextStyle(fontSize: 12)),
                              trailing: Text(
                                '$amountPrefix₱${_fmt(tx.amount)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: rowColor,
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ── Small stacked income/expense chip used in _AccountDetailSheet header ───────

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
          '₱ ${_fmt(amount)}',
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
