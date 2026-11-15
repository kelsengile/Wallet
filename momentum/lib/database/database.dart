import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/failures.dart';
import '../core/screens/trash.dart';
import '../core/themes.dart';
import '../core/screens/settings.dart';
import 'helper.dart';

class DatabaseScreen extends StatefulWidget {
  const DatabaseScreen({super.key});

  @override
  State<DatabaseScreen> createState() => _DatabaseScreenState();
}

class _DatabaseScreenState extends State<DatabaseScreen> {
  final _db = DatabaseHelper.instance;
  late Future<DatabaseStats> _stats;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _stats = _db.getStats();
    _db.changes.addListener(_reload);
  }

  @override
  void dispose() {
    _db.changes.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _stats = _db.getStats());
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _messageOf(Object error) =>
      error is Failure ? error.message : 'Something went wrong.';

  /// Runs an action while showing the progress bar, and reports problems.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _say(_messageOf(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- Actions ----------

  String _backupFileName() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'momentum_backup_${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
  }

  Future<void> _export() {
    return _run(() async {
      final json = await _db.exportToJson();
      final bytes = Uint8List.fromList(utf8.encode(json));
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Export data',
        fileName: _backupFileName(),
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      if (saved != null) _say('Data exported.');
    });
  }

  Future<void> _import() async {
    final ok = await _confirm(
      title: 'Import data',
      message: 'This replaces ALL current data with the data in the file '
          'you choose. Export first if you want to keep what you have now.',
      confirmLabel: 'Choose file',
    );
    if (!ok) return;

    await _run(() async {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'Import data',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return; // cancelled

      final bytes = picked.files.single.bytes;
      if (bytes == null) {
        _say('Couldn\'t read that file.');
        return;
      }

      final String text;
      try {
        text = utf8.decode(bytes);
      } catch (_) {
        _say('That file is not a valid Momentum backup.');
        return;
      }

      await _db.importFromJson(text);
      await AppSettings.instance.load();
      _say('Data imported.');
    });
  }

  Future<void> _reset() async {
    final ok = await _confirm(
      title: 'Clear all data',
      message: 'This permanently deletes every account, transaction and '
          'category (including the trash) and resets the database to its '
          'original configuration and puts all colors and themes back to '
          'default. This can\'t be undone.',
      confirmLabel: 'Clear & reset',
    );
    if (!ok) return;

    await _run(() async {
      await _db.resetDatabase();
      await AppSettings.instance.load();
      _say('Database reset to its original configuration.');
    });
  }

  /// Pop-up in the same accent design as the Settings pop-ups.
  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: AppConstants.popupBarrier,
      builder: (context) {
        final base = Theme.of(context);
        final accent = AppTheme.accentOf(context);
        final fg = accent.foreground;
        final bg = accent.background;
        return Theme(
          data: base.copyWith(
            colorScheme: base.colorScheme.copyWith(
              primary: fg,
              onPrimary: bg,
              onSurface: fg,
              onSurfaceVariant:
                  fg.withValues(alpha: AppConstants.mutedAlpha),
            ),
          ),
          child: AlertDialog(
            backgroundColor: bg,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.popupRadius),
            ),
            insetPadding: AppConstants.popupInsetPadding,
            titlePadding: AppConstants.popupTitlePadding,
            contentPadding: AppConstants.popupContentPadding,
            actionsPadding: AppConstants.popupActionsPadding,
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        );
      },
    );
    return result ?? false;
  }

  // ---------- Screen ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storage_outlined),
            SizedBox(width: AppConstants.spaceSm),
            Text('Database'),
          ],
        ),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(AppConstants.progressBarHeight),
                child: LinearProgressIndicator(
                  minHeight: AppConstants.progressBarHeight,
                ),
              )
            : null,
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: FutureBuilder<DatabaseStats>(
          future: _stats,
          builder: (context, snapshot) {
            final stats = snapshot.data ?? DatabaseStats.empty;
            final trashText = stats.trashed == 0
                ? 'Empty'
                : '${stats.trashed} ${stats.trashed == 1 ? 'item' : 'items'}';

            return ListView(
              padding: const EdgeInsets.only(bottom: AppConstants.spaceLg),
children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spaceMd,
                    vertical: AppConstants.spaceMd,
                  ),
                  child: Builder(
                    builder: (context) {
                      final theme = Theme.of(context);
                      final fg = AppTheme.accentOf(context).foreground;
                      final muted = fg.withValues(
                        alpha: AppConstants.mutedAlpha,
                      );
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.storage_outlined, size: 32, color: fg),
                          const SizedBox(height: AppConstants.spaceSm),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'SQLite Database',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: fg,
                                ),
                              ),
                              const SizedBox(width: AppConstants.spaceSm),
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 20,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Stored on this device',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: muted,
                            ),
                          ),
                          const SizedBox(height: AppConstants.spaceMd),
                          Text(
                            '${stats.accounts} accounts | '
                            '${stats.transactions} transactions | '
                            '${stats.reminders} reminders | '
                            '${stats.categories} categories',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppConstants.spaceSm),
                const _SectionHeader('Trash'),
                _SettingGroup(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: const Text('Trash bin'),
                      subtitle: Text(trashText),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TrashScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spaceSm),
                const _SectionHeader('Backup'),
                _SettingGroup(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.upload_file_outlined),
                      title: const Text('Export data'),
                      subtitle: const Text('Save all your data to a file'),
                      onTap: _export,
                    ),
                    ListTile(
                      leading: const Icon(Icons.download_outlined),
                      title: const Text('Import data'),
                      subtitle: const Text('Replace your data with a file'),
                      onTap: _import,
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spaceSm),
                const _SectionHeader('Danger Zone'),
                _SettingGroup(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.restart_alt),
                      title: const Text('Clear all data & reset'),
                      subtitle: const Text(
                        'Back to the original configuration',
                      ),
                      onTap: _reset,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One big rounded rectangle in the accent color, like the Settings screen.
class _SettingGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final divider = Color.lerp(
      accent.background,
      accent.foreground,
      AppConstants.dividerBlend,
    )!;

    final groupTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        onSurface: accent.foreground,
        onSurfaceVariant:
            accent.foreground.withValues(alpha: AppConstants.mutedAlpha),
      ),
      listTileTheme: theme.listTileTheme.copyWith(
        iconColor: accent.foreground,
        textColor: accent.foreground,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMd,
        vertical: AppConstants.spaceXs,
      ),
      child: Theme(
        data: groupTheme,
        child: Material(
          color: accent.background,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: AppConstants.spaceMd,
                    endIndent: AppConstants.spaceMd,
                    color: divider,
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMd + AppConstants.spaceXs,
        AppConstants.spaceMd,
        AppConstants.spaceMd,
        AppConstants.spaceSm + AppConstants.spaceXs,
      ),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}