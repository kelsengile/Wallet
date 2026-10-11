import 'package:flutter/material.dart';

import 'core/constants.dart';
import 'core/screens/categories.dart';
import 'core/screens/faq.dart';
import 'core/screens/feedback.dart';
import 'core/screens/profile.dart';
import 'core/screens/rate.dart';
import 'core/screens/search.dart';
import 'core/screens/settings.dart';
import 'core/themes.dart';
import 'features/finance/screens/accounts.dart';
import 'features/health/screens/history.dart';
import 'features/schedule/screens/schedule.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load(); // restore saved theme + text size
  runApp(const MomentumApp());
}

class MomentumApp extends StatelessWidget {
  const MomentumApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds the whole app whenever any setting changes.
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;
        final option = settings.themeOption;

        // No choice yet: follow the system light/dark setting.
        // A chosen theme is used for both slots so it always applies.
        final ThemeData lightTheme =
            option == null ? AppTheme.light : AppTheme.byOption(option);
        final ThemeData darkTheme =
            option == null ? AppTheme.dark : AppTheme.byOption(option);

        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: option == null ? ThemeMode.system : ThemeMode.light,
          // Wraps the Navigator, so every page, drawer and dialog is scaled.
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final systemScale = mq.textScaler.scale(14) / 14;
            return MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(systemScale * settings.textScale),
              ),
              child: child!,
            );
          },
          home: const HomeShell(),
        );
      },
    );
  }
}

class _Destination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;

  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
  });
}

class _DrawerItem {
  final String label;
  final IconData icon;
  final Widget screen;

  const _DrawerItem(this.label, this.icon, this.screen);
}

class _DrawerSection {
  final String title;
  final List<_DrawerItem> items;

  const _DrawerSection(this.title, this.items);
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final PageController _pageController = PageController();
  bool _animating = false; // true while a tap-triggered page animation runs

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  static const _destinations = <_Destination>[
    _Destination(
      label: 'Accounts',
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      screen: AccountsScreen(),
    ),
    _Destination(
      label: 'Schedule',
      icon: Icons.calendar_today_outlined,
      selectedIcon: Icons.calendar_today,
      screen: ScheduleScreen(),
    ),
    _Destination(
      label: 'Health',
      icon: Icons.health_and_safety_outlined,
      selectedIcon: Icons.health_and_safety,
      screen: HistoryScreen(),
    ),
  ];

  // Pinned right under the "Momentum" text in the drawer.
  static const _profileItem =
      _DrawerItem('Profile', Icons.person_outline, ProfileScreen());

  static const _sections = <_DrawerSection>[
    _DrawerSection('Preferences', [
      _DrawerItem('Settings', Icons.settings_outlined, SettingsScreen()),
      _DrawerItem('Categories', Icons.category_outlined, CategoriesScreen()),
    ]),
    _DrawerSection('Help & Support', [
      _DrawerItem('FAQ', Icons.help_outline, FaqScreen()),
      _DrawerItem('Rate', Icons.star_outline, RateScreen()),
      _DrawerItem('Feedback', Icons.feedback_outlined, FeedbackScreen()),
    ]),
  ];

  /// Called by the bottom nav and drawer: slides to the chosen page.
  Future<void> _select(int index) async {
    setState(() => _index = index);
    _animating = true;
    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
    _animating = false;
  }

  void _openPage(Widget screen) {
    Navigator.of(context).pop(); // close drawer
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  /// Plain section title (sits under an inset divider).
  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceLg,
        AppConstants.spaceXs,
        AppConstants.spaceLg,
        AppConstants.spaceXs,
      ),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// Gray header at the very top of the drawer with the app name.
  Widget _buildDrawerHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.outlineVariant,
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLg,
        MediaQuery.of(context).padding.top + AppConstants.spaceLg,
        AppConstants.spaceLg,
        AppConstants.spaceMd,
      ),
      child: Text(
        AppConstants.appName,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// Compact drawer button (tight vertical spacing).
  Widget _buildTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      minVerticalPadding: 0,
      leading: Icon(icon),
      title: Text(label),
      selected: selected,
      onTap: onTap,
    );
  }

  Widget _buildVersionFooter(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(AppConstants.spaceMd),
      padding: const EdgeInsets.symmetric(
        vertical: AppConstants.spaceSm + 4,
        horizontal: AppConstants.spaceMd,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      ),
      child: Text(
        '${AppConstants.appName} V: ${AppConstants.appVersion}',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        // 3-line button: opens the drawer
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Open menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        titleSpacing: 0,
        title: Text(
          AppConstants.appName,
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildDrawerHeader(context),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    const SizedBox(height: 10),
                    // Profile: first item, right below the Momentum text
                    _buildTile(
                      icon: _profileItem.icon,
                      label: _profileItem.label,
                      onTap: () => _openPage(_profileItem.screen),
                    ),
                    const Divider(
                      height: AppConstants.spaceMd,
                      indent: AppConstants.spaceLg,
                      endIndent: AppConstants.spaceLg,
                    ),
                    _buildSectionHeader(context, 'Pages'),
                    for (var i = 0; i < _destinations.length; i++)
                      _buildTile(
                        icon: i == _index
                            ? _destinations[i].selectedIcon
                            : _destinations[i].icon,
                        label: _destinations[i].label,
                        selected: i == _index,
                        onTap: () {
                          _select(i);
                          Navigator.of(context).pop(); // close drawer
                        },
                      ),
                    for (final section in _sections) ...[
                      const Divider(
                        height: AppConstants.spaceMd,
                        indent: AppConstants.spaceLg,
                        endIndent: AppConstants.spaceLg,
                      ),
                      _buildSectionHeader(context, section.title),
                      for (final item in section.items)
                        _buildTile(
                          icon: item.icon,
                          label: item.label,
                          onTap: () => _openPage(item.screen),
                        ),
                    ],
                    const SizedBox(height: AppConstants.spaceMd),
                  ],
                ),
              ),
              _buildVersionFooter(context),
            ],
          ),
        ),
      ),
      // Swipe between pages in the same order as the bottom nav.
      // No looping: the first and last pages can't be swiped past.
      body: PageView(
        controller: _pageController,
        physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
        onPageChanged: (i) {
          if (!_animating) setState(() => _index = i);
        },
        children: [
          for (final d in _destinations) _KeepAlive(child: d.screen),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

/// Keeps a page's state alive while it is off-screen in the PageView.
class _KeepAlive extends StatefulWidget {
  final Widget child;

  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}