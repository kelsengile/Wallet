import 'package:flutter/material.dart';

import '../../database/helper.dart';
import '../constants.dart';
import '../failures.dart';
import '../themes.dart';

/// Darker dim behind every pop-up, same as the Settings screen.
const Color _popupBarrier = Color(0xCC000000);

/// Everything that was deleted but not yet removed for good.
/// Each row can be restored or deleted forever; the top bar can empty it.
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final _db = DatabaseHelper.instance;
  late Future<List<TrashItem>> _items;
  bool _busy = false;
  bool _hasItems = false;

  @override
  void initState() {
    super.initState();
    _items = _load();
    _db.changes.addListener(_reload);
  }

  @override
  void dispose() {
    _db.changes.removeListener(_reload);
    super.dispose();
  }

  Future<List<TrashItem>> _load() async {
    final items = await _db.getTrashItems();
    if (mounted) setState(() => _hasItems = items.isNotEmpty);
    return items;
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _items = _load());
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _say(done);
    } catch (error) {
      _say(error is Failure ? error.message : 'Something went wrong.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteForever(TrashItem item) async {
    final extra = item.kind == TrashKind.account
        ? ' Its transactions are deleted too.'
        : '';
    final ok = await _confirm(
      title: 'Delete forever',
      message: '"${item.title}" will be permanently deleted.$extra '
          'This can\'t be undone.',
      confirmLabel: 'Delete',
    );
    if (ok) {
      await _run(() => _db.deleteTrashItemForever(item), 'Deleted forever.');
    }
  }

  Future<void> _emptyTrash() async {
    final ok = await _confirm(
      title: 'Empty trash',
      message: 'Everything in the trash will be permanently deleted. '
          'This can\'t be undone.',
      confirmLabel: 'Empty',
    );
    if (ok) await _run(_db.emptyTrash, 'Trash emptied.');
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: _popupBarrier,
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
              onSurfaceVariant: fg.withValues(alpha: 0.7),
            ),
          ),
          child: AlertDialog(
            backgroundColor: bg,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
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

  String _dateText(DateTime? date) {
    if (date == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Deleted ${date.year}-${two(date.month)}-${two(date.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final divider = Color.lerp(accent.background, accent.foreground, 0.18)!;

    final groupTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        onSurface: accent.foreground,
        onSurfaceVariant: accent.foreground.withValues(alpha: 0.7),
      ),
      listTileTheme: theme.listTileTheme.copyWith(
        iconColor: accent.foreground,
        textColor: accent.foreground,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline),
            SizedBox(width: 8),
            Text('Trash'),
          ],
        ),
        actions: [
          if (_hasItems)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Empty trash',
              onPressed: _busy ? null : _emptyTrash,
            ),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: FutureBuilder<List<TrashItem>>(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Couldn\'t load the trash.'));
          }

          final items = snapshot.data ?? const <TrashItem>[];
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.delete_outline,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: AppConstants.spaceSm),
                  Text(
                    'Trash is empty',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(AppConstants.spaceMd),
            children: [
              Theme(
                data: groupTheme,
                child: Material(
                  color: accent.background,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            thickness: 1,
                            indent: AppConstants.spaceMd,
                            endIndent: AppConstants.spaceMd,
                            color: divider,
                          ),
                        ListTile(
                          leading: Icon(
                            items[i].kind == TrashKind.account
                                ? Icons.account_balance_wallet_outlined
                                : Icons.receipt_long_outlined,
                          ),
                          title: Text(items[i].title),
                          subtitle: Text(
                            [
                              items[i].subtitle,
                              _dateText(items[i].deletedAt),
                            ].where((s) => s.isNotEmpty).join('\n'),
                          ),
                          isThreeLine: items[i].deletedAt != null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.restore_from_trash),
                                tooltip: 'Restore',
                                onPressed: _busy
                                    ? null
                                    : () => _run(
                                          () => _db.restoreTrashItem(items[i]),
                                          'Restored.',
                                        ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_forever_outlined),
                                tooltip: 'Delete forever',
                                onPressed:
                                    _busy ? null : () => _deleteForever(items[i]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}