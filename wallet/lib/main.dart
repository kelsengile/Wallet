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

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
  }

  @override
  void dispose() {
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
    final isAccountsTab = _selectedIndex == 0;

    final overlayStyle = isAccountsTab
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
            // ── Main content ────────────────────────────────────────────────
            Column(
              children: [
                // ── Top nav bar ───────────────────────────────────────────
                _TopNavBar(isAccountsTab: isAccountsTab),

                // ── Swipeable page content ────────────────────────────────
                Expanded(
                  child: NotificationListener<ScrollNotification>(
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
                      physics: const BouncingScrollPhysics(),
                      children: [
                        AccountsPage(
                          onNavigateToAnalytics: () => _onItemTapped(2),
                        ),
                        HistoryPage(key: _historyKey),
                        const AnalyticsPage(),
                        const ProfilePage(),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // ── FAB — slides DOWN into the nav bar when hidden ──────────────
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
                      child: _AddTransactionFab(
                        onPressed: () async {
                          final accounts =
                              await DatabaseHelper.instance.getAllAccounts();
                          if (!context.mounted) return;
                          final tx = await WalletTransaction.showDialog(
                            context,
                            accounts: accounts,
                          );
                          if (tx == null) return;
                          await DatabaseHelper.instance.insertTransaction(tx);
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

// ── Floating add-transaction button ───────────────────────────────────────────

class _AddTransactionFab extends StatelessWidget {
  final VoidCallback onPressed;
  const _AddTransactionFab({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scale the button relative to screen width so it looks right on all sizes:
    // phones (~360–430 dp wide) → ~52 dp; tablets → capped at 60 dp.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final size = (screenWidth * 0.135).clamp(48.0, 60.0);
    final iconSize = size * 0.5;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary,
          ),
          child: Icon(Icons.add, color: Colors.white, size: iconSize),
        ),
      ),
    );
  }
}

// ── Top nav bar ────────────────────────────────────────────────────────────────
//
// Extracted into its own StatelessWidget so that keyboard-triggered
// MediaQuery viewInsets changes (which cause WalletHomePage to rebuild)
// do NOT force an expensive AnimatedContainer + gradient repaint.
// The widget is cheap to diff; Flutter skips its subtree when props are equal.

class _TopNavBar extends StatelessWidget {
  final bool isAccountsTab;
  const _TopNavBar({required this.isAccountsTab});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Read only the top padding — not viewInsets — so the keyboard opening
    // on a different page does not cause this widget to repaint.
    final topPadding = MediaQuery.paddingOf(context).top;

    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          gradient: isAccountsTab
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.tertiary,
                  ],
                )
              : null,
          color: isAccountsTab ? null : theme.colorScheme.surface,
        ),
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
                icon: Icon(
                  Icons.menu,
                  color: isAccountsTab ? Colors.white : null,
                ),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                tooltip: 'Menu',
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: isAccountsTab
                    ? Colors.white.withValues(alpha: 0.2)
                    : theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.account_balance_wallet,
                size: 18,
                color: isAccountsTab
                    ? Colors.white
                    : theme.colorScheme.onPrimaryContainer,
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
                    color: isAccountsTab ? Colors.white : null,
                  ),
                ),
                Text(
                  'Manage your money',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isAccountsTab
                        ? Colors.white70
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const Spacer(),
            IconButton(
              icon: Icon(
                Icons.search,
                color: isAccountsTab ? Colors.white : null,
              ),
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
