import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wallet/database/database_helper.dart';
import 'package:wallet/pages/accounts_page.dart';
import 'package:wallet/pages/history_page.dart';
import 'package:wallet/pages/analytics_page.dart';
import 'package:wallet/pages/profile_page.dart';
import 'package:wallet/pages/settings_page.dart';
import 'package:wallet/pages/category_manager_page.dart';
import 'package:wallet/pages/faq_page.dart';
import 'package:wallet/pages/feedback_page.dart';
import 'package:wallet/models/transaction_model.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const WalletHomePage(),
    );
  }
}

class WalletHomePage extends StatefulWidget {
  const WalletHomePage({super.key});

  @override
  State<WalletHomePage> createState() => _WalletHomePageState();
}

class _WalletHomePageState extends State<WalletHomePage> {
  int _selectedIndex = 0;
  late final PageController _pageController;
  final _historyKey = GlobalKey<HistoryPageState>();
  bool _fabVisible = true;
  // 0.0 = fully on accounts tab, 1.0 = fully off it — drives status bar style.
  double _pageT = 0.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    _pageController.addListener(_onPageScroll);
  }

  void _onPageScroll() {
    final t = (_pageController.page ?? 0.0).clamp(0.0, 1.0);
    if ((t - _pageT).abs() > 0.005) setState(() => _pageT = t);
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Status bar icons: light (white) on accounts tab, dark on all others.
    // Switches at the midpoint of the drag so it's never jarring.
    final overlayStyle = _pageT < 0.5
        ? const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          )
        : const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        drawer: _WalletDrawer(
          selectedIndex: _selectedIndex,
          onNavigate: (index) {
            _onItemTapped(index);
            Navigator.pop(context);
          },
        ),
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Main content (full height, nav bar overlays it) ─────────────
            NotificationListener<ScrollNotification>(
              onNotification: (n) {
                // Only react to vertical scrolls — ignore horizontal
                // PageView swipe notifications entirely.
                if (n is ScrollUpdateNotification &&
                    n.metrics.axis == Axis.vertical) {
                  final delta = n.scrollDelta ?? 0;
                  if (delta > 4 && _fabVisible) {
                    setState(() => _fabVisible = false);
                  } else if (delta < -4 && !_fabVisible) {
                    setState(() => _fabVisible = true);
                  }
                }
                return false;
              },
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) {
                  _onPageChanged(i);
                  setState(() => _fabVisible = true);
                },
                physics: const ClampingScrollPhysics(),
                children: [
                  AccountsPage(
                    onNavigateToAnalytics: () => _onItemTapped(2),
                  ),
                  // Non-accounts pages: add top padding so content
                  // isn't hidden behind the transparent nav overlay.
                  _WithTopNavPadding(child: HistoryPage(key: _historyKey)),
                  const _WithTopNavPadding(child: AnalyticsPage()),
                  const _WithTopNavPadding(child: ProfilePage()),
                ],
              ),
            ),

            // ── Top nav bar — transparent overlay, no background ────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TopNavBar(pageController: _pageController),
            ),

            // ── FAB speed-dial — slides DOWN into the nav bar when hidden ──
            // ClipRect confines the button to the body bounds so it visually
            // disappears *behind* the NavigationBar rather than over it.
            Positioned(
              right: 16,
              bottom: 0,
              child: ClipRect(
                child: AnimatedSlide(
                  offset: _fabVisible ? Offset.zero : const Offset(0, 1.5),
                  duration: const Duration(milliseconds: 380),
                  curve: _fabVisible ? Curves.easeOutCubic : Curves.easeInCubic,
                  child: AnimatedOpacity(
                    opacity: _fabVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 260),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _SpeedDialFab(
                        onAddIncome: () async {
                          final accounts =
                              await DatabaseHelper.instance.getAllAccounts();
                          if (!context.mounted) return;
                          final tx = await WalletTransaction.showDialog(
                            context,
                            accounts: accounts,
                            initialType: 'income',
                          );
                          if (tx == null) return;
                          await DatabaseHelper.instance.insertTransaction(tx);
                          _historyKey.currentState?.refresh();
                        },
                        onAddExpense: () async {
                          final accounts =
                              await DatabaseHelper.instance.getAllAccounts();
                          if (!context.mounted) return;
                          final tx = await WalletTransaction.showDialog(
                            context,
                            accounts: accounts,
                            initialType: 'expense',
                          );
                          if (tx == null) return;
                          await DatabaseHelper.instance.insertTransaction(tx);
                          _historyKey.currentState?.refresh();
                        },
                        onTransfer: () async {
                          final accounts =
                              await DatabaseHelper.instance.getAllAccounts();
                          if (!context.mounted) return;
                          if (accounts.length < 2) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'You need at least 2 accounts to make a transfer.'),
                              ),
                            );
                            return;
                          }
                          final result = await WalletTransactionTransfer
                              .showTransferDialog(
                            context,
                            accounts: accounts,
                          );
                          if (result == null) return;
                          await DatabaseHelper.instance.insertTransfer(
                            fromAccountId: result.fromAccountId,
                            toAccountId: result.toAccountId,
                            amount: result.amount,
                            date: result.date,
                            note: result.note,
                          );
                          _historyKey.currentState?.refresh();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onItemTapped,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet),
              label: 'Accounts',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.show_chart_outlined),
              selectedIcon: Icon(Icons.show_chart),
              label: 'Analytics',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

