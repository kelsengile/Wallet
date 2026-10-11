import 'package:flutter/material.dart';

import 'core/constants.dart';
import 'core/themes.dart';
import 'features/finance/screens/accounts.dart';
import 'features/health/screens/history.dart';
import 'features/schedule/screens/schedule.dart';

void main() {
  runApp(const MomentumApp());
}

class MomentumApp extends StatelessWidget {
  const MomentumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const HomeShell(),
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

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = <_Destination>[
    _Destination(
      label: 'Accounts',
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      screen: AccountsScreen(),
    ),
    _Destination(
      label: 'History',
      icon: Icons.history_outlined,
      selectedIcon: Icons.history,
      screen: HistoryScreen(),
    ),
    _Destination(
      label: 'Schedule',
      icon: Icons.calendar_today_outlined,
      selectedIcon: Icons.calendar_today,
      screen: ScheduleScreen(),
    ),
  ];

  void _select(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
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
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () {
              // TODO: implement search
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppConstants.spaceLg,
                  AppConstants.spaceLg,
                  AppConstants.spaceLg,
                  AppConstants.spaceMd,
                ),
                child: Text(
                  AppConstants.appName,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
              ),
              for (var i = 0; i < _destinations.length; i++)
                ListTile(
                  leading: Icon(
                    i == _index ? _destinations[i].selectedIcon : _destinations[i].icon,
                  ),
                  title: Text(_destinations[i].label),
                  selected: i == _index,
                  onTap: () {
                    _select(i);
                    Navigator.of(context).pop(); // close drawer
                  },
                ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: [for (final d in _destinations) d.screen],
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