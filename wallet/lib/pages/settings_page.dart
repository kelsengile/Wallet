import 'package:flutter/material.dart';
import '../main.dart' show themeModeNotifier, setDarkMode;

/// Settings page — appearance, currency, notifications, etc.
/// Extend this file to add real preferences backed by the `settings` table
/// already present in [DatabaseHelper].
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;
  String _currency = 'PHP (₱)';

  static const _currencies = ['PHP (₱)', 'USD (\$)', 'EUR (€)', 'JPY (¥)'];

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
            child: ListTile(
              leading: const Icon(Icons.attach_money_outlined),
              title: const Text('Currency'),
              trailing: DropdownButton<String>(
                value: _currency,
                underline: const SizedBox.shrink(),
                items: _currencies
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _currency = v);
                },
              ),
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