// ── Speed-dial FAB (Income + Expense + Transfer) ──────────────────────────────

class _SpeedDialFab extends StatefulWidget {
  final VoidCallback onAddIncome;
  final VoidCallback onAddExpense;
  final VoidCallback onTransfer;

  const _SpeedDialFab({
    required this.onAddIncome,
    required this.onAddExpense,
    required this.onTransfer,
  });

  @override
  State<_SpeedDialFab> createState() => _SpeedDialFabState();
}

class _SpeedDialFabState extends State<_SpeedDialFab>
    with TickerProviderStateMixin {
  bool _open = false;

  // Controls expand/collapse of mini buttons
  late final AnimationController _ctrl;

  // Controls the double-spin of the + icon (0 → 1.0 = two full turns)
  late final AnimationController _spinCtrl;
  late final Animation<double> _spinAnim;

  // Per-button staggered slide+fade animations (Transfer=0, Expense=1, Income=2)
  late final List<AnimationController> _btnCtrls;
  late final List<Animation<double>> _btnSlide; // 0=at FAB, 1=final position
  late final List<Animation<double>> _btnFade;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Spin: 2 full turns over 420 ms
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _spinAnim = Tween<double>(begin: 0, end: 2.0).animate(
      CurvedAnimation(parent: _spinCtrl, curve: Curves.easeInOut),
    );

    // Three staggered controllers – each 280 ms, triggered with delay
    _btnCtrls = List.generate(
      3,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 280),
      ),
    );

    // Slide: 0 = sitting right on top of the FAB (no offset), 1 = final spot.
    // We animate the *spacing* rather than absolute offset by using a
    // SizeTransition on each gap – simpler and more reliable.
    _btnSlide = _btnCtrls
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeOutBack))
        .toList();

    _btnFade = _btnCtrls
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeOut))
        .toList();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _spinCtrl.dispose();
    for (final c in _btnCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _toggle() async {
    // Kick off the double-spin every time the FAB is tapped
    _spinCtrl.forward(from: 0);

    if (!_open) {
      setState(() => _open = true);
      _ctrl.forward();
      // Stagger: Income first (closest), then Expense, then Transfer
      // Indices: 0=Transfer, 1=Expense, 2=Income → reverse stagger order
      for (int i = 2; i >= 0; i--) {
        _btnCtrls[i].forward(from: 0);
        await Future.delayed(const Duration(milliseconds: 55));
      }
    } else {
      _close();
    }
  }

  Future<void> _close() async {
    if (!_open) return;
    setState(() => _open = false);
    // Collapse all at once (no stagger on close — snappy feel)
    for (final c in _btnCtrls) {
      c.reverse();
    }
    _ctrl.reverse();
  }

  Widget _miniButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required int index, // 0=Transfer, 1=Expense, 2=Income
  }) {
    // SizeTransition makes the button (and its spacing) grow from 0 height,
    // giving the illusion it bursts upward out of the main FAB.
    return SizeTransition(
      sizeFactor: _btnSlide[index],
      axisAlignment: 1.0, // anchor at bottom (near the FAB)
      child: FadeTransition(
        opacity: _btnFade[index],
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {
                _close();
                onTap();
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final size = (screenWidth * 0.135).clamp(48.0, 60.0);
    final iconSize = size * 0.5;

    // Wrap everything in a TapRegion so any tap outside this widget closes it.
    return TapRegion(
      onTapOutside: (_) => _close(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Mini buttons burst upward from the FAB (Transfer topmost)
          _miniButton(
            icon: Icons.swap_horiz,
            label: 'Transfer',
            color: const Color(0xFF0D9488),
            onTap: widget.onTransfer,
            index: 0,
          ),
          _miniButton(
            icon: Icons.arrow_upward,
            label: 'Expense',
            color: Colors.red,
            onTap: widget.onAddExpense,
            index: 1,
          ),
          _miniButton(
            icon: Icons.arrow_downward,
            label: 'Income',
            color: Colors.green,
            onTap: widget.onAddIncome,
            index: 2,
          ),
          // Main FAB
          GestureDetector(
            onTap: _toggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _open
                    ? theme.colorScheme.surfaceContainerHighest
                    : theme.colorScheme.primary,
              ),
              child: RotationTransition(
                turns: _spinAnim,
                child: Icon(
                  Icons.add,
                  color:
                      _open ? theme.colorScheme.onSurfaceVariant : Colors.white,
                  size: iconSize,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Top nav bar ────────────────────────────────────────────────────────────────
//
// Listens directly to the PageController so icon/text colors interpolate
// smoothly based on the exact drag position — no discrete jump at page snap.
// t = 0.0 → fully on accounts tab (white icons over gradient hero)
// t = 1.0 → fully off accounts tab (theme-colored icons, no background)

class _TopNavBar extends StatefulWidget {
  final PageController pageController;
  const _TopNavBar({required this.pageController});

  @override
  State<_TopNavBar> createState() => _TopNavBarState();
}

class _TopNavBarState extends State<_TopNavBar> {
  double _t = 0.0; // 0 = accounts, 1 = any other page

  @override
  void initState() {
    super.initState();
    widget.pageController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(_TopNavBar old) {
    super.didUpdateWidget(old);
    if (old.pageController != widget.pageController) {
      old.pageController.removeListener(_onScroll);
      widget.pageController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.pageController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final page = widget.pageController.page ?? 0.0;
    // Clamp to [0,1]: fully white at page 0, fully theme-colored from page 1+.
    final t = page.clamp(0.0, 1.0);
    if ((t - _t).abs() > 0.001) setState(() => _t = t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topPadding = MediaQuery.paddingOf(context).top;

    // Lerp icon color: white → onSurface
    final iconColor = Color.lerp(
      Colors.white,
      theme.colorScheme.onSurface,
      _t,
    )!;
    // Lerp subtitle color: white70 → onSurfaceVariant
    final subtitleColor = Color.lerp(
      Colors.white70,
      theme.colorScheme.onSurfaceVariant,
      _t,
    )!;
    // Lerp wallet icon pill background: white.20 → transparent
    final pillColor = Colors.white.withValues(alpha: (1 - _t) * 0.2);

    return RepaintBoundary(
      child: Container(
        // Always transparent — the page content is the background.
        color: Colors.transparent,
        padding: EdgeInsets.only(
          top: topPadding,
          left: 8,
          right: 8,
          bottom: 0,
        ),
        child: Row(
          children: [
            Builder(
              builder: (ctx) => IconButton(
                icon: Icon(Icons.menu, color: iconColor),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                tooltip: 'Menu',
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: pillColor,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.account_balance_wallet,
                size: 18,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Wallet',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                  ),
                ),
                Text(
                  'Manage your money',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: subtitleColor,
                  ),
                ),
              ],
            ),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.search, color: iconColor),
              onPressed: () {},
              tooltip: 'Search',
            ),
          ],
        ),
      ),
    );
  }
}

// ── Drawer ─────────────────────────────────────────────────────────────────────

class _WalletDrawer extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onNavigate;

  const _WalletDrawer({
    required this.selectedIndex,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Drawer(
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [cs.primary, cs.tertiary],
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.of(context).padding.top + 20,
              20,
              24,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wallet',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Manage your money',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Scrollable sections ───────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // PAGES
                _SectionHeader(label: 'Pages'),
                _NavTile(
                  icon: Icons.account_balance_wallet_outlined,
                  selectedIcon: Icons.account_balance_wallet,
                  label: 'Accounts',
                  selected: selectedIndex == 0,
                  onTap: () => onNavigate(0),
                ),
                _NavTile(
                  icon: Icons.history_outlined,
                  selectedIcon: Icons.history,
                  label: 'History',
                  selected: selectedIndex == 1,
                  onTap: () => onNavigate(1),
                ),
                _NavTile(
                  icon: Icons.show_chart_outlined,
                  selectedIcon: Icons.show_chart,
                  label: 'Analytics',
                  selected: selectedIndex == 2,
                  onTap: () => onNavigate(2),
                ),
                _NavTile(
                  icon: Icons.person_outline,
                  selectedIcon: Icons.person,
                  label: 'Profile',
                  selected: selectedIndex == 3,
                  onTap: () => onNavigate(3),
                ),

                const _DrawerDivider(),

                // PREFERENCES
                _SectionHeader(label: 'Preferences'),
                _NavTile(
                  icon: Icons.tune_outlined,
                  selectedIcon: Icons.tune,
                  label: 'Settings',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    );
                  },
                ),
                _NavTile(
                  icon: Icons.category_outlined,
                  selectedIcon: Icons.category,
                  label: 'Category Manager',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CategoryManagerPage()),
                    );
                  },
                ),

                const _DrawerDivider(),

                // HELP & SUPPORT
                _SectionHeader(label: 'Help & Support'),
                _NavTile(
                  icon: Icons.help_outline,
                  selectedIcon: Icons.help,
                  label: 'FAQ',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const FaqPage()),
                    );
                  },
                ),
                _NavTile(
                  icon: Icons.star_outline,
                  selectedIcon: Icons.star,
                  label: 'Rate the App',
                  onTap: () {
                    Navigator.pop(context);
                    _showRateDialog(context);
                  },
                ),
                _NavTile(
                  icon: Icons.feedback_outlined,
                  selectedIcon: Icons.feedback,
                  label: 'Send Feedback',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const FeedbackPage()),
                    );
                  },
                ),

                const _DrawerDivider(),

                // SYSTEM ACTIONS
                _SectionHeader(label: 'System Actions'),
                _NavTile(
                  icon: Icons.upload_outlined,
                  selectedIcon: Icons.upload,
                  label: 'Export Data',
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Export coming soon.')),
                    );
                  },
                ),
                _NavTile(
                  icon: Icons.download_outlined,
                  selectedIcon: Icons.download,
                  label: 'Import Data',
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Import coming soon.')),
                    );
                  },
                ),
                _NavTile(
                  icon: Icons.delete_forever_outlined,
                  selectedIcon: Icons.delete_forever,
                  label: 'Clear All Data',
                  destructive: true,
                  onTap: () {
                    Navigator.pop(context);
                    _showClearDataDialog(context);
                  },
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),

          // ── Version badge ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, size: 14, color: cs.outline),
                  const SizedBox(width: 6),
                  Text(
                    'Wallet App  •  v1.0.0',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.outline,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rate Wallet'),
        content: const Text(
          'Enjoying the app? Leave a rating on the store to help others find it!',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Rate Now'),
          ),
        ],
      ),
    );
  }

  void _showClearDataDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
          'This will permanently delete all accounts and transactions. Are you sure?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await DatabaseHelper.instance.clearAllData();
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All data cleared.')),
                );
              }
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

// ── Drawer helpers ─────────────────────────────────────────────────────────────

class _WithTopNavPadding extends StatelessWidget {
  final Widget child;
  const _WithTopNavPadding({required this.child});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top + 56;
    return Padding(
      padding: EdgeInsets.only(top: topPad),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
          letterSpacing: 1.2,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _DrawerDivider extends StatelessWidget {
  const _DrawerDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Divider(
        height: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final bool destructive;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = destructive
        ? Colors.red
        : selected
            ? cs.primary
            : cs.onSurfaceVariant;

    return ListTile(
      dense: true,
      leading: Icon(
        selected ? selectedIcon : icon,
        color: color,
        size: 22,
      ),
      title: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: color,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: selected,
      selectedTileColor: cs.primaryContainer.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      horizontalTitleGap: 8,
      onTap: onTap,
    );
  }
}
