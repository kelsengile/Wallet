import 'package:flutter/material.dart';
import '../database/database_helper.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  void _confirmClearData(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
          'This will permanently delete all accounts and transactions. Are you sure?',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: CircleAvatar(
            radius: 40,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              Icons.person,
              size: 40,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'My Wallet',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 32),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text('Database'),
                subtitle: const Text('SQLite — stored on device'),
                trailing: Icon(
                  Icons.check_circle,
                  color: Colors.green.shade600,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.delete_forever_outlined,
                  color: Colors.red,
                ),
                title: const Text(
                  'Clear All Data',
                  style: TextStyle(color: Colors.red),
                ),
                subtitle: const Text('Permanently deletes all records'),
                onTap: () => _confirmClearData(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'About',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Wallet App v1.0.0'),
                const Text('Data stored locally using SQLite (sqflite).'),
                const Text('Works fully offline.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
