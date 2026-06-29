import 'package:flutter/material.dart';
import '../main.dart' show themeModeNotifier, setDarkMode;
import '../currency.dart';
import '../database/database_helper.dart';
import 'trash_bin_page.dart';

/// Settings page — appearance, currency, notifications, etc.
/// Extend this file to add real preferences backed by the `settings` table
/// already present in [DatabaseHelper].
class SettingsPage extends StatefulWidget {
  /// Called after "Clear All Data" wipes the database so the home page can
  /// refresh its cached state immediately.
  final VoidCallback? onDataCleared;

  /// Called after the user leaves the Trash Bin page so the home page can
  /// refresh accounts (e.g. a restored account should reappear).
  final VoidCallback? onAccountRestored;

  const SettingsPage({
    super.key,
    this.onDataCleared,
    this.onAccountRestored,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;
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

  static const _currencyLabels = {
    'PHP': 'PHP (₱)',
    'USD': 'USD (\$)',
    'EUR': 'EUR (€)',
    'JPY': 'JPY (¥)',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Appearance ────────────────────────────────────────────────────
          _Section(label: 'Appearance'),
          Card(
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: themeModeNotifier,
              builder: (context, mode, _) {
                return SwitchListTile(
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Dark Mode'),
                  subtitle: const Text('Switch to a darker theme'),
                  value: mode == ThemeMode.dark,
                  onChanged: (v) => setDarkMode(v),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // ── Localisation ──────────────────────────────────────────────────
          _Section(label: 'Localisation'),
          Card(
            child: ValueListenableBuilder<String>(
              valueListenable: currencyCodeNotifier,
              builder: (context, code, _) {
                return ListTile(
                  leading: const Icon(Icons.attach_money_outlined),
                  title: const Text('Currency'),
                  trailing: DropdownButton<String>(
                    value: code,
                    underline: const SizedBox.shrink(),
                    items: _currencyLabels.entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setCurrency(v);
                    },
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // ── Notifications ─────────────────────────────────────────────────
          _Section(label: 'Notifications'),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Enable Notifications'),
              subtitle: const Text('Budget alerts and reminders'),
              value: _notificationsEnabled,
              onChanged: (v) => setState(() => _notificationsEnabled = v),
            ),
          ),

          const SizedBox(height: 16),

          // ── Storage ───────────────────────────────────────────────────────
          _Section(label: 'Storage'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: const Text('Database'),
                  subtitle: const Text('SQLite — stored on device'),
                  trailing:
                      Icon(Icons.check_circle, color: Colors.green.shade600),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.upload_outlined),
                  title: const Text('Export Data'),
                  subtitle: const Text('Save a backup of your data'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Export coming soon.')),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Import Data'),
                  subtitle: const Text('Restore from a backup'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Import coming soon.')),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.delete_outline, color: Colors.red),
                      if (_trashCount > 0)
                        Positioned(
                          top: -4,
                          right: -6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _trashCount > 99 ? '99+' : '$_trashCount',
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
                  title: const Text('Trash Bin',
                      style: TextStyle(color: Colors.red)),
                  subtitle: const Text('View and restore deleted items'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.red),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TrashBinPage()),
                    ).then((_) {
                      _loadTrashCount();
                      widget.onAccountRestored?.call();
                    });
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined,
                      color: Colors.red),
                  title: const Text('Clear All Data',
                      style: TextStyle(color: Colors.red)),
                  subtitle: const Text('Permanently delete everything'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.red),
                  onTap: () => _showClearDataDialog(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              'Wallet App v1.0.0',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showClearDataDialog(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
          'This will permanently delete all accounts, transactions, and trash. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
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
              widget.onDataCleared?.call();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  const _Section({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
