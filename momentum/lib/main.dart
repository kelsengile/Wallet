import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; // ScrollDirection
import 'package:flutter/services.dart';

import 'core/constants.dart';
import 'core/font.dart';
import 'core/screens/about.dart';
import 'core/screens/calculator.dart';
import 'core/screens/categories.dart';
import 'core/screens/converter.dart';
import 'core/screens/faq.dart';
import 'core/screens/feedback.dart';
import 'core/screens/profile.dart';
import 'core/screens/rate.dart';
import 'core/screens/search.dart';
import 'core/screens/settings.dart';
import 'core/themes.dart';
import 'database/database.dart';
import 'database/helper.dart';
import 'features/finance.dart';
import 'features/health.dart';
import 'features/schedule.dart';
import 'services/notification.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock the app to portrait (upright only, no landscape).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  await AppSettings.instance.load(); // restore saved theme, font + text size
  await AppProfile.instance.load();

  // Month-end clean up: removes anything deleted in an earlier month.
  try {
    await DatabaseHelper.instance.purgeExpiredTrash();
  } catch (_) {}

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
        final custom = settings.customColor;

        final ThemeData lightTheme;
        final ThemeData darkTheme;
        if (custom != null) {
          lightTheme = darkTheme = AppTheme.fromColor(
            custom,
            accent: settings.accentColor,
            text: settings.textColor,
          );
        } else if (option != null) {
          lightTheme = darkTheme = AppTheme.byOption(option);
        } else {
          // No choice yet: follow the system light/dark setting.
          lightTheme = AppTheme.light;
          darkTheme = AppTheme.dark;
        }
        final followSystem = custom == null && option == null;

        // Chosen font style, applied on top of whichever theme is active.
        final fontFamily = settings.fontFamily;

        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppFonts.apply(lightTheme, fontFamily),
          darkTheme: AppFonts.apply(darkTheme, fontFamily),
          themeMode: followSystem ? ThemeMode.system : ThemeMode.light,
          // Wraps the Navigator, so every page, drawer and dialog is scaled.
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final systemScale =
                mq.textScaler.scale(AppConstants.baseFontSize) /
                    AppConstants.baseFontSize;
            return TooltipVisibility(
              visible: false,
              child: MediaQuery(
                data: mq.copyWith(
                  textScaler:
                      TextScaler.linear(systemScale * settings.textScale),
                  boldText: settings.boldText || mq.boldText,
                ),
                child: AppLockGate(child: child!),
              ),
            );
          },
          home: const HomeShell(),
        );
      },
    );
  }
}

/// One small button that pops up above the + button.
/// Its label, icon and color all come from Settings > Theme > Specific Color.
class _AddAction {
  final TransactionColorType type;
  const _AddAction(this.type);

  String get label => type.label;
  IconData get icon => type.icon;
}

/// Finance buttons, listed from the + button going UP.
const _financeAddActions = <_AddAction>[
  _AddAction(TransactionColorType.income),
  _AddAction(TransactionColorType.expense),
  _AddAction(TransactionColorType.transfer),
  _AddAction(TransactionColorType.reminder),
];

