import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/account_model.dart';
import '../models/transaction_model.dart';
import '../models/category_model.dart';

// ── Number formatter ───────────────────────────────────────────────────────────

final _currencyFmt = NumberFormat('#,##0.00', 'en_PH');

String _fmt(double v) => _currencyFmt.format(v);

// ── Type metadata ──────────────────────────────────────────────────────────────
//
// All account-type colors, icons, gradients, and labels now come from the
// CategoryRegistry (loaded from the DB), so changes in the Category Manager
// are immediately reflected on account cards. The registry is stored in a
// module-level notifier so widgets at any depth can rebuild when it updates.

final _registryNotifier =
    ValueNotifier<CategoryRegistry>(CategoryRegistry.empty());

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
      builder: (ctx) => _DeleteAccountDialog(accountName: account.name),
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
        onEditAccount: (a) {
          // Open the edit form; on save, pop the detail sheet too so the
          // freshly-reloaded card reflects the new colors immediately.
          _showEditAndRefreshDetail(a, ctx);
        },
      ),
    );
  }

  void _showEditAndRefreshDetail(Account account, BuildContext detailCtx) {
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
    );
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
                    onCardLongPress: (_) {},
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
    // Extend gradient behind the transparent top nav bar overlay.
    final topPadding = MediaQuery.paddingOf(context).top;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, topPadding + 80, 20, 36),
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
    final accountColor = account.colorHex.isNotEmpty
        ? colorFromHex(account.colorHex)
        : const Color(0xFF6366F1);
    final gradients = gradientForColor(accountColor);
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
    final accountColor = account.colorHex.isNotEmpty
        ? colorFromHex(account.colorHex)
        : const Color(0xFF6366F1);
    final gradients = gradientForColor(accountColor);
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
          // Category icon (top-right corner)
          Positioned(
            top: 12,
            right: 12,
            child: ValueListenableBuilder<CategoryRegistry>(
              valueListenable: _registryNotifier,
              builder: (context, registry, _) {
                final catEntry = registry.accountCategories
                    .where((c) => c.name == account.category)
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
  final Future<void> Function()? onDelete;

  const _AccountFormSheet({this.existing, required this.onSave, this.onDelete});

  @override
  State<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends State<_AccountFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _balanceCtrl;
  String? _selectedType;
  String? _selectedCategory;

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
                      )
                    : Account(
                        name: _nameCtrl.text.trim(),
                        balance:
                            double.tryParse(_balanceCtrl.text.trim()) ?? 0.0,
                        type: _selectedType!,
                        category: _selectedCategory!,
                        colorHex: typeHex,
                        icon: 'wallet',
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
                      accountName: widget.existing!.name,
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
  List<WalletTransaction> _allTransferTxs = [];
  List<WalletCategory> _txCategories = [];
  List<WalletCategory> _accountTypes = [];
  List<WalletCategory> _accountCategories = [];
  bool _loading = true;

  // ── Current-month transactions ────────────────────────────────────────────
  List<WalletTransaction> get _currentMonthTransactions {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final monthEnd = DateTime(now.year, now.month + 1);
    return _transactions.where((tx) {
      final d = DateTime.tryParse(tx.date);
      return d != null && !d.isBefore(monthStart) && d.isBefore(monthEnd);
    }).toList();
  }

  // ── Transfer pair helper ──────────────────────────────────────────────────
  static String? _extractRef(String? note) {
    if (note == null) return null;
    final match = RegExp(r'__ref:([^_]+)__').firstMatch(note);
    return match?.group(1);
  }

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

  Future<void> _editTransaction(WalletTransaction existing) async {
    if (existing.type == 'transfer_out' || existing.type == 'transfer_in') {
      _showTransferInfo(existing);
      return;
    }
    final updated = await WalletTransaction.showDialog(
      context,
      accounts: _allAccounts,
      categories: _txCategories,
      accountTypes: _accountTypes,
      accountCategories: _accountCategories,
      existing: existing,
      type: existing.type,
    );
    if (updated == null) return;
    await DatabaseHelper.instance.updateTransaction(existing, updated);
    await _load();
    widget.onTransactionChanged?.call();
  }

  void _showTransferInfo(WalletTransaction tx) {
    const transferColor = Color(0xFF2563EB);
    const transferBgColor = Color(0xFFDBEAFE);
    final isOut = tx.type == 'transfer_out';
    final rawNote = tx.note ?? '';
    final userNote = rawNote.replaceAll(RegExp(r'\s*__ref:[^_]+__'), '').trim();

    // Resolve the paired account name
    String pairedAccountName = isOut ? 'Transfer Out' : 'Transfer In';
    final ref = _extractRef(rawNote);
    if (ref != null) {
      final pairedTx = _allTransferTxs
          .where(
              (t) => t.id != tx.id && (t.note?.contains('__ref:$ref') ?? false))
          .firstOrNull;
      if (pairedTx != null) {
        pairedAccountName = _allAccounts
            .firstWhere(
              (a) => a.id == pairedTx.accountId,
              orElse: () => Account(
                  name: 'Unknown',
                  balance: 0,
                  type: '',
                  colorHex: '',
                  icon: ''),
            )
            .name;
      }
    }

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
                      color: transferBgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.swap_horiz_rounded,
                      color: transferColor,
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
                          isOut
                              ? 'to $pairedAccountName'
                              : 'from $pairedAccountName',
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
                      color: isOut ? Colors.red : transferColor,
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
    final typeColor = _registryNotifier.value.typeColor(widget.account.type) !=
            const Color(0xFF6366F1)
        ? _registryNotifier.value.typeColor(widget.account.type)
        : (widget.account.colorHex.isNotEmpty
            ? colorFromHex(widget.account.colorHex)
            : theme.colorScheme.primary);

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
            // ── Transactions label ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Transactions',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.70),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _currentMonthTransactions.isEmpty
                      ? Center(
                          child: Text(
                            _transactions.isEmpty
                                ? 'No transactions for this account'
                                : 'No transactions this month.',
                            style: TextStyle(color: theme.colorScheme.outline),
                          ),
                        )
                      : _buildGroupedList(
                          _currentMonthTransactions, theme, scrollCtrl),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteTransaction(WalletTransaction tx) async {
    await DatabaseHelper.instance.deleteTransaction(tx);
    await _load();
    widget.onTransactionChanged?.call();
  }

  Widget _buildGroupedList(
      List<WalletTransaction> txs, ThemeData theme, ScrollController ctrl) {
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
      controller: ctrl,
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
          const transferColor = Color(0xFF2563EB);
          const transferBgColor = Color(0xFFDBEAFE);
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
                    confirmDismiss: (_) async {
                      return await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Transfer'),
                          content: const Text(
                              'This will delete both legs of the transfer.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel')),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                    },
                    onDismissed: (_) async {
                      await _deleteTransaction(outTx);
                      await _deleteTransaction(inTx);
                    },
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      onTap: () => _showTransferInfo(outTx),
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: transferBgColor,
                        child: Icon(
                          transferIcon,
                          size: 20,
                          color: transferColor,
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
                        '$transferAmountPrefix ₱${_fmt(outTx.amount)}',
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
        final rowColor = isIncome ? Colors.green : Colors.red;
        final bgColor = isIncome ? Colors.green.shade100 : Colors.red.shade100;
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
                      '$amountPrefix ₱${_fmt(tx.amount)}',
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
  final String accountName;

  const _DeleteAccountDialog({required this.accountName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                      Icon(Icons.account_balance_wallet_outlined,
                          size: 15, color: Colors.red.shade700),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          accountName,
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
