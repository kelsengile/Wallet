import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wallet/database/database_helper.dart';
import 'package:wallet/currency.dart';
import 'package:wallet/pages/accounts_page.dart';
import 'package:wallet/pages/history_page.dart';
import 'package:wallet/pages/analytics_page.dart';
import 'package:wallet/pages/profile_page.dart';
import 'package:wallet/pages/settings_page.dart';
import 'package:wallet/pages/category_manager_page.dart';
import 'package:wallet/pages/faq_page.dart';
import 'package:wallet/pages/feedback_page.dart';
import 'package:wallet/pages/trash_bin_page.dart';
import 'package:wallet/models/transaction_model.dart';

/// Global dark-mode toggle, readable/writable from anywhere (currently just
/// the Settings page). Persisted to the `settings` table so the choice
/// survives app restarts.
final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier(ThemeMode.light);

const _kDarkModeSettingKey = 'dark_mode';

Future<void> _loadSavedThemeMode() async {
  final saved = await DatabaseHelper.instance.getSetting(_kDarkModeSettingKey);
  themeModeNotifier.value = saved == 'true' ? ThemeMode.dark : ThemeMode.light;
}

/// Call this from Settings whenever the user flips the Dark Mode switch.
Future<void> setDarkMode(bool enabled) async {
  themeModeNotifier.value = enabled ? ThemeMode.dark : ThemeMode.light;
  await DatabaseHelper.instance
      .saveSetting(_kDarkModeSettingKey, enabled.toString());
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _loadSavedThemeMode();
  await loadSavedCurrency();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Wallet',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          // Rebuilds the whole home subtree (without losing State, since
          // WalletHomePage is non-const below) whenever the currency
          // changes, so every already-mounted page re-reads
          // currencySymbolNotifier.value and shows the new symbol
          // immediately — no per-widget listeners needed.
          home: ValueListenableBuilder<String>(
            valueListenable: currencySymbolNotifier,
            // ignore: prefer_const_constructors
            builder: (context, symbol, _) => WalletHomePage(),
          ),
        );
      },
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
  final _accountsKey = GlobalKey<AccountsPageState>();
  final _analyticsKey = GlobalKey<AnalyticsPageState>();
  bool _fabVisible = true;
  // 0.0 = fully on accounts tab, 1.0 = fully off it — drives status bar style.
  // Uses a ValueNotifier so scroll updates never trigger a full widget rebuild.
  final _pageTNotifier = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    _pageController.addListener(_onPageScroll);
  }

  void _onPageScroll() {
    // Store raw page position (not clamped to 1) so status-bar notifier also
    // covers the History→Analytics transition.
    final t = (_pageController.page ?? 0.0).clamp(0.0, 3.0);
    if ((t - _pageTNotifier.value).abs() > 0.005) {
      _pageTNotifier.value = t;
    }
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    _pageTNotifier.dispose();
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

  Future<void> _onRefresh() async {
    switch (_selectedIndex) {
      case 0:
        await _accountsKey.currentState?.refresh();
        break;
      case 1:
        await _historyKey.currentState?.refresh();
        break;
      case 2:
        await _analyticsKey.currentState?.refresh();
        break;
      // Profile page (3) has no async data to refresh
    }
  }

  /// Called after the database has been wiped from the "Clear All Data"
  /// drawer action. Refreshes every page that caches data so the UI
  /// reflects the empty state immediately, and jumps back to the
  /// Accounts tab.
  Future<void> _onDataCleared() async {
    await Future.wait([
      _accountsKey.currentState?.refresh() ?? Future.value(),
      _historyKey.currentState?.refresh() ?? Future.value(),
      _analyticsKey.currentState?.refresh() ?? Future.value(),
    ]);
    if (_selectedIndex != 0) {
      _onItemTapped(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<double>(
      valueListenable: _pageTNotifier,
      builder: (context, pageT, child) {
        // The NavigationBar uses surfaceContainer as its background in M3.
        // Mirror that colour on the phone's system navigation bar so the
        // gesture/button strip blends seamlessly with the app's bottom bar.
        final navBarColor = theme.colorScheme.surfaceContainer;
        final navBarIconBrightness = theme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark;

        // Status bar icons: light (white) on Accounts + History, dark on Analytics+.
        // Switches at the midpoint of the History→Analytics swipe (pageT crosses 1.5).
        final overlayStyle = pageT < 1.5
            ? SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
                systemNavigationBarColor: navBarColor,
                systemNavigationBarIconBrightness: navBarIconBrightness,
                systemNavigationBarContrastEnforced: false,
              )
            : SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
                systemNavigationBarColor: navBarColor,
                systemNavigationBarIconBrightness: navBarIconBrightness,
                systemNavigationBarContrastEnforced: false,
              );
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle,
          child: child!,
        );
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        drawer: _WalletDrawer(
          selectedIndex: _selectedIndex,
          onNavigate: (index) {
            _onItemTapped(index);
            Navigator.pop(context);
          },
          onDataCleared: _onDataCleared,
          onCategoryChanged: () async {
            await _accountsKey.currentState?.refresh();
          },
          onAccountRestored: () {
            _accountsKey.currentState?.refresh();
          },
        ),
        body: RefreshIndicator(
          onRefresh: _onRefresh,
          // edgeOffset: 0 means the spinner appears from the very top of the
          // screen, above the transparent _TopNavBar overlay.
          edgeOffset: 0,
          child: Stack(
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
                  physics: const PageScrollPhysics(),
                  children: [
                    _PageSeparator(
                      pageController: _pageController,
                      index: 0,
                      child: AccountsPage(
                        key: _accountsKey,
                        onNavigateToAnalytics: () => _onItemTapped(2),
                      ),
                    ),
                    // History page handles its own top padding/overlay,
                    // like AccountsPage's total balance hero.
                    _PageSeparator(
                      pageController: _pageController,
                      index: 1,
                      child: HistoryPage(key: _historyKey),
                    ),
                    // Remaining pages: add top padding so content
                    // isn't hidden behind the transparent nav overlay.
                    _PageSeparator(
                      pageController: _pageController,
                      index: 2,
                      child: _WithTopNavPadding(
                          child: AnalyticsPage(key: _analyticsKey)),
                    ),
                    _PageSeparator(
                      pageController: _pageController,
                      index: 3,
                      child: const _WithTopNavPadding(child: ProfilePage()),
                    ),
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
                    curve:
                        _fabVisible ? Curves.easeOutCubic : Curves.easeInCubic,
                    child: AnimatedOpacity(
                      opacity: _fabVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 260),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _SpeedDialFab(
                          onAddIncome: () async {
                            final accounts = await DatabaseHelper.instance
                                .getAccountsSortedByLatestTransaction();
                            final registry = await DatabaseHelper.instance
                                .getCategoryRegistry();
                            final typeOrder =
                                await DatabaseHelper.instance.getTypeOrder();
                            if (!context.mounted) return;
                            final tx = await WalletTransaction.showDialog(
                              context,
                              accounts: accounts,
                              categories:
                                  registry.selectableTransactionCategories,
                              accountTypes: registry.accountTypes,
                              accountCategories: registry.accountCategories,
                              type: 'income',
                              typeOrder: typeOrder,
                            );
                            if (tx == null) return;
                            await DatabaseHelper.instance.insertTransaction(tx);
                            if (tx.accountId != null) {
                              _accountsKey.currentState
                                  ?.applyBalanceDelta(tx.accountId!, tx.amount);
                            }
                            _historyKey.currentState?.refresh();
                          },
                          onAddExpense: () async {
                            final accounts = await DatabaseHelper.instance
                                .getAccountsSortedByLatestTransaction();
                            final registry = await DatabaseHelper.instance
                                .getCategoryRegistry();
                            final typeOrder =
                                await DatabaseHelper.instance.getTypeOrder();
                            if (!context.mounted) return;
                            final tx = await WalletTransaction.showDialog(
                              context,
                              accounts: accounts,
                              categories:
                                  registry.selectableTransactionCategories,
                              accountTypes: registry.accountTypes,
                              accountCategories: registry.accountCategories,
                              type: 'expense',
                              typeOrder: typeOrder,
                            );
                            if (tx == null) return;
                            await DatabaseHelper.instance.insertTransaction(tx);
                            if (tx.accountId != null) {
                              _accountsKey.currentState?.applyBalanceDelta(
                                  tx.accountId!, -tx.amount);
                            }
                            _historyKey.currentState?.refresh();
                          },
                          onTransfer: () async {
                            final accounts = await DatabaseHelper.instance
                                .getAccountsSortedByLatestTransaction();
                            final registry = await DatabaseHelper.instance
                                .getCategoryRegistry();
                            final typeOrder =
                                await DatabaseHelper.instance.getTypeOrder();
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
                              accountTypes: registry.accountTypes,
                              typeOrder: typeOrder,
                            );
                            if (result == null) return;
                            await DatabaseHelper.instance.insertTransfer(
                              fromAccountId: result.fromAccountId,
                              toAccountId: result.toAccountId,
                              amount: result.amount,
                              date: result.date,
                              note: result.note,
                            );
                            _accountsKey.currentState?.applyTransferDelta(
                              result.fromAccountId,
                              result.toAccountId,
                              result.amount,
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
          ), // Stack
        ), // RefreshIndicator
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
  // ignore: unused_field
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

    // Rotate 45° when open to turn + into ×
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _spinAnim = Tween<double>(begin: 0, end: 0.125).animate(
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
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 3,
                  ),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
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
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final size = (screenWidth * 0.155).clamp(56.0, 68.0);
    final iconSize = size * 0.5;

    final fabColor = _open
        ? cs.surface
        : isDark
            ? const Color(0xFF3A3A40)
            : cs.primary;

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
            color: isDark ? const Color(0xFF3A3A40) : const Color(0xFF0D9488),
            onTap: widget.onTransfer,
            index: 0,
          ),
          _miniButton(
            icon: Icons.arrow_upward,
            label: 'Expense',
            color: isDark ? const Color(0xFF4A2A2A) : Colors.red,
            onTap: widget.onAddExpense,
            index: 1,
          ),
          _miniButton(
            icon: Icons.arrow_downward,
            label: 'Income',
            color: isDark ? const Color(0xFF1E3A2A) : Colors.green,
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
                color: fabColor,
                border: Border.all(
                  color: theme.colorScheme.surface,
                  width: 3.5,
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  _open ? Icons.close : Icons.add,
                  key: ValueKey(_open),
                  color: _open ? theme.colorScheme.onSurface : Colors.white,
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
  double _page =
      0.0; // raw page position (0.0 = accounts, 1.0 = history, 2.0 = analytics …)

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
    if ((page - _page).abs() > 0.001) setState(() => _page = page);
  }

  /// Returns a color that smoothly lerps across three waypoints:
  ///   page 0 → [c0]  (Accounts)
  ///   page 1 → [c1]  (History)
  ///   page 2+ → [c2] (Analytics and beyond)
  Color _lerpColor(Color c0, Color c1, Color c2) {
    if (_page <= 1.0) {
      // Segment 1: Accounts → History
      return Color.lerp(c0, c1, _page.clamp(0.0, 1.0))!;
    } else {
      // Segment 2: History → Analytics
      return Color.lerp(c1, c2, (_page - 1.0).clamp(0.0, 1.0))!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final topPadding = MediaQuery.paddingOf(context).top;

    // ── Colour waypoints ──────────────────────────────────────────────────────
    // Accounts (page 0):  white icons over gradient hero
    // History  (page 1):  deep-indigo tinted icons
    // Analytics (page 2): teal/tertiary tinted icons

    // Icon colour:  white (Accounts) → white (History) → onSurface/dark (Analytics+)
    final iconColor = _lerpColor(
      Colors.white,
      Colors.white,
      cs.onSurface,
    );

    // Subtitle colour:  white70 → white70 → onSurfaceVariant
    final subtitleColor = _lerpColor(
      Colors.white70,
      Colors.white70,
      cs.onSurfaceVariant,
    );

    // Pill background:  white.20 → white.20 → onSurface.10
    final pillColor = _lerpColor(
      Colors.white.withValues(alpha: 0.20),
      Colors.white.withValues(alpha: 0.20),
      cs.onSurface.withValues(alpha: 0.10),
    );

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

class _WalletDrawer extends StatefulWidget {
  final int selectedIndex;
  final void Function(int) onNavigate;
  final VoidCallback onDataCleared;
  final VoidCallback onCategoryChanged;
  final VoidCallback onAccountRestored;

  const _WalletDrawer({
    required this.selectedIndex,
    required this.onNavigate,
    required this.onDataCleared,
    required this.onCategoryChanged,
    required this.onAccountRestored,
  });

  @override
  State<_WalletDrawer> createState() => _WalletDrawerState();
}

class _WalletDrawerState extends State<_WalletDrawer> {
  int _trashCount = 0;

  @override
  void initState() {
    super.initState();
    _loadTrashCount();
  }

  Future<void> _loadTrashCount() async {
    final count = await DatabaseHelper.instance.getTrashCount();
    if (mounted) setState(() => _trashCount = count);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final isDark = theme.brightness == Brightness.dark;
    final drawerGradientColors = isDark
        ? [const Color(0xFF2A2A2E), const Color(0xFF3A3A40)]
        : [cs.primary, cs.tertiary];

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
                colors: drawerGradientColors,
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
                  selected: widget.selectedIndex == 0,
                  onTap: () => widget.onNavigate(0),
                ),
                _NavTile(
                  icon: Icons.history_outlined,
                  selectedIcon: Icons.history,
                  label: 'History',
                  selected: widget.selectedIndex == 1,
                  onTap: () => widget.onNavigate(1),
                ),
                _NavTile(
                  icon: Icons.show_chart_outlined,
                  selectedIcon: Icons.show_chart,
                  label: 'Analytics',
                  selected: widget.selectedIndex == 2,
                  onTap: () => widget.onNavigate(2),
                ),
                _NavTile(
                  icon: Icons.person_outline,
                  selectedIcon: Icons.person,
                  label: 'Profile',
                  selected: widget.selectedIndex == 3,
                  onTap: () => widget.onNavigate(3),
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
                    ).then((_) {
                      _loadTrashCount();
                      widget.onCategoryChanged();
                    });
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

                // ── Trash Bin ───────────────────────────────────────────────
                _NavTileWithBadge(
                  icon: Icons.delete_outline,
                  selectedIcon: Icons.delete,
                  label: 'Trash',
                  badgeCount: _trashCount,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TrashBinPage()),
                    ).then((_) {
                      _loadTrashCount();
                      widget.onAccountRestored();
                    });
                  },
                ),

                _NavTile(
                  icon: Icons.delete_forever_outlined,
                  selectedIcon: Icons.delete_forever,
                  label: 'Clear All Data',
                  destructive: true,
                  onTap: () {
                    // Grab a stable reference *before* the drawer closes —
                    // once popped, the drawer's own context is deactivated
                    // and can no longer be used to look up ancestors.
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(context);
                    _showClearDataDialog(context, messenger);
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

  void _showClearDataDialog(
      BuildContext context, ScaffoldMessengerState messenger) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
          'This will permanently delete all accounts, transactions, and trash. Are you sure?',
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
                messenger.showSnackBar(
                  const SnackBar(content: Text('All data cleared.')),
                );
              }
              _loadTrashCount();
              widget.onDataCleared();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

// ── Page separator ───────────────────────────────────────────────────────────

/// Wraps a PageView child so it scales down very slightly while it's not
/// the fully-active page. When settled on a page, scale is exactly 1.0 —
/// the page's own design/layout is untouched. While swiping, both the
/// outgoing and incoming pages shrink a touch, revealing the scaffold
/// background between them like a small added buffer.
class _PageSeparator extends StatelessWidget {
  final PageController pageController;
  final int index;
  final Widget child;

  const _PageSeparator({
    required this.pageController,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pageController,
      builder: (context, child) {
        double scaleX = 1.0;
        if (pageController.hasClients &&
            pageController.position.haveDimensions) {
          final page =
              pageController.page ?? pageController.initialPage.toDouble();
          final distance = (page - index).abs().clamp(0.0, 1.0);
          scaleX = 1.0 - distance * 0.03;
        }
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(scaleX, 1.0, 1.0),
          child: child,
        );
      },
      child: child,
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

// ── Nav tile with a red count badge (used for Trash Bin) ──────────────────────

class _NavTileWithBadge extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badgeCount;
  final VoidCallback onTap;

  const _NavTileWithBadge({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.badgeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // ignore: unused_local_variable
    final cs = theme.colorScheme;
    const color = Colors.red;

    return ListTile(
      dense: true,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, color: color, size: 22),
          if (badgeCount > 0)
            Positioned(
              top: -4,
              right: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(color: color),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      horizontalTitleGap: 8,
      onTap: onTap,
    );
  }
}