class _Destination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;

  /// True when the page starts with a colored card behind the top bar
  /// (the bar's icons and text then use the accent's readable color).
  final bool headerCard;

  /// Small buttons shown when the + is pressed on this page.
  /// Empty = the + only turns into an X for now.
  final List<_AddAction> addActions;

  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
    this.headerCard = false,
    this.addActions = const [],
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

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  final PageController _pageController = PageController();
  bool _animating = false; // true while a tap-triggered page animation runs

  // One controller drives the + / X icon and the small buttons.
  late final AnimationController _addController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    reverseDuration: const Duration(milliseconds: 220),
  );

  // + button state. Setting _addOpen plays / reverses the animation, so
  // every `_addOpen = false` elsewhere in this file keeps working.
  bool _addOpenValue = false;
  bool get _addOpen => _addOpenValue;
  set _addOpen(bool value) {
    if (value == _addOpenValue) return;
    _addOpenValue = value;
    if (value) {
      _addController.forward();
    } else {
      _addController.reverse();
    }
  }

  bool _addVisible = true; // false = hidden while scrolling down

  // Where the finger went down, to tell a tap from a swipe.
  Offset? _downPos;

  @override
  void dispose() {
    _addController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  static final _destinations = <_Destination>[
    _Destination(
      label: 'Finance'.tr,
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      screen: FinanceScreen(),
      headerCard: true,
      addActions: _financeAddActions,
    ),
    _Destination(
      label: 'Schedule'.tr,
      icon: Icons.calendar_today_outlined,
      selectedIcon: Icons.calendar_today,
      screen: ScheduleScreen(),
    ),
    _Destination(
      label: 'Health'.tr,
      icon: Icons.health_and_safety_outlined,
      selectedIcon: Icons.health_and_safety,
      screen: HistoryScreen(),
    ),
  ];

  // Shown in its own "Tools" section below Profile / Notifications.
  static final _toolsItem = <_DrawerItem>[
    _DrawerItem('Calculator'.tr, Icons.calculate_outlined, CalculatorScreen()),
    _DrawerItem('Converter'.tr, Icons.compare_arrows_outlined, ConverterScreen()),
  ];

static final _sections = <_DrawerSection>[
  _DrawerSection('Preferences'.tr, [
    _DrawerItem('Settings'.tr, Icons.settings_outlined, SettingsScreen()),
    _DrawerItem('Categories'.tr, Icons.category_outlined, CategoriesScreen()),
    _DrawerItem('Database'.tr, Icons.storage_outlined, DatabaseScreen()),
    _DrawerItem('Notifications'.tr, Icons.notifications_outlined, NotificationScreen()),
  ]),
    _DrawerSection('Help & Support'.tr, [
      _DrawerItem('FAQ'.tr, Icons.help_outline, FaqScreen()),
      _DrawerItem('Rate'.tr, Icons.star_outline, RateScreen()),
      _DrawerItem('Feedback'.tr, Icons.feedback_outlined, FeedbackScreen()),
      _DrawerItem('About'.tr, Icons.info_outline, AboutScreen()),
    ]),
  ];

  /// Called by the bottom nav and drawer: slides to the chosen page.
  Future<void> _select(int index) async {
    setState(() {
      _index = index;
      _addOpen = false;
      _addVisible = true;
    });
    _animating = true;
    await _pageController.animateToPage(
      index,
      duration: AppConstants.pageAnimationDuration,
      curve: Curves.easeInOut,
    );
    _animating = false;
  }

  void _openPage(Widget screen) {
    Navigator.of(context).pop(); // close drawer
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  // ---------- + button ----------

  void _closeAdd() {
    if (_addOpen) setState(() => _addOpen = false);
  }

  /// A swipe on the page retracts the buttons while the page still scrolls.
  void _onPageMove(PointerMoveEvent e) {
    if (!_addOpen || _downPos == null) return;
    if ((e.position - _downPos!).distance > 8) _closeAdd();
  }

  /// A plain tap on the page retracts them too.
  void _onPageUp(PointerUpEvent e) {
    if (_addOpen &&
        _downPos != null &&
        (e.position - _downPos!).distance <= 8) {
      _closeAdd();
    }
    _downPos = null;
  }

  /// 1.0 at the default font size. It follows the font setting only
  /// partly (addButtonFollow), then is multiplied by addButtonScale.
  double _buttonScale(BuildContext context) {
    final fontScale =
        MediaQuery.textScalerOf(context).scale(AppConstants.baseFontSize) /
            AppConstants.baseFontSize;
    return (1 + (fontScale - 1) * AppConstants.addButtonFollow) *
        AppConstants.addButtonScale;
  }

  /// The + is sucked into the middle, then the X grows out of it.
  /// Closing plays the same thing backwards.
  Widget _addIcon(double value, Color color, double size) {
    final showX = value >= 0.5;
    final scale = showX
        ? Curves.easeOut.transform((value - 0.5) / 0.5)
        : 1 - Curves.easeIn.transform(value / 0.5);
    return Transform.scale(
      scale: scale,
      child: Icon(showX ? Icons.close : Icons.add, size: size, color: color),
    );
  }

  /// Closes the small buttons on any scroll or swipe. Hides the + when a
  /// vertical list scrolls down, shows it on scroll up.
  bool _onScroll(UserScrollNotification n) {
    // Any movement (even sideways) puts the + back to idle.
    if (_addOpen && n.direction != ScrollDirection.idle) {
      setState(() => _addOpen = false);
    }
    if (n.metrics.axis != Axis.vertical) return false; // ignore sideways
    if (n.direction == ScrollDirection.reverse && _addVisible) {
      setState(() {
        _addVisible = false;
        _addOpen = false;
      });
    } else if (n.direction == ScrollDirection.forward && !_addVisible) {
      setState(() => _addVisible = true);
    }
    return false;
  }

  /// Opens the Income / Expense / Transfer / Reminder pop-up.
  /// The pop-ups live in features/finance/finance.dart.
  Future<void> _openAddSheet(_AddAction action) =>
      showTransactionSheet(context, action.type);

  /// The small buttons and the + button.
  List<Widget> _addLayer(BuildContext context, _Destination current) {
    final accent = AppTheme.accentOf(context);
    final ringColor = Theme.of(context).scaffoldBackgroundColor;
    final actions = current.addActions;
    final s = _buttonScale(context);

    return [
      Positioned(
        right: AppConstants.spaceMd,
        bottom: AppConstants.spaceMd,
        child: IgnorePointer(
          ignoring: !_addVisible,
          child: AnimatedSlide(
            offset: _addVisible ? Offset.zero : const Offset(0, 2),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: AnimatedOpacity(
              opacity: _addVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: ListenableBuilder(
                // Rebuilds on the animation and on color changes.
                listenable: Listenable.merge([
                  _addController,
                  AppSettings.instance,
                ]),
                builder: (context, _) {
                  final value = _addController.value;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    // Small buttons touch the + button's right edge.
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Reversed so the first action ends up closest to the +.
                      for (var i = actions.length - 1; i >= 0; i--) ...[
                        _smallButton(
                          action: actions[i],
                          // Nearest button starts first, then each next one.
                          t: Interval(
                            i * 0.12,
                            (i * 0.12 + 0.6).clamp(0.0, 1.0),
                            curve: Curves.easeOutBack,
                          ).transform(value),
                          accent: accent,
                          ringColor: ringColor,
                          scale: s,
                        ),
                        SizedBox(height: 10 * s), // space between buttons
                      ],
                      _RingButton(
                        label: _addOpen ? 'Cancel' : 'Add',
                        size: 56 * s,
                        ring: 4 * s,
                        ringColor: ringColor,
                        color: accent.background,
                        onTap: () => setState(() => _addOpen = !_addOpen),
                        child: _addIcon(value, accent.foreground, 28 * s),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// One small transaction button. [t] is its own animation progress
  /// (0 = hidden under the +, 1 = fully out). It slides up, grows and fades in.
  /// [scale] makes the circle and the icon follow the font size.
  Widget _smallButton({
    required _AddAction action,
    required double t,
    required AppAccent accent,
    required Color ringColor,
    required double scale,
  }) {
    return IgnorePointer(
      ignoring: !_addOpen,
      child: Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 28 * scale),
          child: Transform.scale(
            scale: t.clamp(0.0, 1.3),
            alignment: Alignment.bottomRight,
            child: _RingButton(
              label: action.label,
              size: 44 * scale,
              ring: 3 * scale,
              ringColor: ringColor,
              // Dark tint of the chosen transaction color.
              color: Color.alphaBlend(
                AppSettings.instance
                    .transactionColor(action.type)
                    .withValues(alpha: 0.3),
                accent.background,
              ),
              onTap: () {
                _closeAdd();
                _openAddSheet(action);
              },
              child: Icon(
                action.icon,
                size: 22 * scale,
                color: accent.foreground,
              ),
            ),
          ),
        ),
      ),
    );
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
        title.tr,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
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
      title: Text(label.tr),
      selected: selected,
      onTap: onTap,
    );
  }

  /// Top of the drawer: just the app name.
  Widget _buildDrawerHeader(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    return Container(
      width: double.infinity,
      color: accent.background,
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLg,
        MediaQuery.of(context).padding.top + AppConstants.spaceMd,
        AppConstants.spaceLg,
        AppConstants.spaceMd,
      ),
      child: Text(
        AppConstants.appName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: accent.foreground,
        ),
      ),
    );
  }

  /// Version box at the bottom of the drawer (accent color).
  Widget _buildVersionFooter(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(AppConstants.spaceMd),
      padding: const EdgeInsets.symmetric(
        vertical: AppConstants.spaceSmMd,
        horizontal: AppConstants.spaceMd,
      ),
      decoration: BoxDecoration(
        color: accent.background,
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      ),
      child: Text(
        '${'Version'.tr}: ${AppConstants.appVersion}',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: accent.foreground,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final accent = AppTheme.accentOf(context);
    final current = _destinations[_index];

    // The top bar has no background. On pages that start with a
    // card it uses the accent's readable color, otherwise the normal one.
    final barColor =
        current.headerCard ? accent.foreground : theme.colorScheme.onSurface;

    // The nav bar labels read onSurface / onSurfaceVariant from the theme.
    // Re-point those at the accent's readable color for the bar only, so
    // the labels keep the chosen font.
    final navTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        onSurface: accent.foreground,
        onSurfaceVariant:
            accent.foreground.withValues(alpha: AppConstants.mutedAlpha),
      ),
    );

    return Scaffold(
      // Pages draw behind the (transparent) top bar.
      extendBodyBehindAppBar: true,
      // Close the + when the drawer opens.
      onDrawerChanged: (open) {
        if (open) _closeAdd();
      },
      appBar: AppBar(
        // No background, so the page design shows through.
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: barColor,
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
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: barColor,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () {
              _closeAdd();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              );
            },
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
                    const SizedBox(height: AppConstants.drawerTopGap),
                    _buildSectionHeader(context, 'Pages'),
                    for (var i = 0; i < _destinations.length; i++)
                      _buildTile(
                        icon: _destinations[i].icon,
                        label: _destinations[i].label,
                        onTap: () {
                          _select(i);
                          Navigator.of(context).pop();
                        },
                      ),
                    const Divider(
                      height: AppConstants.spaceMd,
                      indent: AppConstants.spaceLg,
                      endIndent: AppConstants.spaceLg,
                    ),
                    _buildSectionHeader(context, 'Tools'),
                    for (final item in _toolsItem)
                      _buildTile(
                        icon: item.icon,
                        label: item.label,
                        onTap: () => _openPage(item.screen),
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
              ProfileDrawerTile(
                onTap: () => _openPage(const ProfileScreen()),
              ),
              _buildVersionFooter(context),
            ],
          ),
        ),
      ),
      // Swipe between pages in the same order as the bottom nav.
      // No looping: the first and last pages can't be swiped past.
      // The + button sits on top of the pages and hides / shows with
      // vertical scrolling.
      body: NotificationListener<UserScrollNotification>(
        onNotification: _onScroll,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The Listener sees every touch on the page without blocking it,
            // so a swipe or tap retracts the small buttons and still works.
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (e) => _downPos = e.position,
              onPointerMove: _onPageMove,
              onPointerUp: _onPageUp,
              child: PageView(
                controller: _pageController,
                physics:
                    const PageScrollPhysics(parent: ClampingScrollPhysics()),
                onPageChanged: (i) {
                  setState(() {
                    _addOpen = false;
                    _addVisible = true;
                    if (!_animating) _index = i;
                  });
                },
                children: [
                  for (final d in _destinations) _KeepAlive(child: d.screen),
                ],
              ),
            ),
            ..._addLayer(context, current),
          ],
        ),
      ),
      bottomNavigationBar: Theme(
        data: navTheme,
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label.tr,
              ),
          ],
        ),
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

/// A round button with a ring around it in the page background color.
class _RingButton extends StatelessWidget {
  final String label;
  final double size;
  final double ring;
  final Color color;
  final Color ringColor;
  final VoidCallback onTap;
  final Widget child;

  const _RingButton({
    required this.label,
    required this.size,
    required this.ring,
    required this.color,
    required this.ringColor,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: ringColor,
        shape: const CircleBorder(),
        child: Padding(
          padding: EdgeInsets.all(ring),
          child: Material(
            color: color,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              splashFactory: NoSplash.splashFactory, // no ripple
              highlightColor: Colors.transparent, // no press glow
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              child: SizedBox(
                width: size,
                height: size,
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}