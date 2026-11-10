import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/gestures.dart';

import '../core/constants.dart';
import '../core/failures.dart';
import '../core/screens/settings.dart';
import '../core/themes.dart';
import '../core/utils.dart';
import '../database/helper.dart';

/// Look of one account: its color, plus either a pattern or a picture
/// for the card. A picture wins over a pattern.
class AccountTheme {
  final int? color; // ARGB
  final String? pattern;
  final String? imagePath;
  const AccountTheme({this.color, this.pattern, this.imagePath});

  static const AccountTheme none = AccountTheme();

  bool get isDefault => color == null && pattern == null && imagePath == null;

  String encode() =>
      jsonEncode({'color': color, 'pattern': pattern, 'image': imagePath});

  factory AccountTheme.decode(String? raw) {
    if (raw == null) return none;
    try {
      final m = jsonDecode(raw) as Map;
      return AccountTheme(
        color: (m['color'] as num?)?.toInt(),
        pattern: m['pattern'] as String?,
        imagePath: m['image'] as String?,
      );
    } catch (_) {
      return none;
    }
  }
}

/// Every account's theme. Saved in the `settings` table (so it is in
/// backups) and reloaded whenever the database changes (for example after
/// an import).
class _AccountThemes extends ChangeNotifier {
  _AccountThemes() {
    DatabaseHelper.instance.changes.addListener(reload);
    reload();
  }

  static const String _prefix = 'accountTheme.';
  Map<int, AccountTheme> _themes = {};
  int _version = 0; // lets a save win over a reload that started earlier

  AccountTheme of(int accountId) => _themes[accountId] ?? AccountTheme.none;

  Future<void> reload() async {
    final started = _version;
    try {
      final all = await DatabaseHelper.instance.getAllSettings();
      if (started != _version) return;
      final next = <int, AccountTheme>{};
      for (final e in all.entries) {
        if (!e.key.startsWith(_prefix)) continue;
        final id = int.tryParse(e.key.substring(_prefix.length));
        if (id != null) next[id] = AccountTheme.decode(e.value);
      }
      _themes = next;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> set(int accountId, AccountTheme theme) async {
    _version++;
    if (theme.isDefault) {
      _themes.remove(accountId);
    } else {
      _themes[accountId] = theme;
    }
    notifyListeners();
    try {
      final db = DatabaseHelper.instance;
      if (theme.isDefault) {
        await db.removeSetting('$_prefix$accountId');
      } else {
        await db.setSetting('$_prefix$accountId', theme.encode());
      }
    } catch (_) {
    } finally {
      _version++;
    }
  }
}

final _accountThemes = _AccountThemes();

/// Background of the list area under an account's header: a bit darker
/// when the panel color is light, a bit lighter when it is dark.
Color _contentTone(Color panel) {
  final light = panel.computeLuminance() > 0.5;
  return Color.alphaBlend(
    (light ? Colors.black : Colors.white).withValues(alpha: light ? 0.10 : 0.12),
    panel,
  );
}

const List<String> _patternNames = [
  'Dots', 'Stripes', 'Grid', 'Waves', 'Diamonds', 'Circles',
];

/// Colors + backdrop of a card, worked out from the account's theme.
class _CardLook {
  final Color bg;
  final Color fg;
  final String? image;
  final String? pattern;
  const _CardLook._(this.bg, this.fg, this.image, this.pattern);

  factory _CardLook.of(BuildContext context, AccountTheme t) {
    final accent = AppTheme.accentOf(context);
    final img = t.imagePath;
    if (img != null && File(img).existsSync()) {
      // Picture: dark scrim, so the text is white.
      return const _CardLook._(Colors.black, Colors.white, null, null)
          ._withImage(img);
    }
    final c = t.color != null ? Color(t.color!) : null;
    return _CardLook._(
      c ?? accent.background,
      c != null ? AppTheme.onColor(c) : accent.foreground,
      null,
      t.pattern,
    );
  }

  _CardLook _withImage(String path) => _CardLook._(bg, fg, path, null);
}

/// Picture / pattern layers that sit behind the card's content.
List<Widget> _cardBackdrop(_CardLook look) => [
      if (look.image != null) ...[
        Positioned.fill(
          child: Image.file(
            File(look.image!),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
        Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
        ),
      ] else if (look.pattern != null)
        Positioned.fill(
          child: CustomPaint(
            painter: _PatternPainter(
              look.pattern!,
              look.fg.withValues(alpha: 0.14),
            ),
          ),
        ),
    ];

class _PatternPainter extends CustomPainter {
  final String pattern;
  final Color color;
  const _PatternPainter(this.pattern, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 306; // pattern scales with the card
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * k;
    final fill = Paint()..color = color;
    final w = size.width, h = size.height;

    switch (pattern) {
      case 'Dots':
        final s = 22 * k;
        for (var y = s / 2; y < h; y += s) {
          for (var x = s / 2; x < w; x += s) {
            canvas.drawCircle(Offset(x, y), 2.5 * k, fill);
          }
        }
      case 'Stripes':
        final s = 20 * k;
        for (var x = -h; x < w; x += s) {
          canvas.drawLine(Offset(x, h), Offset(x + h, 0), line);
        }
      case 'Grid':
        final s = 24 * k;
        for (var x = 0.0; x < w; x += s) {
          canvas.drawLine(Offset(x, 0), Offset(x, h), line);
        }
        for (var y = 0.0; y < h; y += s) {
          canvas.drawLine(Offset(0, y), Offset(w, y), line);
        }
      case 'Waves':
        final s = 22 * k;
        for (var y = s / 2; y < h + s; y += s) {
          final path = Path()..moveTo(0, y);
          for (var x = 0.0; x <= w; x += 4) {
            path.lineTo(x, y + math.sin(x / (18 * k) * math.pi) * 6 * k);
          }
          canvas.drawPath(path, line);
        }
      case 'Diamonds':
        final s = 32 * k;
        for (var y = 0.0; y < h + s; y += s) {
          for (var x = 0.0; x < w + s; x += s) {
            final c = Offset(x, y);
            canvas.drawPath(
              Path()
                ..moveTo(c.dx, c.dy - s / 2)
                ..lineTo(c.dx + s / 2, c.dy)
                ..lineTo(c.dx, c.dy + s / 2)
                ..lineTo(c.dx - s / 2, c.dy)
                ..close(),
              line,
            );
          }
        }
      case 'Circles':
        final s = 24 * k;
        final corner = Offset(w, h);
        final maxR = math.sqrt(w * w + h * h);
        for (var r = s; r < maxR; r += s) {
          canvas.drawCircle(corner, r, line);
        }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter o) =>
      o.pattern != pattern || o.color != color;
}

/// Copies a picked picture into the app's own folder.
Future<String> _storeThemeImage(String source) async {
  final dir = await getApplicationDocumentsDirectory();
  final folder = Directory(p.join(dir.path, 'account_themes'));
  if (!await folder.exists()) await folder.create(recursive: true);
  final target = p.join(
    folder.path,
    '${DateTime.now().microsecondsSinceEpoch}${p.extension(source)}',
  );
  await File(source).copy(target);
  return target;
}

void _deleteThemeImage(String? path) {
  if (path == null) return;
  try {
    File(path).delete();
  } catch (_) {}
}

/// One account as shown on a card.
class _AccountCardData {
  final int id;
  final String name;
  final int typeId;
  final String typeName;
  final String? typeIcon;
  final String category;
  final String? categoryIcon;
  final double balance;
  final String? noteTitle;
  final String? noteBody;

  const _AccountCardData({
    required this.id,
    required this.name,
    required this.typeId,
    required this.typeName,
    required this.typeIcon,
    required this.category,
    required this.categoryIcon,
    required this.balance,
    this.noteTitle,
    this.noteBody,
  });
}

/// Icons an account type can use (same keys as the Categories screen).
const Map<String, IconData> _typeIcons = {
  'wallet': Icons.account_balance_wallet_outlined,
  'cash': Icons.payments_outlined,
  'bank': Icons.account_balance,
  'phone': Icons.smartphone,
  'card': Icons.credit_card,
  'handshake': Icons.handshake_outlined,
  'trending': Icons.trending_up,
  'savings': Icons.savings_outlined,
  'food': Icons.restaurant,
  'car': Icons.directions_car,
  'shopping': Icons.shopping_bag,
  'receipt': Icons.receipt_long,
  'heart': Icons.favorite,
  'movie': Icons.movie,
  'work': Icons.work,
  'swap': Icons.swap_horiz,
  'home': Icons.home,
  'gift': Icons.card_giftcard,
  'pets': Icons.pets,
  'school': Icons.school,
  'fitness': Icons.fitness_center,
  'flight': Icons.flight,
  'family': Icons.family_restroom,
  'business': Icons.business_center,
  'flag': Icons.flag,
  'medical': Icons.medical_services,
  'star': Icons.star,
  'shapes': Icons.category,
  'label': Icons.label_outline,
};

/// Default icon of each seed account type, used when none is saved.
const Map<String, String> _typeIconDefaults = {
  'Cash': 'cash',
  'Bank': 'bank',
  'Digital Bank': 'phone',
  'Credit': 'card',
  'E-Wallet': 'wallet',
  'Investment': 'trending',
  'Assets': 'home',
  'Debt': 'handshake',
  'Business': 'business',
};

IconData _iconForType(String name, String? saved) {
  if (saved != null && _typeIcons.containsKey(saved)) return _typeIcons[saved]!;
  return _typeIcons[_typeIconDefaults[name] ?? 'wallet']!;
}

/// Account category icon: the saved one, or a plain label.
IconData _iconForCategory(String? saved) {
  if (saved != null && _typeIcons.containsKey(saved)) return _typeIcons[saved]!;
  return _typeIcons['label']!;
}

// ------------------------------------------------------------------
// Account card size.
// The values that tune it (card ratio, sample width, how much the card
// and its text follow the font size) are in AppConstants:
//   cardSampleWidth, cardRatio, bigTextScale, baseCardWidth,
//   cardFollow, textFollow.
// Every size inside the card (icon, spacing, corners) is a multiple of
// "u" = card width / cardSampleWidth.
// ------------------------------------------------------------------

double _fontScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(AppConstants.baseFontSize) /
    AppConstants.baseFontSize;

/// Card width: slightly smaller or bigger than the "Big" size.
double _cardWidthFor(BuildContext context) =>
    AppConstants.baseCardWidth *
    (1 +
        (_fontScale(context) - AppConstants.bigTextScale) *
            AppConstants.cardFollow);

/// Text size multiplier inside the card (1.0 at "Big").
double _textFactorFor(BuildContext context) =>
    1 +
    (_fontScale(context) - AppConstants.bigTextScale) * AppConstants.textFollow;

double _cardHeightFor(double width) => width / AppConstants.cardRatio;

/// Empty space left under the lists so the floating + button
/// (56 button + 8 ring, scaled with the font) never covers the last card.
double _addButtonClearanceOf(BuildContext context) =>
    (56 + 8) *
        (1 + (_fontScale(context) - 1) * AppConstants.addButtonFollow) *
        AppConstants.addButtonScale +
    AppConstants.spaceMd * 2;

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {

  AccountsSummary _summary = AccountsSummary.empty;
  List<_AccountCardData> _accounts = const [];
  String? _error;

  // true = amounts are hidden (eye closed), false = amounts are shown.
  bool _hideAmounts = false;

  // false = sideways cards, true = list of rows.
  bool _listView = false;

  // true while the user is dragging account types to reorder them.
  bool _rearranging = false;

  // saved order of the account type ids.
  List<int> _typeOrder = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadOrder();
    // Reload whenever the database reports a change, or the date range
    // kept in Analytics changes.
    DatabaseHelper.instance.changes.addListener(_load);
    _analyticsRange.addListener(_load);
  }

  @override
  void dispose() {
    DatabaseHelper.instance.changes.removeListener(_load);
    _analyticsRange.removeListener(_load);
    super.dispose();
  }

  Future<void> _loadOrder() async {
    try {
      final order = await DatabaseHelper.instance.getTypeOrder();
      if (!mounted) return;
      setState(() => _typeOrder = order);
    } catch (_) {
      // No saved order: the normal (id) order is used.
    }
  }

  Future<void> _saveOrder(List<int> ids) async {
    try {
      await DatabaseHelper.instance.saveTypeOrder(ids);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Couldn\'t save the new order.')),
        );
    }
  }

  /// Active accounts with their type, category and current balance.
  Future<List<_AccountCardData>> _loadAccounts() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('''
      SELECT a.id, a.name, a.type_id, a.note_title, a.note_body,
             t.name AS type_name, t.icon AS type_icon,
             c.name AS category_name, c.icon AS category_icon,
             b.balance AS balance
      FROM accounts a
      JOIN account_types t ON t.id = a.type_id
      JOIN account_categories c ON c.id = a.category_id
      JOIN account_balances b ON b.account_id = a.id
      WHERE a.deleted_at IS NULL
      ORDER BY t.id, a.id
    ''');
    return [
      for (final row in rows)
        _AccountCardData(
          id: (row['id'] as num).toInt(),
          name: row['name'] as String,
          typeId: (row['type_id'] as num).toInt(),
          typeName: row['type_name'] as String,
          typeIcon: row['type_icon'] as String?,
          category: row['category_name'] as String,
          categoryIcon: row['category_icon'] as String?,
          balance:
              (row['balance'] as num).toInt() / AppConstants.centavosPerPeso,
          noteTitle: row['note_title'] as String?,
          noteBody: row['note_body'] as String?,
        ),
    ];
  }

  Future<void> _load() async {
    try {
      final summary = await DatabaseHelper.instance.getAccountsSummary();
      final accounts = await _loadAccounts();

      // Latest transaction date of each account (as the source account
      // or as the receiving side of a transfer).
      final history = await DatabaseHelper.instance.getHistory();
      final lastUsed = <int, DateTime>{};
      void touch(int? id, DateTime date) {
        if (id == null) return;
        final current = lastUsed[id];
        if (current == null || date.isAfter(current)) lastUsed[id] = date;
      }

      for (final e in history) {
        touch(e.accountId, e.date);
        touch(e.toAccountId, e.date);
      }

      // Income / expense of the date range kept in Analytics (this month
      // until a range was picked, same as the Analytics pop-up).
      final range = _analyticsRange.value ??
          _HistoryRange.of(_Period.month, DateTime.now());
      final from = range.from;
      final until = range.until;
      var income = 0.0;
      var expense = 0.0;
      for (final e in history) {
        if (from != null && e.date.isBefore(from)) continue;
        if (until != null && !e.date.isBefore(until)) continue;
        if (e.type == 'income') income += e.amount;
        if (e.type == 'expense') expense += e.amount;
      }
      final rangedSummary = AccountsSummary(
        totalBalance: summary.totalBalance,
        accountCount: summary.accountCount,
        income: income,
        expense: expense,
      );

      // Most recent transaction first. Accounts with no transactions go
      // to the end of their type, in their normal (id) order.
      final sorted = [...accounts]..sort((a, b) {
          final da = lastUsed[a.id];
          final db = lastUsed[b.id];
          if (da != null && db != null) {
            final c = db.compareTo(da);
            if (c != 0) return c;
          } else if (da != null) {
            return -1;
          } else if (db != null) {
            return 1;
          }
          return a.id.compareTo(b.id);
        });

      if (!mounted) return;
      setState(() {
        _summary = rangedSummary;
        _accounts = sorted;
        _error = null;
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _error = f.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = const UnknownFailure().message);
    }
  }

  /// Accounts grouped by account type, in the saved order.
  /// Types that are not in the saved order yet go to the end (by id).
  List<List<_AccountCardData>> get _groups {
    final groups = <int, List<_AccountCardData>>{};
    for (final account in _accounts) {
      groups.putIfAbsent(account.typeId, () => []).add(account);
    }
    final ids = groups.keys.toList();
    final rank = {for (var i = 0; i < _typeOrder.length; i++) _typeOrder[i]: i};
    const last = 1 << 30;
    ids.sort((a, b) {
      final ra = rank[a] ?? last;
      final rb = rank[b] ?? last;
      if (ra != rb) return ra.compareTo(rb);
      return a.compareTo(b);
    });
    return [for (final id in ids) groups[id]!];
  }

  /// Tap. Finishes rearranging, or switches card view <-> list view.
  void _onViewButtonTap() {
    setState(() {
      if (_rearranging) {
        _rearranging = false;
      } else {
        _listView = !_listView;
      }
    });
  }

  /// Long press. Starts rearranging the account types.
  void _onViewButtonLongPress() {
    if (_rearranging) return;
    HapticFeedback.mediumImpact();
    setState(() => _rearranging = true);
  }

  /// Moves one account type to a new place and saves the order.
  void _reorderTypes(
    List<List<_AccountCardData>> groups,
    int oldIndex,
    int newIndex,
  ) {
    if (newIndex == oldIndex) return;
    final ids = [for (final g in groups) g.first.typeId];
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    setState(() => _typeOrder = ids);
    _saveOrder(ids);
  }

  /// Pops the "New Account" sheet up from the bottom.
  Future<void> _addAccount() {
    final accent = AppTheme.accentOf(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: accent.background,
      barrierColor: AppConstants.popupBarrier,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _AddAccountSheet(),
    );
  }

  /// The Rearrange button. Tap = view, long press = reorder types.
  Widget _viewButton() {
    final glyphColor = AppTheme.accentOf(context).foreground;
    final IconData icon;
    final String label;
    if (_rearranging) {
      icon = Icons.check;
      label = 'Done';
    } else if (_listView) {
      icon = Icons.view_agenda_outlined;
      label = 'Card view';
    } else {
      icon = Icons.view_headline;
      label = 'List view';
    }
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: _onViewButtonTap,
        onLongPress: _onViewButtonLongPress,
        radius: 24,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(child: Icon(icon, color: glyphColor)),
        ),
      ),
    );
  }

  /// One bar per account type that can be dragged.
  Widget _rearrangeList(
    BuildContext context,
    List<List<_AccountCardData>> groups,
  ) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceMd + AppConstants.spaceXs,
            AppConstants.spaceSm,
            AppConstants.spaceMd,
            AppConstants.spaceXs,
          ),
        ),
        Expanded(
          child: ReorderableListView(
            padding: EdgeInsets.fromLTRB(
              AppConstants.spaceMd,
              AppConstants.spaceSm,
              AppConstants.spaceMd,
              _addButtonClearanceOf(context),
            ),
            buildDefaultDragHandles: false,
            onReorderItem: (oldIndex, newIndex) =>
                _reorderTypes(groups, oldIndex, newIndex),
            // While dragging: no extra box or shadow, only the bar moves.
            proxyDecorator: (child, index, animation) => Material(
              type: MaterialType.transparency,
              child: child,
            ),
            children: [
              for (var i = 0; i < groups.length; i++)
                Padding(
                  key: ValueKey('type-${groups[i].first.typeId}'),
                  padding: const EdgeInsets.only(bottom: AppConstants.spaceSm),
                  child: Material(
                    color: accent.background,
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spaceSmMd,
                        vertical: AppConstants.spaceSm,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: fg.withValues(
                                alpha: AppConstants.tintAlpha,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusSm,
                              ),
                            ),
                            child: Icon(
                              _iconForType(
                                groups[i].first.typeName,
                                groups[i].first.typeIcon,
                              ),
                              size: 22,
                              color: fg,
                            ),
                          ),
                          const SizedBox(width: AppConstants.spaceSmMd),
                          Expanded(
                            child: Text(
                              groups[i].first.typeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: fg,
                              ),
                            ),
                          ),
                          Text(
                            '${groups[i].length}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: fg.withValues(
                                alpha: AppConstants.mutedAlpha,
                              ),
                            ),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.all(
                                AppConstants.spaceSm,
                              ),
                              child: Icon(
                                Icons.drag_handle,
                                size: 24,
                                color: fg.withValues(
                                  alpha: AppConstants.mutedAlpha,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = _groups;

    // The Glyph color from Settings > Theme > General Color
    // (fonts, icons and buttons).
    final glyphColor = AppTheme.accentOf(context).foreground;

    // Column: the top part stays fixed, only the Expanded part scrolls.
    // Nothing is padded at the top so the card still starts behind the
    // status bar and the transparent app bar.
    return Column(
      children: [
        // ----- Fixed part -----
        TotalBalanceCard(summary: _summary, hidden: _hideAmounts),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(AppConstants.spaceMd),
            child: Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceMd + AppConstants.spaceXs,
            AppConstants.spaceMd,
            AppConstants.spaceSm,
            0,
          ),
          child: Row(
            children: [
              Text(
                'My Accounts',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                color: glyphColor,
                icon: const Icon(Icons.add),
                tooltip: 'Add Account',
                onPressed: _addAccount,
              ),
              // Eye button. Open eye = amounts shown, closed = hidden.
              IconButton(
                color: glyphColor,
                icon: Icon(
                  _hideAmounts
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                tooltip: _hideAmounts ? 'Show amounts' : 'Hide amounts',
                onPressed: () => setState(() => _hideAmounts = !_hideAmounts),
              ),
              // Tap = card / list view, long press = reorder types.
              _viewButton(),
            ],
          ),
        ),
        // ----- Scrolling part: starts right below the My Accounts row -----
        Expanded(
          child: _rearranging
              ? _rearrangeList(context, groups)
              : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // One section per account type.
                    for (final group in groups)
                      _AccountTypeSection(
                        accounts: group,
                        hidden: _hideAmounts,
                        listView: _listView,
                      ),
                    // Room for the floating + button.
                    SizedBox(height: _addButtonClearanceOf(context)),
                  ],
                ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------
// New / Edit Account bottom sheet
// ------------------------------------------------------------------

/// Bottom sheet that opens from the "+" button next to "My Accounts".
/// Pass [account] to edit an existing account instead (no balance field,
/// plus a Delete Account button).
/// Background = accent color, text / icons / outlines = glyph color.
/// Types and categories come from the app's own database lists.
class _AddAccountSheet extends StatefulWidget {
  final _AccountCardData? account; // null = new account, set = edit
  const _AddAccountSheet({this.account});

  @override
  State<_AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<_AddAccountSheet> {
  static const int _noteTitleMax = 30;
  static const int _noteBodyMax = 120;
  static const double _fieldRadius = 4;
  static const double _sidePad = 20;
  static const double _gap = 12; // space between fields
  static const double _fieldVPad = 15; // text field height
  static const double _selectorVPad = 12; // Type / Category height

  // Balance text: normal size, and the smallest it shrinks to.
  static const double _balanceMaxFont = 16;
  static const double _balanceMinFont = 8;

  final _name = TextEditingController();
  final _balance = TextEditingController();
  final _noteTitle = TextEditingController();
  final _noteBody = TextEditingController();

  List<CategoryItem> _types = const [];
  List<CategoryItem> _categories = const [];
  CategoryItem? _type;
  CategoryItem? _category;
  AccountTheme _theme = AccountTheme.none;
  String? _savedImage; // picture the saved theme already has
  bool _saving = false;
  bool _didSave = false;
  String? _error;

  bool get _editing => widget.account != null;

  /// Background / glyph color of this sheet (follows the chosen account color).
  (Color, Color) _colors() {
    final accent = AppTheme.accentOf(context);
    final custom = _theme.color != null;
    final bg = custom ? Color(_theme.color!) : accent.background;
    return (bg, custom ? AppTheme.onColor(bg) : accent.foreground);
  }

  Future<void> _pickType() async {
    final (bg, fg) = _colors();
    final picked = await _pickItem(
      context,
      title: 'Type',
      items: _types,
      selected: _type,
      iconFor: (item) => _iconForType(item.name, item.icon),
      background: bg,
      foreground: fg,
    );
    if (picked != null) setState(() => _type = picked);
  }

  Future<void> _pickCategory() async {
    final (bg, fg) = _colors();
    final picked = await _pickItem(
      context,
      title: 'Category',
      items: _categories,
      selected: _category,
      iconFor: (item) => _iconForCategory(item.icon),
      background: bg,
      foreground: fg,
    );
    if (picked != null) setState(() => _category = picked);
  }

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    if (a != null) {
      _name.text = a.name;
      _noteTitle.text = a.noteTitle ?? '';
      _noteBody.text = a.noteBody ?? '';
      _theme = _accountThemes.of(a.id);
      _savedImage = _theme.imagePath;
    }
    for (final c in [_name, _balance, _noteTitle, _noteBody]) {
      c.addListener(_refresh);
    }
    _loadLists();
  }

  @override
  void dispose() {
    // A picture picked but never saved is not kept.
    if (!_didSave && _theme.imagePath != _savedImage) {
      _deleteThemeImage(_theme.imagePath);
    }
    for (final c in [_name, _balance, _noteTitle, _noteBody]) {
      c.removeListener(_refresh);
      c.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadLists() async {
    try {
      final db = DatabaseHelper.instance;
      final types = await db.getCategoryItems(CategoryGroup.accountType);
      final categories = await db.getCategoryItems(
        CategoryGroup.accountCategory,
      );
      if (!mounted) return;
      setState(() {
        _types = types;
        _categories = categories;
        final a = widget.account;
        if (a != null) {
          for (final t in types) {
            if (t.id == a.typeId) _type = t;
          }
          for (final c in categories) {
            if (c.name == a.category) _category = c;
          }
        }
      });
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  bool get _canSave =>
      !_saving &&
      _name.text.trim().isNotEmpty &&
      _type != null &&
      _category != null;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final a = widget.account;
      final int id;
      if (a != null) {
        await DatabaseHelper.instance.updateAccount(
          id: a.id,
          name: _name.text,
          typeId: _type!.id,
          categoryId: _category!.id,
          noteTitle: _noteTitle.text,
          noteBody: _noteBody.text,
        );
        id = a.id;
      } else {
        id = await DatabaseHelper.instance.addAccount(
          name: _name.text,
          typeId: _type!.id,
          categoryId: _category!.id,
          initialBalance: double.tryParse(_balance.text.trim()) ?? 0,
          noteTitle: _noteTitle.text,
          noteBody: _noteBody.text,
        );
      }
      // The theme is saved together with the account.
      await _accountThemes.set(id, _theme);
      if (_savedImage != null && _savedImage != _theme.imagePath) {
        _deleteThemeImage(_savedImage); // the replaced picture
      }
      _didSave = true;
      if (mounted) Navigator.of(context).pop();
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      if (mounted) setState(() => _error = const UnknownFailure().message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final a = widget.account!;
    final confirmed = await _confirmDeleteAccount(
      context,
      name: a.name,
      icon: _iconForType(a.typeName, a.typeIcon),
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = widget.account!.id;
      final image = _accountThemes.of(id).imagePath;

      await DatabaseHelper.instance.softDeleteAccount(id);

      _accountThemes.set(id, AccountTheme.none);
      _deleteThemeImage(image);

      if (mounted) Navigator.of(context).pop();
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      if (mounted) setState(() => _error = const UnknownFailure().message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

Future<void> _pickTheme() {
  return _showAccountThemeSheet(
    context,
    initial: _theme,
    onChanged: (next) {
      // Delete the replaced picture now, unless it is the one the account
      // already has saved (that one is removed in _save()).
      final old = _theme.imagePath;
      if (old != null && old != next.imagePath && old != _savedImage) {
        _deleteThemeImage(old);
      }
      if (mounted) setState(() => _theme = next);
    },
  );
}

  /// null = nothing chosen yet.
  String? get _themeText {
    if (_theme.imagePath != null) return 'Image';
    if (_theme.pattern != null) return _theme.pattern!;
    if (_theme.color != null) return 'Custom color';
    return null;
  }

  Widget _themeField(Color fg) {
    final text = _themeText;
    return InkWell(
      onTap: _pickTheme,
      borderRadius: BorderRadius.circular(_fieldRadius),
      child: InputDecorator(
        isEmpty: false,
        decoration: _decoration(
          fg,
          // No label above until something is chosen.
          label: text == null ? null : 'Account Theme',
          floating: FloatingLabelBehavior.always,
          icon: Icon(Icons.style_outlined, color: fg),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            text ?? 'Account Theme',
            maxLines: 1,
            style: TextStyle(
              color: text == null
                  ? fg.withValues(alpha: AppConstants.mutedAlpha)
                  : fg,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  /// The biggest font size (down to the minimum) at which the typed
  /// balance still fits inside the field. No limit on how long it can be.
  double _balanceFontSize(double fieldWidth) {
    final text = _balance.text;
    if (text.isEmpty) return _balanceMaxFont;

    // Space left for the text: minus the prefix icon (48) and the padding.
    final available = fieldWidth - 48 - AppConstants.spaceMd * 2;

    var size = _balanceMaxFont;
    while (size > _balanceMinFont) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: TextStyle(fontSize: size)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (painter.width <= available) break;
      size -= 0.5;
    }
    return size;
  }

  /// Outlined box look shared by every field (glyph-colored outline).
  InputDecoration _decoration(
    Color fg, {
    required String? label,
    required Widget icon,
    Widget? suffix,
    FloatingLabelBehavior? floating,
    double vPad = _fieldVPad,
  }) {
    OutlineInputBorder border(double alpha, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(_fieldRadius),
      borderSide: BorderSide(
        color: fg.withValues(alpha: alpha),
        width: width,
      ),
    );
    return InputDecoration(
      isDense: true, // icons no longer force a 48px minimum height
      labelText: label,
      labelStyle: TextStyle(
        color: fg.withValues(alpha: AppConstants.mutedAlpha),
      ),
      floatingLabelStyle: TextStyle(color: fg),
      floatingLabelBehavior: floating,
      prefixIcon: icon,
      suffixIcon: suffix,
      contentPadding: EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMd,
        vertical: vPad,
      ),
      border: border(AppConstants.borderAlpha, 1),
      enabledBorder: border(AppConstants.borderAlpha, 1),
      focusedBorder: border(1, 2),
    );
  }

  /// A tappable box that looks like the other fields (Type / Category).
  Widget _selector({
    required Color fg,
    required String label,
    required CategoryItem? value,
    required IconData Function(CategoryItem) iconFor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(_fieldRadius),
      child: InputDecorator(
        isEmpty: value == null,
        decoration: _decoration(
          fg,
          label: label,
          vPad: _selectorVPad,
          icon: Icon(
            value == null ? Icons.touch_app_outlined : iconFor(value),
            color: fg,
          ),
          suffix: Icon(Icons.expand_more, color: fg),
        ),
        child: Text(
          value?.name ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: fg, fontSize: 16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final custom = _theme.color != null;
    final bg = custom ? Color(_theme.color!) : accent.background;
    final fg = custom ? AppTheme.onColor(bg) : accent.foreground;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: _form(context, fg, bg),
    );
  }

  Widget _form(BuildContext context, Color fg, Color bg) {
    final base = Theme.of(context);
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);

    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          primary: fg,
          onPrimary: bg,
          onSurface: fg,
          onSurfaceVariant: muted,
        ),
        textSelectionTheme: TextSelectionThemeData(cursorColor: fg),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            _sidePad,
            AppConstants.spaceSmMd,
            _sidePad,
            AppConstants.spaceMd,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: AppConstants.borderAlpha),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceSmMd),

              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: AppConstants.tintAlpha),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet_outlined,
                      color: fg,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceMd),
                  Text(
                    _editing ? 'Edit Account' : 'New Account',
                    style: base.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceMd),

              // Account name (theme sits beside it when editing)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: TextField(
                      controller: _name,
                      style: TextStyle(color: fg, fontSize: 16),
                      cursorColor: fg,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration(
                        fg,
                        label: 'Account Name',
                        icon: Icon(Icons.label_outline, color: fg),
                      ),
                    ),
                  ),
                  if (_editing) ...[
                    const SizedBox(width: _gap),
                    Expanded(flex: 4, child: _themeField(fg)),
                  ],
                ],
              ),
              const SizedBox(height: _gap),

              // Initial balance + theme beside it (new accounts only)
              if (!_editing) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final size = _balanceFontSize(constraints.maxWidth);
                          return TextField(
                            controller: _balance,
                            style: TextStyle(color: fg, fontSize: size),
                            cursorColor: fg,
                            maxLines: 1,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d{0,2}'),
                              ),
                            ],
                            decoration: _decoration(
                              fg,
                              label:
                                  'Initial Balance (${AppConstants.currencySymbol})',
                              icon: Icon(Icons.payments_outlined, color: fg),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: _gap),
                    Expanded(flex: 4, child: _themeField(fg)),
                  ],
                ),
                const SizedBox(height: _gap),
              ],

              // Type + Category side by side
              Row(
                children: [
                  Expanded(
                    child: _selector(
                      fg: fg,
                      label: 'Type',
                      value: _type,
                      iconFor: (item) => _iconForType(item.name, item.icon),
                      onTap: _pickType,
                    ),
                  ),
                  const SizedBox(width: _gap),
                  Expanded(
                    child: _selector(
                      fg: fg,
                      label: 'Category',
                      value: _category,
                      iconFor: (item) => _iconForCategory(item.icon),
                      onTap: _pickCategory,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: _gap),

              // Note: a short title (30) and a longer body (120)
              Container(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spaceMd,
                  AppConstants.spaceXs,
                  AppConstants.spaceMd,
                  AppConstants.spaceXs,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_fieldRadius),
                  border: Border.all(
                    color: fg.withValues(alpha: AppConstants.borderAlpha),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.notes, color: fg),
                        const SizedBox(width: AppConstants.spaceMd),
                        Expanded(
                          child: TextField(
                            controller: _noteTitle,
                            maxLength: _noteTitleMax,
                            style: TextStyle(color: fg, fontSize: 16),
                            cursorColor: fg,
                            decoration: InputDecoration(
                              hintText: 'Note',
                              hintStyle: TextStyle(color: muted),
                              counterText: '',
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: AppConstants.spaceSm,
                              ),
                            ),
                          ),
                        ),
                        Text(
                          '${_noteTitle.text.length} / $_noteTitleMax',
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                      ],
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: fg.withValues(alpha: AppConstants.dividerAlpha),
                    ),
                    TextField(
                      controller: _noteBody,
                      maxLength: _noteBodyMax,
                      minLines: 2,
                      maxLines: 2,
                      style: TextStyle(color: fg, fontSize: 16),
                      cursorColor: fg,
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: AppConstants.spaceSm,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${_noteBody.text.length} / $_noteBodyMax',
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: AppConstants.spaceSm),
                Text(
                  _error!,
                  style: base.textTheme.bodySmall?.copyWith(color: fg),
                ),
              ],
              const SizedBox(height: AppConstants.spaceMd),

              // Add / Save button (greyed out until name, type and
              // category are set)
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _canSave ? _save : null,
                  icon: Icon(_editing ? Icons.save : Icons.add),
                  label: Text(_editing ? 'Save Changes' : 'Add Account'),
                ),
              ),
              if (_editing) ...[
                const SizedBox(height: AppConstants.spaceSm),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red, width: 1.5),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete Account'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Delete-account confirm pop-up. Same size and shape as the date pop-up.
/// Red top with a trash icon, accent-colored body, account chip, message,
/// Cancel (outlined) and Delete (red) buttons.
Future<bool> _confirmDeleteAccount(
  BuildContext context, {
  required String name,
  required IconData icon,
  String message =
      'All transactions linked to this account will be permanently '
      'removed. This action cannot be undone.',
}) async {
  final accent = AppTheme.accentOf(context);
  final fg = accent.foreground;
  final bg = accent.background;
  final red = Colors.red.shade600;

  final ok = await showDialog<bool>(
    context: context,
    barrierColor: AppConstants.popupBarrier,
    builder: (ctx) => Dialog(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ----- Red top -----
            Container(
              color: red,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
              child: Column(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                    child: const Icon(
                      Icons.delete_forever,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceMd),
                  const Text(
                    'Delete Account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            // ----- Body -----
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(
                children: [
                  // Account chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: red.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 20, color: red),
                        const SizedBox(width: AppConstants.spaceSm),
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceMd),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: fg.withValues(alpha: AppConstants.mutedAlpha),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceLg),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: const StadiumBorder(),
                            foregroundColor: fg,
                            side: BorderSide(color: fg.withValues(alpha: 0.5)),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: _sheetGap),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: const StadiumBorder(),
                            backgroundColor: red,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => Navigator.of(ctx).pop(true),
                          icon: const Icon(Icons.delete, size: 20),
                          label: const Text(
                            'Delete',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}

/// Account Theme pop-up: Account Color + Card Theme (pattern / camera /
/// gallery). Pops the chosen [AccountTheme] on Apply.
Future<void> _showAccountThemeSheet(
  BuildContext context, {
  required AccountTheme initial,
  required ValueChanged<AccountTheme> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent, // the sheet paints its own color
    barrierColor: AppConstants.popupBarrier,
    builder: (_) => _AccountThemeSheet(initial: initial, onChanged: onChanged),
  );
}

/// Account Theme bottom sheet: Account Color + Card Theme (pattern / camera /
/// gallery). Every change is sent to [onChanged] right away; the account
/// popup's Save button is what keeps it.
class _AccountThemeSheet extends StatefulWidget {
  final AccountTheme initial;
  final ValueChanged<AccountTheme> onChanged;
  const _AccountThemeSheet({required this.initial, required this.onChanged});

  @override
  State<_AccountThemeSheet> createState() => _AccountThemeSheetState();
}

class _AccountThemeSheetState extends State<_AccountThemeSheet> {
  late int? _color = widget.initial.color;
  late String? _pattern = widget.initial.pattern;
  late String? _image = widget.initial.imagePath;
  String? _error;

  void _emit() => widget.onChanged(
        AccountTheme(color: _color, pattern: _pattern, imagePath: _image),
      );

  /// Same colors as the account popup behind this sheet.
  (Color, Color) _colors() {
    final accent = AppTheme.accentOf(context);
    final custom = _color != null;
    final bg = custom ? Color(_color!) : accent.background;
    return (bg, custom ? AppTheme.onColor(bg) : accent.foreground);
  }

  Future<void> _pickColor() async {
    final accent = AppTheme.accentOf(context);
    final picked = await showDialog<Color>(
      context: context,
      barrierColor: AppConstants.popupBarrier,
      builder: (_) => ColorPickerDialog(
        title: 'Account Color',
        icon: Icons.palette_outlined,
        initial: _color != null ? Color(_color!) : accent.background,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _color = picked.toARGB32());
      _emit();
    }
  }

  Future<void> _pickCardTheme() async {
    final (bg, fg) = _colors();
    final choice = await _pickItem(
      context,
      title: 'Card Theme',
      background: bg,
      foreground: fg,
      items: const [
        CategoryItem(0, 'Pattern'),
        CategoryItem(1, 'Camera'),
        CategoryItem(2, 'Gallery'),
        CategoryItem(3, 'None'),
      ],
      iconFor: (item) => switch (item.id) {
        0 => Icons.grid_on,
        1 => Icons.photo_camera_outlined,
        2 => Icons.photo_library_outlined,
        _ => Icons.block,
      },
    );
    if (choice == null || !mounted) return;

    switch (choice.id) {
      case 0:
        final picked = await _pickItem(
          context,
          title: 'Pattern',
          background: bg,
          foreground: fg,
          items: [
            for (var i = 0; i < _patternNames.length; i++)
              CategoryItem(i, _patternNames[i]),
          ],
          iconFor: (_) => Icons.grid_on,
        );
        if (picked == null || !mounted) return;
        setState(() {
          _pattern = _patternNames[picked.id];
          _image = null;
          _error = null;
        });
        _emit();
      case 3:
        setState(() {
          _pattern = null;
          _image = null;
        });
        _emit();
      default:
        try {
          final file = await ImagePicker().pickImage(
            source: choice.id == 1 ? ImageSource.camera : ImageSource.gallery,
            imageQuality: 80,
            maxWidth: 1600,
          );
          if (file == null) return;
          final saved = await _storeThemeImage(file.path);
          if (!mounted) {
            _deleteThemeImage(saved); // sheet closed while picking
            return;
          }
          setState(() {
            _image = saved;
            _pattern = null;
            _error = null;
          });
          _emit();
        } catch (_) {
          if (mounted) setState(() => _error = 'Couldn\'t get that image.');
        }
    }
  }

  String get _cardThemeText {
    if (_image != null) return 'Image';
    if (_pattern != null) return 'Pattern  ·  $_pattern';
    return 'None';
  }

  Widget _row({
    required Color fg,
    required IconData icon,
    required String label,
    required String value,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return Material(
      color: fg.withValues(alpha: AppConstants.tintAlpha),
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceMd,
            vertical: AppConstants.spaceSmMd,
          ),
          child: Row(
            children: [
              Icon(icon, color: fg, size: 22),
              const SizedBox(width: AppConstants.spaceSmMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: fg.withValues(alpha: AppConstants.mutedAlpha),
                      ),
                    ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spaceLg,
          AppConstants.spaceSmMd,
          AppConstants.spaceLg,
          AppConstants.spaceLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: AppConstants.borderAlpha),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
              const SizedBox(height: AppConstants.spaceLg),
              Text(
                'Account Theme',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
              ),
              const SizedBox(height: AppConstants.spaceMd),
            // Account color
            _row(
              fg: fg,
              icon: Icons.palette_outlined,
              label: 'Account Color',
              value: _color == null ? 'Default' : 'Custom',
              onTap: _pickColor,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_color != null)
                    InkResponse(
                      onTap: () {
                        setState(() => _color = null);
                        _emit();
                      },
                      radius: 18,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(Icons.close, size: 18, color: fg),
                      ),
                    ),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _color != null ? Color(_color!) : bg,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: fg.withValues(alpha: AppConstants.borderAlpha),
                        width: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spaceSm),

            // Card theme: pattern / camera / gallery
            _row(
              fg: fg,
              icon: Icons.credit_card,
              label: 'Card Theme',
              value: _cardThemeText,
              onTap: _pickCardTheme,
              trailing: Icon(Icons.chevron_right, color: fg),
            ),

            if (_error != null) ...[
              const SizedBox(height: AppConstants.spaceSm),
              Text(_error!, style: TextStyle(fontSize: 13, color: fg)),
            ],
          ],
        ),
      ),
    );
  }
}


/// Second bottom sheet: a wrap of chips (icon + name) to pick one item.
Future<CategoryItem?> _pickItem(
  BuildContext context, {
  required String title,
  required List<CategoryItem> items,
  required IconData Function(CategoryItem) iconFor,
  CategoryItem? selected,
  Color? background, // new
  Color? foreground, // new
}) {
  final base = Theme.of(context);
  final accent = AppTheme.accentOf(context);
  final fg = foreground ?? accent.foreground;

  return showModalBottomSheet<CategoryItem>(
    context: context,
    backgroundColor: background ?? accent.background,
    // ...everything else stays the same
    barrierColor: AppConstants.popupBarrier,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceLg,
        AppConstants.spaceSmMd,
        AppConstants.spaceLg,
        AppConstants.spaceLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: AppConstants.borderAlpha),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spaceLg),
          Text(
            title,
            style: base.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          const SizedBox(height: AppConstants.spaceMd),
          Wrap(
            spacing: AppConstants.spaceSm,
            runSpacing: AppConstants.spaceSm,
            children: [
              for (final item in items)
                Material(
                  color: fg.withValues(
                    alpha: item.id == selected?.id
                        ? AppConstants.iconTileSelectedAlpha
                        : AppConstants.tintAlpha,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(sheetContext).pop(item),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spaceMd,
                        vertical: AppConstants.spaceSmMd + 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(iconFor(item), size: 15, color: fg),
                          const SizedBox(width: AppConstants.spaceSm),
                          Text(
                            item.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: fg,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// A header (type icon + type name) with either a sideways list of its
/// cards or, in list view, a column of rows.
class _AccountTypeSection extends StatelessWidget {
  final List<_AccountCardData> accounts;
  final bool hidden;
  final bool listView;

  const _AccountTypeSection({
    required this.accounts,
    required this.hidden,
    required this.listView,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final first = accounts.first;

    // The card follows the font size, but only a little.
    final cardWidth = _cardWidthFor(context);
    final cardHeight = _cardHeightFor(cardWidth);

    // The icon box follows the size of the type name text.
    // At the default size (16) this gives a 36 box and a 20 icon.
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final textSize = MediaQuery.textScalerOf(
      context,
    ).scale(titleStyle?.fontSize ?? 16);
    final boxSize = textSize * 2.25;
    final iconSize = textSize * 1.25;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceMd,
            AppConstants.spaceMd,
            AppConstants.spaceMd,
            AppConstants.spaceSmMd,
          ),
          child: Row(
            children: [
              Container(
                width: boxSize,
                height: boxSize,
                decoration: BoxDecoration(
                  color: accent.background,
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Icon(
                  _iconForType(first.typeName, first.typeIcon),
                  size: iconSize,
                  color: accent.foreground,
                ),
              ),
              const SizedBox(width: AppConstants.spaceSmMd),
              Text(first.typeName, style: titleStyle),
            ],
          ),
        ),
        if (listView)
          // List view, one row per account.
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spaceMd,
            ),
            child: Column(
              children: [
                for (final account in accounts)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: AppConstants.spaceSm,
                    ),
                    child: _AccountListTile(account: account, hidden: hidden),
                  ),
              ],
            ),
          )
        else
          SizedBox(
            height: cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceMd,
              ),
              itemCount: accounts.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: AppConstants.spaceSmMd),
              itemBuilder: (context, i) => SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: _FlipAccountCard(
                  account: accounts[i],
                  hidden: hidden,
                  width: cardWidth,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One account as a row (list view). It has everything the front of
/// the card has: category icon, name, balance and category.
/// Long press opens the view-account pop-up.
class _AccountListTile extends StatelessWidget {
  final _AccountCardData account;
  final bool hidden;

  const _AccountListTile({required this.account, required this.hidden});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;

    final balanceStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      color: fg,
    );

    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showAccountView(context, account, hidden: hidden);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMd,
          vertical: AppConstants.spaceSmMd,
        ),
        decoration: BoxDecoration(
          color: accent.background,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: Row(
          children: [
            // Text first (left side)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    account.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: fg.withValues(alpha: AppConstants.mutedAlpha),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Balance shrinks to fit, however long it is.
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: hidden
                          ? TotalBalanceCard._maskedText(
                              context,
                              balanceStyle,
                              prefix: '${AppConstants.currencySymbol} ',
                            )
                          : Text(
                              Utils.formatCurrency(
                                account.balance,
                                symbol: AppConstants.currencyPrefix,
                              ),
                              maxLines: 1,
                              softWrap: false,
                              style: balanceStyle,
                            ),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceXs),
                  // Smaller tag (smaller than the account name)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spaceSm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: AppConstants.tintAlpha),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusLg),
                    ),
                    child: Text(
                      account.category.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppConstants.spaceMd),
            // Category icon on the right side
            Container(
              width: 33,
              height: 33,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: AppConstants.tintAlpha),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Icon(
                _iconForCategory(account.categoryIcon),
                size: 26,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An account card that flips over when tapped (front <-> back).
/// Long press opens the view-account pop-up (unless [allowLongPress] is
/// false, which the pop-up itself uses for its own card).
class _FlipAccountCard extends StatefulWidget {
  final _AccountCardData account;
  final bool hidden;
  final double width;
  final bool allowLongPress;

  const _FlipAccountCard({
    required this.account,
    required this.hidden,
    required this.width,
    this.allowLongPress = true,
  });

  @override
  State<_FlipAccountCard> createState() => _FlipAccountCardState();
}

class _FlipAccountCardState extends State<_FlipAccountCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppConstants.cardFlipDuration,
  );
  bool _showBack = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _flip() {
    if (_showBack) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    _showBack = !_showBack;
  }

  @override
  Widget build(BuildContext context) {
    final textFactor = _textFactorFor(context);

    return ListenableBuilder(
      listenable: Listenable.merge([AppSettings.instance, _accountThemes]),
      builder: (context, _) {
        final look = _CardLook.of(
          context,
          _accountThemes.of(widget.account.id),
        );
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.noScaling),
          child: GestureDetector(
            onTap: _flip,
            onLongPress: widget.allowLongPress
                ? () {
                    HapticFeedback.mediumImpact();
                    _showAccountView(
                      context,
                      widget.account,
                      hidden: widget.hidden,
                    );
                  }
                : null,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final curved = Curves.easeInOut.transform(_controller.value);
                final angle = curved * math.pi;
                final isFront = angle < math.pi / 2;

                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY(angle),
                  child: isFront
                      ? _CardFront(
                          account: widget.account,
                          hidden: widget.hidden,
                          look: look,
                          width: widget.width,
                          textFactor: textFactor,
                        )
                      // The back is turned around so its text isn't mirrored.
                      : Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateY(math.pi),
                          child: _CardBack(
                            account: widget.account,
                            look: look,
                            width: widget.width,
                            textFactor: textFactor,
                          ),
                        ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Front: category icon on the top right, then name, balance and category
/// at the bottom left. Sizes are measured from the sample (u = width / 612).
/// Text sizes use k = u * textFactor, so at the Big font size they match
/// the sample and change only slightly at other sizes.
/// The name and the balance shrink to fit the card, however long they are.
class _CardFront extends StatelessWidget {
  final _AccountCardData account;
  final bool hidden;
  final _CardLook look;
  final double width;
  final double textFactor;

  const _CardFront({
    required this.account,
    required this.hidden,
    required this.look,
    required this.width,
    required this.textFactor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = look.fg;
    final u = width / AppConstants.cardSampleWidth;
    final k = u * textFactor; // text size unit

    final balanceStyle = theme.textTheme.titleLarge?.copyWith(
      fontSize: 52 * k,
      height: 1.1,
      fontWeight: FontWeight.w700,
      color: fg,
    );

    return Container(
      width: width,
      height: _cardHeightFor(width),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: look.bg,
        borderRadius: BorderRadius.circular(40 * u),
      ),
      child: Stack(
        children: [
          ..._cardBackdrop(look),
          // Icon, top right (the account's category icon)
          Positioned(
            top: 29 * u,
            right: 28 * u,
            child: Container(
              width: 62 * u,
              height: 62 * u,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: AppConstants.tintAlpha),
                borderRadius: BorderRadius.circular(16 * u),
              ),
              child: Icon(
                _iconForCategory(account.categoryIcon),
                size: 32 * u,
                color: fg,
              ),
            ),
          ),
          // Name, balance and category, bottom left
          Positioned(
            left: 40 * u,
            right: 40 * u,
            bottom: 39 * u,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    account.name,
                    maxLines: 1,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 26 * k,
                      height: 1.2,
                      fontWeight: FontWeight.w400,
                      color: fg.withValues(alpha: AppConstants.mutedAlpha),
                    ),
                  ),
                ),
                SizedBox(height: 14 * u),
                // Balance: shrinks to fit the card width (no size limit).
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: hidden
                        ? TotalBalanceCard._maskedText(
                            context,
                            balanceStyle,
                            prefix: '${AppConstants.currencySymbol} ',
                          )
                        : Text(
                            Utils.formatCurrency(
                              account.balance,
                              symbol: AppConstants.currencyPrefix,
                            ),
                            maxLines: 1,
                            softWrap: false,
                            style: balanceStyle,
                          ),
                  ),
                ),
                SizedBox(height: 17 * u),
                // Category: only under the balance, as small as its text.
                // It grows with the text instead of having a fixed height.
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 18 * u,
                    vertical: 7 * u,
                  ),
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: AppConstants.tintAlpha),
                    borderRadius: BorderRadius.circular(17 * u),
                  ),
                  child: Text(
                    account.category.toUpperCase(),
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 19 * k,
                      height: 1.0,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.5 * u,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Back: a dark band (the same on every card), a small notes box under it,
/// then a bigger notes area with no box. Sizes are measured from the sample
/// (u = width / 612) and fitted to the real card height. Text changes
/// slightly with the font size like the front.
class _CardBack extends StatelessWidget {
  final _AccountCardData account;
  final _CardLook look;
  final double width;
  final double textFactor;

  const _CardBack({
    required this.account,
    required this.look,
    required this.width,
    required this.textFactor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = look.fg;
    final u = width / AppConstants.cardSampleWidth;
    final k = u * textFactor; // text size unit

    final title = account.noteTitle?.trim() ?? '';
    final body = account.noteBody?.trim() ?? '';

    return Container(
      width: width,
      height: _cardHeightFor(width),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: look.bg,
        borderRadius: BorderRadius.circular(40 * u),
      ),
      child: Stack(
        children: [
          ..._cardBackdrop(look),
          // The black band, the same on every card.
          Positioned(
            top: 58 * u,
            left: 0,
            right: 0,
            height: 70 * u,
            child: Container(
              color: Colors.black.withValues(alpha: AppConstants.cardBandAlpha),
            ),
          ),
          // First notes section: the small one, with a box.
          Positioned(
            top: 160 * u,
            left: 38 * u,
            right: 39 * u,
            height: 53 * u,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20 * u),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: AppConstants.tintAlpha),
                borderRadius: BorderRadius.circular(14 * u),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  title.isEmpty ? 'Notes' : title,
                  maxLines: 1,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 24 * k,
                    height: 1.0,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ),
          ),
          // Second notes section: the bigger one, no box.
          Positioned(
            top: 228 * u,
            left: 58 * u,
            right: 58 * u,
            bottom: 82 * u,
            child: Text(
              body.isEmpty ? 'Notes' : body,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 24 * k,
                height: 1.2,
                fontWeight: FontWeight.w400,
                color: fg.withValues(alpha: AppConstants.mutedAlpha),
              ),
            ),
          ),
          // Type icon, bottom left
          Positioned(
            left: 40 * u,
            bottom: 34 * u,
            child: Icon(
              _iconForType(account.typeName, account.typeIcon),
              size: 34 * u,
              color: fg.withValues(alpha: AppConstants.mutedAlpha),
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel at the top of the Finance page.
/// It draws behind the status bar and the (transparent) app bar.
/// Its margins, radius, balance weight and mask settings are in
/// AppConstants (totalCard*, balanceWeight, balanceFontSize, maskDrop,
/// maskText).
class TotalBalanceCard extends StatelessWidget {
  final AccountsSummary summary;

  /// When true, the balance, income and expense are masked with asterisks.
  final bool hidden;

  const TotalBalanceCard({
    super.key,
    required this.summary,
    this.hidden = false,
  });

  static String _plain(double v) => Utils.formatCurrency(v, symbol: '');

  /// Draws the asterisks vertically centered on the text line.
  /// The `*` glyph normally sits high, so it is shifted down.
  /// [prefix] (for example the peso sign) stays on the normal baseline.
  static Widget _maskedText(
    BuildContext context,
    TextStyle? style, {
    String prefix = '',
  }) {
    final size = style?.fontSize ?? AppConstants.baseFontSize;
    final drop =
        MediaQuery.textScalerOf(context).scale(size) * AppConstants.maskDrop;
    return Text.rich(
      TextSpan(
        children: [
          if (prefix.isNotEmpty) TextSpan(text: prefix),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Transform.translate(
              offset: Offset(0, drop),
              child: Text(AppConstants.maskText, style: style),
            ),
          ),
        ],
      ),
      style: style,
    );
  }

  // Rebuilds the card when a setting (like a transaction color) changes.
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) => _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);

    // Colors picked in Settings > Theme > Specific Color
    final incomeColor = AppSettings.instance.incomeColor;
    final expenseColor = AppSettings.instance.expenseColor;

    // Space taken by the status bar + app bar, so content starts below them.
    final topInset = MediaQuery.viewPaddingOf(context).top + kToolbarHeight;

    final balanceStyle = theme.textTheme.headlineLarge?.copyWith(
      fontSize: AppConstants.balanceFontSize,
      fontWeight: AppConstants.balanceWeight,
      color: fg,
      height: 1.0, // removes the font's extra line spacing
    );
    final incomeStyle = theme.textTheme.labelSmall?.copyWith(
      color: incomeColor,
      fontWeight: FontWeight.w600,
    );
    final expenseStyle = theme.textTheme.labelSmall?.copyWith(
      color: expenseColor,
      fontWeight: FontWeight.w600,
    );

    final card = Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppConstants.totalCardSideMargin,
        topInset + AppConstants.totalCardTopMargin,
        AppConstants.totalCardSideMargin,
        AppConstants.totalCardBottomMargin,
      ),
      decoration: BoxDecoration(
        color: accent.background,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppConstants.totalCardRadius),
        ),
      ),
      child: Column(
        // Shrinks to the content when the ratio is off.
        mainAxisSize: AppConstants.totalCardUseRatio
            ? MainAxisSize.max
            : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // "Total Balance" on the left, account count on the right
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Balance',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
              Text(
                '${summary.accountCount} '
                '${summary.accountCount == 1 ? 'Account' : 'Accounts'}',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.totalCardLabelGap),
          // Big balance (left) and analytics (right) on one row.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Big balance takes the leftover space and shrinks if needed.
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showTransactionHistory(context),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: hidden
                        ? _maskedText(
                            context,
                            balanceStyle,
                            prefix: AppConstants.currencyPrefix,
                          )
                        : Text(
                            Utils.formatCurrency(
                              summary.totalBalance,
                              symbol: AppConstants.currencyPrefix,
                            ),
                            maxLines: 1,
                            softWrap: false,
                            style: balanceStyle,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spaceSm),
              // Analytics: income | expense (right side), colors come from
              // Settings > Theme > Specific Color.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showAnalytics(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_upward,
                      size: 11,
                      color: incomeColor,
                    ),
                    const SizedBox(width: 2),
                    hidden
                        ? _maskedText(context, incomeStyle)
                        : Text(_plain(summary.income), style: incomeStyle),
                    const SizedBox(width: AppConstants.spaceSm),
                    Container(
                      width: 1,
                      height: 12,
                      color: fg.withValues(alpha: AppConstants.separatorAlpha),
                    ),
                    const SizedBox(width: AppConstants.spaceSm),
                    Icon(
                      Icons.arrow_downward,
                      size: 11,
                      color: expenseColor,
                    ),
                    const SizedBox(width: 2),
                    hidden
                        ? _maskedText(context, expenseStyle)
                        : Text(_plain(summary.expense), style: expenseStyle),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return AppConstants.totalCardUseRatio
        ? AspectRatio(aspectRatio: AppConstants.cardRatio, child: card)
        : card;
  }
}

// ------------------------------------------------------------------
// View account pop-up (long press an account card)
// ------------------------------------------------------------------

/// Loads one active account with its current balance (null = gone).
Future<_AccountCardData?> _queryAccount(int id) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.rawQuery('''
    SELECT a.id, a.name, a.type_id, a.note_title, a.note_body,
           t.name AS type_name, t.icon AS type_icon,
           c.name AS category_name, c.icon AS category_icon,
           b.balance AS balance
    FROM accounts a
    JOIN account_types t ON t.id = a.type_id
    JOIN account_categories c ON c.id = a.category_id
    JOIN account_balances b ON b.account_id = a.id
    WHERE a.id = ? AND a.deleted_at IS NULL
  ''', [id]);
  if (rows.isEmpty) return null;
  final row = rows.first;
  return _AccountCardData(
    id: (row['id'] as num).toInt(),
    name: row['name'] as String,
    typeId: (row['type_id'] as num).toInt(),
    typeName: row['type_name'] as String,
    typeIcon: row['type_icon'] as String?,
    category: row['category_name'] as String,
    categoryIcon: row['category_icon'] as String?,
    balance: (row['balance'] as num).toInt() / AppConstants.centavosPerPeso,
    noteTitle: row['note_title'] as String?,
    noteBody: row['note_body'] as String?,
  );
}

/// Receipt data for a transaction (same as the history receipt).
_ReceiptData _entryReceiptData(HistoryEntry e) {
  final s = AppSettings.instance;
  final isTransfer = e.type == 'transfer';
  final color = isTransfer
      ? s.transferColor
      : (e.type == 'income' ? s.incomeColor : s.expenseColor);
  final dateText = '${_fmtLong(e.date)}  •  ${_fmtTime12(e.date)}';
  return _ReceiptData(
    color: color,
    icon: isTransfer ? Icons.arrow_upward : _iconForCategory(e.categoryIcon),
    title: e.title,
    kind: _typeOf(e.type).label,
    rows: isTransfer
        ? [
            ('From', e.accountName, null),
            ('To', e.toAccountName ?? '', null),
            ('Date', dateText, null),
          ]
        : [
            ('Account', e.accountName, null),
            (
              'Category',
              e.categoryName ?? '',
              _iconForCategory(e.categoryIcon),
            ),
            ('Date', dateText, null),
          ],
    note: e.note?.trim(),
    imagePath: e.imagePath,
    totalLabel: 'TOTAL',
    totalText: Utils.formatCurrency(
      e.amount,
      symbol: AppConstants.currencySymbol,
    ),
  );
}

/// A category on the category pop-up. [color] is the colour shown in the
/// pie (saved or automatic). [kind] is 'income' or 'expense'.
class _CategoryRef {
  final int? id;
  final String name;
  final String? icon;
  final Color color;
  final String kind;
  const _CategoryRef(this.id, this.name, this.icon, this.color, this.kind);
}

/// The card floats on top (transparent background, flippable), the
/// transaction list sits at the bottom. Both slide up from the bottom.
Future<void> _showAccountView(
  BuildContext context,
  _AccountCardData account, {
  required bool hidden,
  bool analytics = false,
  _HistoryRange? range,
}) {
  return _openViewSheet(
    context,
    _AccountViewSheet(
      account: account,
      hidden: hidden,
      analytics: analytics,
      range: range,
    ),
  );
}

/// Category pop-up (no card on top). Pass [account] to only show that
/// account's transactions of the category.
Future<void> _showCategoryView(
  BuildContext context, {
  required _CategoryRef category,
  required _HistoryRange range,
  _AccountCardData? account,
  bool hidden = false,
}) {
  return _openViewSheet(
    context,
    _AccountViewSheet(
      account: account,
      category: category,
      hidden: hidden,
      range: range,
    ),
  );
}

Future<void> _openViewSheet(BuildContext context, Widget sheet) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: AppConstants.popupBarrier,
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (_, _, _) => sheet,
    // No default fade: the sheet slides its own two halves.
    transitionBuilder: (context, animation, _, child) => child,
  );
}

class _AccountViewSheet extends StatefulWidget {
  final _AccountCardData? account; // null = category pop-up from main analytics
  final _CategoryRef? category; // set = category pop-up (no card on top)
  final bool hidden;
  final bool analytics;
  final _HistoryRange? range;
  const _AccountViewSheet({
    this.account,
    this.category,
    required this.hidden,
    this.analytics = false,
    this.range,
  });

  @override
  State<_AccountViewSheet> createState() => _AccountViewSheetState();
}

class _AccountViewSheetState extends State<_AccountViewSheet> {
  final _db = DatabaseHelper.instance;
  late _AccountCardData? _account = widget.account;
  // A range handed in (from Analytics) wins. Otherwise the last filter
  // used on this pop-up, otherwise this month.
  late _HistoryRange _range = widget.range ??
      _lastAccountRange ??
      _HistoryRange.of(_Period.month, DateTime.now());
  List<HistoryEntry> _entries = const [];
  List<ReminderItem> _reminders = const [];
  final Set<String> _collapsed = {}; // day headers that are folded
  bool _loaded = false;
  String? _error;

  late bool _analytics = widget.analytics; // false = history, true = analytics
  String? _typeFilter; // history only: income / expense filter
  String _view = 'all'; // analytics only: all | income | expense

  bool get _catMode => widget.category != null;

  /// Panel color: the account's own color, or the app accent.
  Color _bgColor(BuildContext context) {
    final a = _account;
    final t = a == null ? null : _accountThemes.of(a.id).color;
    return t != null ? Color(t) : AppTheme.accentOf(context).background;
  }

  @override
  void initState() {
    super.initState();
    _load();
    // Any edit (transaction or account) refreshes the card and the list.
    _db.changes.addListener(_load);
  }

  /// Income / expense text pressed.
  /// History: filters the list. Analytics: opens only that kind's graphs.
  void _tapStat(String filter) => setState(() {
        if (_analytics) {
          _view = _view == filter ? 'all' : filter;
        } else {
          _typeFilter = _typeFilter == filter ? null : filter;
        }
      });

  /// Account name pressed: back to the full history.
  void _showHistory() => setState(() {
        _analytics = false;
        _typeFilter = null;
        _view = 'all';
      });

  /// Net balance text pressed (once): opens the default analytics.
  void _openAnalytics() => setState(() {
        _analytics = true;
        _view = 'all';
      });

  @override
  void dispose() {
    _db.changes.removeListener(_load);
    super.dispose();
  }

  bool _matches(HistoryEntry e, _AccountCardData? acc) {
    final c = widget.category;
    if (c != null) {
      return e.type != 'transfer' &&
          e.categoryId == c.id &&
          (acc == null || e.accountId == acc.id);
    }
    return e.accountId == acc!.id || e.toAccountId == acc.id;
  }

  Future<void> _load() async {
    try {
      final a = widget.account;
      _AccountCardData? fresh;
      if (a != null) {
        fresh = await _queryAccount(a.id);
        if (!mounted) return;
        if (fresh == null) {
          // The account was deleted: close this pop-up.
          final route = ModalRoute.of(context);
          if (route != null) Navigator.of(context).removeRoute(route);
          return;
        }
      }
      final all = await _db.getHistory(from: _range.from, until: _range.until);
      final reminders = await _db.getReminders();
      if (!mounted) return;
      setState(() {
        _account = fresh;
        _reminders = reminders;
        _entries = [
          for (final e in all)
            if (_matches(e, fresh)) e,
        ];
        _loaded = true;
        _error = null;
      });
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      if (mounted) setState(() => _error = const UnknownFailure().message);
    }
  }

  double get _income => _entries
      .where((e) => e.type == 'income')
      .fold(0.0, (sum, e) => sum + e.amount);
  double get _expense => _entries
      .where((e) => e.type == 'expense')
      .fold(0.0, (sum, e) => sum + e.amount);

  /// Balance change inside the selected date range (category pop-up:
  /// income minus expense).
  double get _rangeBalance {
    final id = _account?.id;
    if (_catMode || id == null) return _income - _expense;
    var total = 0.0;
    for (final e in _entries) {
      if (e.type == 'income' && e.accountId == id) {
        total += e.amount;
      } else if (e.type == 'expense' && e.accountId == id) {
        total -= e.amount;
      } else if (e.type == 'transfer') {
        if (e.accountId == id) total -= e.amount;
        if (e.toAccountId == id) total += e.amount;
      }
    }
    return total;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- Actions ----------

  /// Opens the date picker used by the transaction history.
  Future<void> _pickRange() async {
    final accent = AppTheme.accentOf(context);
    final bg = _bgColor(context);
    final custom = bg != accent.background;
    final fg = custom ? AppTheme.onColor(bg) : accent.foreground;

    final picked = await showDialog<_HistoryRange>(
      context: context,
      barrierColor: AppConstants.popupBarrier,
      builder: (_) => _RangeDialog(
        initial: _range,
        background: bg,
        foreground: fg,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
    if (!_catMode) _lastAccountRange = picked; // remember it
    _load();
  }

  /// Long press on the account name.
  Future<void> _editAccount() {
    HapticFeedback.mediumImpact();
    final accent = AppTheme.accentOf(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: accent.background,
      barrierColor: AppConstants.popupBarrier,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _AddAccountSheet(account: _account),
    );
  }

  void _openEntry(HistoryEntry first) {
    var current = first;
    _showReceipt(
      context,
      _entryReceiptData(first),
      reload: () async {
        final all = await _db.getHistory();
        for (final x in all) {
          if (x.id == first.id) {
            current = x;
            return _entryReceiptData(x);
          }
        }
        return null;
      },
      onEdit: () =>
          showTransactionSheet(context, _typeOf(first.type), entry: current),
    );
  }

  Future<void> _removeEntry(HistoryEntry e) async {
    setState(() {
      _entries = [
        for (final x in _entries)
          if (x.id != e.id) x,
      ];
    });
    try {
      await _db.softDeleteTransaction(e.id);
    } on Failure catch (f) {
      _snack(f.message);
      _load();
    } catch (_) {
      _snack(const UnknownFailure().message);
      _load();
    }
  }

  // ---------- Pieces ----------

  Widget _miniStat(IconData icon, Color color, double value, String filter) {
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: color,
    );
    final selected = !_catMode &&
        (_analytics ? _view == filter : _typeFilter == filter);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _catMode ? null : () => _tapStat(filter),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.18) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 2),
            widget.hidden
                ? TotalBalanceCard._maskedText(context, style)
                : Text(
                    Utils.formatCurrency(
                      value,
                      symbol: AppConstants.currencyPrefix,
                    ),
                    style: style,
                  ),
          ],
        ),
      ),
    );
  }

  Widget _header(Color fg) {
    final theme = Theme.of(context);
    final s = AppSettings.instance;
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    final cat = widget.category;
    final shown = _rangeBalance;
    final balanceColor = shown >= 0 ? s.incomeColor : s.expenseColor;
    final balanceStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w800,
      color: balanceColor,
    );
    final nameStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w800,
      color: fg,
    );

    // The icon box follows the size of the account name text.
    final nameSize = MediaQuery.textScalerOf(
      context,
    ).scale(nameStyle?.fontSize ?? 22);
    final boxSize = nameSize * 2.4;
    final iconSize = nameSize * 1.2;
    final boxColor = cat?.color;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMd,
        AppConstants.spaceMd,
        AppConstants.spaceMd,
        0,
      ),
      child: Row(
        children: [
          Container(
            width: boxSize,
            height: boxSize,
            decoration: BoxDecoration(
              color: boxColor != null
                  ? boxColor.withValues(alpha: 0.25)
                  : fg.withValues(alpha: AppConstants.tintAlpha),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Icon(
              cat != null
                  ? _iconForCategory(cat.icon)
                  : _iconForType(_account!.typeName, _account!.typeIcon),
              size: iconSize,
              color: boxColor ?? fg,
            ),
          ),
          const SizedBox(width: AppConstants.spaceMd),
          // Account pop-up: tap = history, long press = edit account.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _catMode ? null : _showHistory,
              onLongPress: _catMode ? null : _editAccount,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cat?.name ?? _account!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: nameStyle,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          (cat != null ? cat.kind : _account!.typeName)
                              .toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: fg,
                          ),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          cat != null
                              ? '  ·  ${_account?.name ?? 'All accounts'}'
                              : '  ·  ${_account!.category}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spaceSm),
          // Not flexible: it is only as wide as its content (up to half the
          // screen), so it sits flush against the right padding.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.5,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Net balance: press ONCE to open the analytics.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _catMode ? null : _openAnalytics,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: widget.hidden
                        ? TotalBalanceCard._maskedText(
                            context,
                            balanceStyle,
                            prefix: AppConstants.currencyPrefix,
                          )
                        : Text(
                            Utils.formatCurrency(
                              shown,
                              symbol: AppConstants.currencyPrefix,
                            ),
                            maxLines: 1,
                            softWrap: false,
                            textAlign: TextAlign.right,
                            style: balanceStyle,
                          ),
                  ),
                ),
                // The category pop-up only shows the total, no
                // income / expense stats under it.
                if (!_catMode) ...[
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _miniStat(Icons.arrow_upward, s.incomeColor, _income, 'income'),
                        const SizedBox(width: AppConstants.spaceSm),
                        Container(
                          width: 1,
                          height: 12,
                          color: fg.withValues(alpha: AppConstants.separatorAlpha),
                        ),
                        const SizedBox(width: AppConstants.spaceSm),
                        _miniStat(Icons.arrow_downward, s.expenseColor, _expense, 'expense'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "History" / "Analytics" (left) and the selected date (right).
  /// Tap the row to open the history date picker.
  Widget _titleRow(Color fg) {
    final theme = Theme.of(context);
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    return InkWell(
      onTap: _pickRange,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spaceMd,
          AppConstants.spaceSm,
          AppConstants.spaceMd,
          AppConstants.spaceMd,
        ),
        child: Row(
          children: [
            Text(
              (_analytics && !_catMode) ? 'Analytics' : 'History',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
            const SizedBox(width: AppConstants.spaceMd),
            Expanded(
              child: Text(
                _range.label,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bigger month header, shown when the picked dates cover several months.
  Widget _monthHeader(int year, int month, Color fg) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMd,
        AppConstants.spaceLg,
        AppConstants.spaceMd,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _range.multiYear
                ? '${_monthNames[month - 1]} $year'
                : _monthNames[month - 1],
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          const SizedBox(height: AppConstants.spaceXs),
          Divider(height: 1, thickness: 2, color: fg.withValues(alpha: 0.3)),
        ],
      ),
    );
  }

  Widget _dayHeader(DateTime d, String key, Color fg) {
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    final folded = _collapsed.contains(key);
    final year = _range.multiYear ? ', ${d.year}' : '';
    return InkWell(
      onTap: () => setState(() {
        folded ? _collapsed.remove(key) : _collapsed.add(key);
      }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spaceMd,
          AppConstants.spaceSmMd,
          AppConstants.spaceMd,
          0,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_monthNames[d.month - 1].substring(0, 3)} ${d.day}'
                    '$year,  ${_weekdayLong[d.weekday - 1]}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                ),
                Icon(
                  folded ? Icons.chevron_right : Icons.expand_more,
                  size: 20,
                  color: muted,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Divider(
              height: 1,
              thickness: 1,
              color: fg.withValues(alpha: AppConstants.dividerAlpha),
            ),
          ],
        ),
      ),
    );
  }

  /// Same row design as the transaction history.
  Widget _entryRow(HistoryEntry e, Color fg) {
    final s = AppSettings.instance;
    final theme = Theme.of(context);
    final k = _fontScale(context).clamp(0.8, 1.3).toDouble();
    final isTransfer = e.type == 'transfer';
    final color = isTransfer
        ? s.transferColor
        : (e.type == 'income' ? s.incomeColor : s.expenseColor);
    final sign = isTransfer ? '±' : (e.type == 'income' ? '+' : '−');
    final sub = isTransfer
        ? '${e.accountName} → ${e.toAccountName ?? ''}'
        : e.accountName;

    final card = Material(
      color: _contentTone(_bgColor(context)),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openEntry(e),
        child: Padding(
          padding: EdgeInsets.all(AppConstants.spaceSmMd * k),
          child: Row(
            children: [
              Container(
                width: 42 * k,
                height: 42 * k,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isTransfer
                      ? Icons.swap_horiz
                      : _iconForCategory(e.categoryIcon),
                  size: 22 * k,
                  color: color,
                ),
              ),
              const SizedBox(width: AppConstants.spaceSmMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                        color: fg.withValues(alpha: AppConstants.mutedAlpha),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.spaceSm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$sign${Utils.formatCurrency(e.amount, symbol: AppConstants.currencySymbol)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fmtTime12(e.date),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 11,
                      color: fg.withValues(alpha: AppConstants.mutedAlpha),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMd,
        vertical: 2,
      ),
      child: Dismissible(
        key: ValueKey('acc-tx-${e.id}'),
        direction: DismissDirection.endToStart,
        resizeDuration: const Duration(milliseconds: 250),
        onDismissed: (_) => _removeEntry(e),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: AppConstants.spaceLg),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        child: card,
      ),
    );
  }

  List<Widget> _listChildren(Color fg) {
    if (!_loaded) {
      return const [
        Padding(
          padding: EdgeInsets.all(AppConstants.spaceXl),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final visible = _typeFilter == null
        ? _entries
        : [for (final e in _entries) if (e.type == _typeFilter) e];
    if (visible.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(AppConstants.spaceXl),
          child: Center(
            child: Text(
              'No transactions',
              style: TextStyle(
                color: fg.withValues(alpha: AppConstants.mutedAlpha),
              ),
            ),
          ),
        ),
      ];
    }
    final out = <Widget>[];
    int? lastMonth;
    String? lastDay;
    for (final e in visible) {
      final d = e.date;
      if (_range.groupByMonth) {
        final mk = d.year * 100 + d.month;
        if (mk != lastMonth) {
          out.add(_monthHeader(d.year, d.month, fg));
          lastMonth = mk;
          lastDay = null;
        }
      }
      final key = '${d.year}-${d.month}-${d.day}';
      if (key != lastDay) {
        out.add(_dayHeader(d, key, fg));
        lastDay = key;
      }
      if (!_collapsed.contains(key)) out.add(_entryRow(e, fg));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds when a Specific Color changes.
    return ListenableBuilder(
      listenable: Listenable.merge([AppSettings.instance, _accountThemes]),
      builder: (context, _) => _buildSheet(context),
    );
  }

  void _openKind(String kind) => setState(() => _view = kind);

  /// Opens a category pop-up that only shows THIS account's transactions.
  void _openCategory(_CatSlice c) => _showCategoryView(
        context,
        category: _CategoryRef(c.id, c.name, c.icon, c.color, _view),
        account: _account,
        range: _range,
        hidden: widget.hidden,
      );

  List<Widget> _analyticsChildren(Color fg) {
    if (!_loaded) {
      return const [
        Padding(
          padding: EdgeInsets.all(AppConstants.spaceXl),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_view == 'all') {
      final id = _account?.id;
      return [
        _DayLinked(
          builder: (link) => Padding(
            padding: const EdgeInsets.all(AppConstants.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _txCountCard(
                  entries: _entries,
                  reminders: [
                    for (final r in _reminders)
                      if (r.accountId == id) r,
                  ],
                  range: _range,
                  fg: fg,
                  link: link,
                ),
                const SizedBox(height: AppConstants.spaceMd),
                _dualLineCard(_entries, fg, _openKind, link: link),
                const SizedBox(height: AppConstants.spaceMd),
                _dualPieCard(_entries, fg, _openKind),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      _KindCharts(
        entries: _entries,
        kind: _view,
        range: _range,
        fg: fg,
        onOpenCategory: _openCategory,
      ),
    ];
  }

  /// Category pop-up: line graph of the category's transactions, then
  /// the list of them.
  List<Widget> _categoryChildren(Color fg) {
    final cat = widget.category!;
    final s = AppSettings.instance;
    final color = cat.kind == 'income' ? s.incomeColor : s.expenseColor;
    final list = [..._entries]..sort((a, b) => a.date.compareTo(b.date));
    return [
      if (_loaded && list.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceMd,
            AppConstants.spaceMd,
            AppConstants.spaceMd,
            AppConstants.spaceSm,
          ),
          child: _chartCard(
            fg,
            _TxLineChart(series: [_Series(cat.kind, list, color)], fg: fg),
            title: _ChartTitles.category(_account?.name, cat.name),
            dot: color,
          ),
        ),
      ..._listChildren(fg),
    ];
  }

  Widget _buildSheet(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final bg = _bgColor(context);
    final custom = bg != accent.background;
    final fg = custom ? AppTheme.onColor(bg) : accent.foreground;
    final screenW = MediaQuery.sizeOf(context).width;
    final cardW = math.min(_cardWidthFor(context) * 1.25, screenW - 32);
    final cardH = _cardHeightFor(cardW);
    // The category pop-up has no card on top, so the panel is taller.
    final panelH =
        MediaQuery.sizeOf(context).height * (_catMode ? 0.86 : 0.62);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    final route = ModalRoute.of(context)?.animation ??
        const AlwaysStoppedAnimation<double>(1);
    final eased = route.drive(CurveTween(curve: Curves.easeOutCubic));
    final fromTop = eased.drive(
      Tween<Offset>(begin: const Offset(0, -1.5), end: Offset.zero),
    );
    final fromBottom = eased.drive(
      Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero),
    );

    final children = _catMode
        ? _categoryChildren(fg)
        : (_analytics ? _analyticsChildren(fg) : _listChildren(fg));

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        bottom: false,
        child: SizedBox.expand(
          child: Column(
            children: [
              // Card: slides down from the top. Tap outside to close.
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: _catMode
                      ? const SizedBox.expand()
                      : SlideTransition(
                          position: fromTop,
                          child: Center(
                            child: SizedBox(
                              width: cardW,
                              height: cardH,
                              child: _FlipAccountCard(
                                account: _account!,
                                hidden: widget.hidden,
                                width: cardW,
                                allowLongPress: false,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              // Bottom panel: slides up from the bottom.
              SlideTransition(
                position: fromBottom,
                child: Container(
                  height: panelH,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Handle: swipe down to close the pop-up.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragEnd: (d) {
                          if ((d.primaryVelocity ?? 0) > 200) {
                            Navigator.of(context).pop();
                          }
                        },
                        child: SizedBox(
                          height: 28,
                          width: double.infinity,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: fg.withValues(alpha: AppConstants.borderAlpha),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      _header(fg),
                      // Title + selected date, above the separator.
                      _titleRow(fg),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.all(AppConstants.spaceSm),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      // Separator, same as the transaction history popup.
                      Divider(
                        height: 1,
                        thickness: 2,
                        color: fg.withValues(alpha: 0.3),
                      ),
                      Expanded(
                        child: ColoredBox(
                          color: _contentTone(bg),
                          child: ListView(
                            padding: EdgeInsets.only(
                              bottom: bottomInset + AppConstants.spaceMd,
                            ),
                            children: children,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Transaction history pop-up
// ------------------------------------------------------------------

/// Height of the bottom nav bar in main.dart. The history panel stops here.
const double _navBarHeight = 56;

const List<String> _weekdayLong = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  'Sunday',
];

String _fmtLong(DateTime d) =>
    '${_monthNames[d.month - 1].substring(0, 3)} ${d.day}, ${d.year}';

String _fmtTime12(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${_two(d.minute)} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

TransactionColorType _typeOf(String type) {
  switch (type) {
    case 'income':
      return TransactionColorType.income;
    case 'expense':
      return TransactionColorType.expense;
    default:
      return TransactionColorType.transfer;
  }
}

/// The last date filter the user used. Kept while the app is open.
_HistoryRange? _lastHistoryRange;

/// The last date filter used in the account pop-up. Kept while the app is open.
_HistoryRange? _lastAccountRange;

/// Rich, bright version of a color (stays saturated, not pale).
/// Grays are left as grays, so they never turn red.
Color _vivid(Color c) {
  final hsl = HSLColor.fromColor(c);
  if (hsl.saturation < 0.08) {
    return hsl.withLightness(hsl.lightness.clamp(0.6, 0.9).toDouble()).toColor();
  }
  return hsl
      .withSaturation(math.max(hsl.saturation, 0.8))
      .withLightness(hsl.lightness.clamp(0.58, 0.68).toDouble())
      .toColor();
}

/// Darker version of a color (same hue). Used for overdue reminders.
Color _darker(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness * 0.62).clamp(0.0, 1.0)).toColor();
}

/// Lighter version of a color (mixes in white). Used for the cards
/// in the history list so they stand out from the panel behind them.
/// [amount] = how much white: 0.0 = none, 1.0 = pure white.
Color _lighter(Color c, [double amount = 0.08]) =>
    Color.alphaBlend(Colors.white.withValues(alpha: amount), c);

/// True when the color is black or white (or close to it).
bool _isBW(Color c) {
  final l = HSLColor.fromColor(c).lightness;
  return l < 0.1 || l > 0.92;
}

enum _Period { day, week, month, year, all, custom }

/// The dates the history is showing. [end] is inclusive.
class _HistoryRange {
  final _Period period;
  final DateTime start;
  final DateTime end;
  const _HistoryRange(this.period, this.start, this.end);

  factory _HistoryRange.of(_Period p, DateTime a) {
    final d = DateTime(a.year, a.month, a.day);
    switch (p) {
      case _Period.day:
        return _HistoryRange(p, d, d);
      case _Period.week:
        final s = DateTime(d.year, d.month, d.day - (d.weekday - 1));
        return _HistoryRange(p, s, DateTime(s.year, s.month, s.day + 6));
      case _Period.month:
        return _HistoryRange(
          p,
          DateTime(d.year, d.month),
          DateTime(d.year, d.month + 1, 0),
        );
      case _Period.year:
        return _HistoryRange(p, DateTime(d.year), DateTime(d.year, 12, 31));
      case _Period.all:
      case _Period.custom:
        return _HistoryRange(p, d, d);
    }
  }

  bool get isAll => period == _Period.all;

  /// "All" and "Custom" have no arrows.
  bool get canStep => period != _Period.all && period != _Period.custom;

  DateTime? get from => isAll ? null : start;
  DateTime? get until =>
      isAll ? null : DateTime(end.year, end.month, end.day + 1);

  bool get groupByMonth =>
      period == _Period.year ||
      isAll ||
      (period == _Period.custom &&
          (start.month != end.month || start.year != end.year));

  bool get multiYear => isAll || start.year != end.year;

  _HistoryRange shifted(int by) {
    switch (period) {
      case _Period.day:
        return _HistoryRange.of(
          period,
          DateTime(start.year, start.month, start.day + by),
        );
      case _Period.week:
        return _HistoryRange.of(
          period,
          DateTime(start.year, start.month, start.day + 7 * by),
        );
      case _Period.month:
        return _HistoryRange.of(period, DateTime(start.year, start.month + by));
      case _Period.year:
        return _HistoryRange.of(period, DateTime(start.year + by));
      case _Period.all:
      case _Period.custom:
        return this;
    }
  }

  String get label {
    String mon(DateTime d) => _monthNames[d.month - 1].substring(0, 3);
    switch (period) {
      case _Period.day:
        return _fmtLong(start);
      case _Period.week:
        return start.year == end.year
            ? '${mon(start)} ${start.day} – ${mon(end)} ${end.day}, ${end.year}'
            : '${_fmtLong(start)} – ${_fmtLong(end)}';
      case _Period.month:
        return '${_monthNames[start.month - 1]} ${start.year}';
      case _Period.year:
        return '${start.year}';
      case _Period.all:
        return 'All Time';
      case _Period.custom:
        return '${_fmtLong(start)} – ${_fmtLong(end)}';
    }
  }
}

/// Opens the history. It drops down from the top and stops just above the
/// bottom nav bar. Tap the dim area below, tap the handle, or swipe the
/// handle up to close it.
Future<void> showTransactionHistory(BuildContext context) {
  final bottom = MediaQuery.viewPaddingOf(context).bottom + _navBarHeight;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close history',
    barrierColor: AppConstants.popupBarrier,
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (_, _, _) => Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: const _HistoryPanel(),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class _HistoryPanel extends StatefulWidget {
  const _HistoryPanel();

  @override
  State<_HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<_HistoryPanel> {
  final _db = DatabaseHelper.instance;
  late _HistoryRange _range;
  List<HistoryEntry> _entries = const [];
  List<ReminderItem> _reminders = const [];
  bool _loaded = false;
  String? _error;
  // null = show everything (What's left), 'income' or 'expense' = only those.
  String? _typeFilter;

  @override
  void initState() {
    super.initState();
    _range =
        _lastHistoryRange ?? _HistoryRange.of(_Period.month, DateTime.now());
    _load();
    _db.changes.addListener(_load);
  }

  @override
  void dispose() {
    _db.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final entries = await _db.getHistory(
        from: _range.from,
        until: _range.until,
      );
      final reminders = await _db.getReminders();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _reminders = reminders;
        _loaded = true;
        _error = null;
      });
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      if (mounted) setState(() => _error = const UnknownFailure().message);
    }
  }

  Widget _swipeBackground(double radius) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppConstants.spaceLg),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: const Icon(Icons.delete_outline, color: Colors.white),
    );
  }

  /// Same red pop-up as the Categories delete.
  Future<bool> _confirmDelete(String title, String message) async {
    const white = TextStyle(color: Colors.white);
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: AppConstants.popupBarrier,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.red,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.popupRadius),
        ),
        insetPadding: AppConstants.popupInsetPadding,
        titlePadding: AppConstants.popupTitlePaddingCompact,
        contentPadding: AppConstants.popupContentPaddingCompact,
        actionsPadding: AppConstants.popupActionsPaddingCompact,
        title: Text(
          title,
          style: white.copyWith(fontWeight: FontWeight.w600),
        ),
        content: Text(message, style: white),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.red,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Called after the swipe and shrink animation are finished.
  Future<void> _removeEntry(HistoryEntry e) async {
    // Remove it locally first, so the list is already correct.
    setState(() {
      _entries = [
        for (final x in _entries)
          if (x.id != e.id) x,
      ];
    });
    try {
      await _db.softDeleteTransaction(e.id);
    } on Failure catch (f) {
      _snack(f.message);
      _load(); // bring the transaction back
    } catch (_) {
      _snack(const UnknownFailure().message);
      _load();
    }
  }

  Future<bool> _deleteReminderItem(ReminderItem r) async {
    if (!await _confirmDelete(
      'Delete reminder?',
      'This reminder will be deleted.',
    )) {
      return false;
    }
    try {
      await _db.deleteReminder(r.id);
      return true;
    } on Failure catch (f) {
      _snack(f.message);
    } catch (_) {
      _snack(const UnknownFailure().message);
    }
    return false;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  double get _income => _entries
      .where((e) => e.type == 'income')
      .fold(0.0, (sum, e) => sum + e.amount);
  double get _expense => _entries
      .where((e) => e.type == 'expense')
      .fold(0.0, (sum, e) => sum + e.amount);

  void _shift(int by) {
    setState(() => _range = _range.shifted(by));
    _lastHistoryRange = _range;
    _load();
  }

  Future<void> _pickRange() async {
    final picked = await showDialog<_HistoryRange>(
      context: context,
      barrierColor: AppConstants.popupBarrier,
      builder: (_) => _RangeDialog(initial: _range),
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
    _lastHistoryRange = picked;
    _load();
  }

  // ---------- Receipts ----------

  void _openEntry(HistoryEntry first) {
    var current = first;
    _showReceipt(
      context,
      _entryReceipt(first),
      reload: () async {
        final all = await _db.getHistory();
        for (final x in all) {
          if (x.id == first.id) {
            current = x;
            return _entryReceipt(x);
          }
        }
        return null;
      },
      onEdit: () =>
          showTransactionSheet(context, _typeOf(first.type), entry: current),
    );
  }

  void _openReminder(ReminderItem first) {
    var current = first;
    _showReceipt(
      context,
      _reminderReceipt(first),
      reload: () async {
        final all = await _db.getReminders();
        for (final x in all) {
          if (x.id == first.id) {
            current = x;
            return _reminderReceipt(x);
          }
        }
        return null; // done or deleted: the receipt closes
      },
      onEdit: () => showTransactionSheet(
        context,
        TransactionColorType.reminder,
        reminder: current,
      ),
      onDone: () => _markDone(current),
    );
  }

  Future<void> _markDone(ReminderItem r) async {
    var accountId = r.accountId;
    if (accountId == null) {
      // No account saved on the reminder: ask which one to use.
      final accounts = await _db.getAccountOptions();
      if (!mounted) return;
      final picked = await _pickItem(
        context,
        title: 'Account',
        items: [for (final a in accounts) CategoryItem(a.id, a.name, a.typeIcon)],
        iconFor: (item) => _iconForType('', item.icon),
      );
      if (picked == null) return;
      accountId = picked.id;
    }
    try {
      await _db.completeReminder(r, accountId: accountId);
    } on Failure catch (f) {
      _snack(f.message);
    } catch (_) {
      _snack(const UnknownFailure().message);
    }
  }

  _ReceiptData _entryReceipt(HistoryEntry e) => _entryReceiptData(e);

  bool _isOverdue(DateTime due) {
    final n = DateTime.now();
    return DateTime(due.year, due.month, due.day)
        .isBefore(DateTime(n.year, n.month, n.day));
  }

  _ReceiptData _reminderReceipt(ReminderItem r) {
    final s = AppSettings.instance;
    const repeatLabels = {
      'daily': 'Daily',
      'weekly': 'Weekly',
      'monthly': 'Monthly',
      'yearly': 'Yearly',
    };
    return _ReceiptData(
      color: s.reminderColor,
      icon: _iconForCategory(r.categoryIcon),
      title: r.title,
      kind: 'Reminder',
      overdue: _isOverdue(r.dueDate),
      rows: [
        ('Type', _capitalizeWord(r.type), null),
        if (r.categoryName != null)
          ('Category', r.categoryName!, _iconForCategory(r.categoryIcon)),
        (
          'Due date',
          '${_fmtLong(r.dueDate)}, ${_weekdayShort[r.dueDate.weekday - 1]}',
          null,
        ),
        if (repeatLabels.containsKey(r.repeat))
          ('Repeat', repeatLabels[r.repeat]!, null),
        if (r.accountName != null) ('Account', r.accountName!, null),
      ],
      note: r.note?.trim(),
      imagePath: r.imagePath,
      totalLabel: 'AMOUNT',
      totalText: Utils.formatCurrency(
        r.amount,
        symbol: AppConstants.currencySymbol,
      ),
    );
  }

  String _capitalizeWord(String t) =>
      t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);

  // ---------- Pieces ----------

  Widget _stat(IconData icon, Color color, double value, String? filter) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        onTap: () => setState(() {
          // Tapping the same one again shows everything again.
          _typeFilter = (_typeFilter == filter) ? null : filter;
        }),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                Utils.formatCurrency(value, symbol: AppConstants.currencySymbol),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayHeader(DateTime d, Color fg) {
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMd,
        AppConstants.spaceLg,
        AppConstants.spaceMd,
        AppConstants.spaceMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_monthNames[d.month - 1].substring(0, 3)} ${d.day}'
            ',  ${_weekdayLong[d.weekday - 1]}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: muted,
            ),
          ),
          const SizedBox(height: 2),
          Divider(
            height: 1,
            thickness: 1,
            color: fg.withValues(alpha: AppConstants.dividerAlpha),
          ),
        ],
      ),
    );
  }

  Widget _monthHeader(int year, int month, Color fg) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMd,
        AppConstants.spaceLg,
        AppConstants.spaceMd,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _range.multiYear
                ? '${_monthNames[month - 1]} $year'
                : _monthNames[month - 1],
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          const SizedBox(height: AppConstants.spaceXs),
          Divider(height: 1, thickness: 2, color: fg.withValues(alpha: 0.3)),
        ],
      ),
    );
  }

  Widget _entryRow(HistoryEntry e, Color fg) {
    final s = AppSettings.instance;
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final k = _fontScale(context).clamp(0.8, 1.3).toDouble();
    final isTransfer = e.type == 'transfer';
    final color = isTransfer
        ? s.transferColor
        : (e.type == 'income' ? s.incomeColor : s.expenseColor);
    final sign = isTransfer ? '±' : (e.type == 'income' ? '+' : '−');
    final sub = isTransfer
        ? '${e.accountName} → ${e.toAccountName ?? ''}'
        : e.accountName;

    // Same size and shape as the reminder card.
    final card = Material(
      color: _lighter(accent.background),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openEntry(e),
        child: Padding(
          padding: EdgeInsets.all(AppConstants.spaceSmMd * k),
          child: Row(
            children: [
              Container(
                width: 42 * k,
                height: 42 * k,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isTransfer
                      ? Icons.swap_horiz
                      : _iconForCategory(e.categoryIcon),
                  size: 22 * k,
                  color: color,
                ),
              ),
              const SizedBox(width: AppConstants.spaceSmMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                        color: fg.withValues(alpha: AppConstants.mutedAlpha),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.spaceSm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$sign${Utils.formatCurrency(e.amount, symbol: AppConstants.currencySymbol)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fmtTime12(e.date),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 11,
                      color: fg.withValues(alpha: AppConstants.mutedAlpha),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceMd),
      child: Dismissible(
        key: ValueKey('tx-${e.id}'),
        direction: DismissDirection.endToStart,
        resizeDuration: const Duration(milliseconds: 250),
        onDismissed: (_) => _removeEntry(e),
        background: _swipeBackground(16),
        child: card,
      ),
    );
  }

  Widget _reminderCard(ReminderItem r, Color fg) {
    final s = AppSettings.instance;
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final k = _fontScale(context).clamp(0.8, 1.3).toDouble();
    final overdue = _isOverdue(r.dueDate);
    final base = overdue ? _darker(s.reminderColor) : s.reminderColor;
    final amountColor = r.type == 'income' ? s.incomeColor : s.expenseColor;
    final due =
        '${overdue ? 'Due ' : ''}${_monthNames[r.dueDate.month - 1].substring(0, 3)} '
        '${r.dueDate.day}, ${_weekdayShort[r.dueDate.weekday - 1]}';

    final card = Material(
      // Solid color, so the red swipe background doesn't show through.
      color: Color.alphaBlend(
        base.withValues(alpha: 0.14),
        _lighter(accent.background),
      ),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openReminder(r),
        child: Padding(
          padding: EdgeInsets.all(AppConstants.spaceSmMd * k),
          child: Row(
            children: [
              Container(
                width: 42 * k,
                height: 42 * k,
                decoration: BoxDecoration(
                  color: base.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  overdue
                      ? Icons.warning_amber_rounded
                      : Icons.notifications_active,
                  size: 22 * k,
                  color: base,
                ),
              ),
              const SizedBox(width: AppConstants.spaceSmMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          _iconForCategory(r.categoryIcon),
                          size: 13 * k,
                          color: amountColor,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            r.categoryName ?? _capitalizeWord(r.type),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 12,
                              color: fg.withValues(
                                alpha: AppConstants.mutedAlpha,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.spaceSm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${r.type == 'income' ? '+' : '−'}'
                    '${Utils.formatCurrency(r.amount, symbol: AppConstants.currencySymbol)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: amountColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    due,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 11,
                      color: overdue
                          ? base
                          : fg.withValues(alpha: AppConstants.mutedAlpha),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMd,
        0,
        AppConstants.spaceMd,
        AppConstants.spaceSm,
      ),
      child: Dismissible(
        key: ValueKey('rem-${r.id}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _deleteReminderItem(r),
        onDismissed: (_) => setState(() {
          _reminders = [
            for (final x in _reminders)
              if (x.id != r.id) x,
          ];
        }),
        background: _swipeBackground(16),
        child: card,
      ),
    );
  }

  Widget _remindersSection(Color fg) {
    final color = AppSettings.instance.reminderColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceMd,
            AppConstants.spaceMd,
            AppConstants.spaceMd,
            AppConstants.spaceSm,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.notifications_outlined, size: 18, color: color),
              ),
              const SizedBox(width: AppConstants.spaceSm),
              Text(
                'REMINDERS',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: color,
                ),
              ),
              const SizedBox(width: AppConstants.spaceSm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_reminders.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final r in _reminders) _reminderCard(r, fg),
      ],
    );
  }

  List<Widget> _listChildren(Color fg) {
    final out = <Widget>[];
    if (_reminders.isNotEmpty) out.add(_remindersSection(fg));
    if (!_loaded) {
      out.add(const Padding(
        padding: EdgeInsets.all(AppConstants.spaceXl),
        child: Center(child: CircularProgressIndicator()),
      ));
      return out;
    }
    // Only the transactions that match the pressed analytic.
    final visible = _typeFilter == null
        ? _entries
        : [
            for (final e in _entries)
              if (e.type == _typeFilter) e,
          ];
    if (visible.isEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.all(AppConstants.spaceXl),
        child: Center(
          child: Text(
            'No transactions',
            style: TextStyle(
              color: fg.withValues(alpha: AppConstants.mutedAlpha),
            ),
          ),
        ),
      ));
      return out;
    }
    int? lastMonth;
    String? lastDay;
    for (final e in visible) {
      final d = e.date;
      if (_range.groupByMonth) {
        final mk = d.year * 100 + d.month;
        if (mk != lastMonth) {
          out.add(_monthHeader(d.year, d.month, fg));
          lastMonth = mk;
          lastDay = null;
        }
      }
      final dk = '${d.year}-${d.month}-${d.day}';
      if (dk != lastDay) {
        out.add(_dayHeader(d, fg));
        lastDay = dk;
      }
      out.add(_entryRow(e, fg));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final s = AppSettings.instance;
    final left = _income - _expense;
    final scale = _fontScale(context).clamp(0.9, 1.3).toDouble();

    return Material(
      color: accent.background,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(height: MediaQuery.viewPaddingOf(context).top),
          // Title + date filter button
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spaceMd + AppConstants.spaceXs,
              AppConstants.spaceMd,
              AppConstants.spaceSm,
              0,
            ),
            child: Row(
              children: [
                Container(
                  width: 40 * scale,
                  height: 40 * scale,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: AppConstants.tintAlpha),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Icon(Icons.receipt_long_outlined, color: fg),
                ),
                const SizedBox(width: AppConstants.spaceMd),
                Expanded(
                  child: Text(
                    'History',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.filter_list, color: fg),
                  tooltip: 'Filter by date',
                  onPressed: _pickRange,
                ),
              ],
            ),
          ),
          // < date >
          Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: _range.canStep
                    ? IconButton(
                        icon: Icon(Icons.chevron_left, color: fg),
                        onPressed: () => _shift(-1),
                      )
                    : null,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _range.label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                height: 48,
                child: _range.canStep
                    ? IconButton(
                        icon: Icon(Icons.chevron_right, color: fg),
                        onPressed: () => _shift(1),
                      )
                    : null,
              ),
            ],
          ),
          // Income | Expense | What's left
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spaceMd,
              AppConstants.spaceSm,
              AppConstants.spaceMd,
              AppConstants.spaceMd,
            ),
            child: Row(
              children: [
                _stat(Icons.arrow_upward, s.incomeColor, _income, 'income'),
                _stat(Icons.arrow_downward, s.expenseColor, _expense, 'expense'),
                _stat(
                  Icons.account_balance_wallet_outlined,
                  left >= 0 ? s.incomeColor : s.expenseColor,
                  left,
                  null,
                ),
              ],
            ),
          ),
          // Line the list scrolls under
          Divider(height: 1, thickness: 2, color: fg.withValues(alpha: 0.3)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(AppConstants.spaceSm),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          Expanded(
            child: ColoredBox(
              color: _lighter(accent.background),
              child: ListView(
                padding: const EdgeInsets.only(bottom: AppConstants.spaceMd),
                children: _listChildren(fg),
              ),
            ),
          ),
          // Handle: tap or swipe up to close
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < 0) Navigator.of(context).pop();
            },
            child: ColoredBox(
              color: _lighter(accent.background),
              child: SizedBox(
                height: 28,
                width: double.infinity,
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: AppConstants.borderAlpha),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------
// Analytics pop-up
// ------------------------------------------------------------------

/// The last date filter used in Analytics. Kept while the app is open.
/// The Total Balance card listens to it, so its income / expense follow it.
final ValueNotifier<_HistoryRange?> _analyticsRange =
    ValueNotifier<_HistoryRange?>(null);

/// Opens Analytics. Same drop-down from the top as the history.
Future<void> showAnalytics(BuildContext context) {
  final bottom = MediaQuery.viewPaddingOf(context).bottom + _navBarHeight;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close analytics',
    barrierColor: AppConstants.popupBarrier,
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (_, _, _) => Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: const _AnalyticsPanel(),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class _AnalyticsPanel extends StatefulWidget {
  const _AnalyticsPanel();

  @override
  State<_AnalyticsPanel> createState() => _AnalyticsPanelState();
}

class _AnalyticsPanelState extends State<_AnalyticsPanel> {
  final _db = DatabaseHelper.instance;
  late _HistoryRange _range;
  List<HistoryEntry> _entries = const [];
  List<ReminderItem> _reminders = const [];
  List<_AccountCardData> _accounts = const [];
  List<int> _typeOrder = const [];
  String _view = 'all'; // all (default graphs) | income | expense | net

  @override
  void initState() {
    super.initState();
    _range = _analyticsRange.value ??
        _HistoryRange.of(_Period.month, DateTime.now());
    _load();
    _db.changes.addListener(_load);
  }

  @override
  void dispose() {
    _db.changes.removeListener(_load);
    super.dispose();
  }

  double get _income => _entries
      .where((e) => e.type == 'income')
      .fold(0.0, (sum, e) => sum + e.amount);
  double get _expense => _entries
      .where((e) => e.type == 'expense')
      .fold(0.0, (sum, e) => sum + e.amount);

  void _shift(int by) {
    setState(() => _range = _range.shifted(by));
    _analyticsRange.value = _range;
    _load();
  }

  Future<void> _pickRange() async {
    final picked = await showDialog<_HistoryRange>(
      context: context,
      barrierColor: AppConstants.popupBarrier,
      builder: (_) => _RangeDialog(initial: _range),
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
    _analyticsRange.value = _range;
    _load();
  }

  Future<void> _load() async {
    try {
      final entries =
          await _db.getHistory(from: _range.from, until: _range.until);
      final reminders = await _db.getReminders();
      final options = await _db.getAccountOptions();
      final order = await _db.getTypeOrder(); // same order as Finance
      final accounts = <_AccountCardData>[];
      for (final o in options) {
        final a = await _queryAccount(o.id);
        if (a != null) accounts.add(a);
      }
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _reminders = reminders;
        _accounts = accounts;
        _typeOrder = order;
      });
    } catch (_) {}
  }

  /// No underline. Pressing opens that view.
  Widget _stat(IconData icon, Color color, double value, String view) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        onTap: () => setState(() => _view = view),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                  Utils.formatCurrency(
                    value,
                    symbol: AppConstants.currencySymbol,
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Category pressed in the income / expense graphs.
  void _openCategory(_CatSlice c) => _showCategoryView(
        context,
        category: _CategoryRef(c.id, c.name, c.icon, c.color, _view),
        range: _range,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final s = AppSettings.instance;
    final left = _income - _expense;
    final scale = _fontScale(context).clamp(0.9, 1.3).toDouble();

    return Material(
      color: accent.background,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(height: MediaQuery.viewPaddingOf(context).top),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spaceMd + AppConstants.spaceXs,
              AppConstants.spaceMd,
              AppConstants.spaceSm,
              0,
            ),
            child: Row(
              children: [
                Container(
                  width: 40 * scale,
                  height: 40 * scale,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: AppConstants.tintAlpha),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Icon(Icons.insights_outlined, color: fg),
                ),
                const SizedBox(width: AppConstants.spaceMd),
                // Pressing the title returns to the default graphs.
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _view = 'all'),
                    child: Text(
                      'Analytics',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.filter_list, color: fg),
                  tooltip: 'Filter by date',
                  onPressed: _pickRange,
                ),
              ],
            ),
          ),
          Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: _range.canStep
                    ? IconButton(
                        icon: Icon(Icons.chevron_left, color: fg),
                        onPressed: () => _shift(-1),
                      )
                    : null,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _range.label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                height: 48,
                child: _range.canStep
                    ? IconButton(
                        icon: Icon(Icons.chevron_right, color: fg),
                        onPressed: () => _shift(1),
                      )
                    : null,
              ),
            ],
          ),
          // Income | Expense | Net
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spaceMd,
              AppConstants.spaceSm,
              AppConstants.spaceMd,
              AppConstants.spaceMd,
            ),
            child: Row(
              children: [
                _stat(Icons.arrow_upward, s.incomeColor, _income, 'income'),
                _stat(
                    Icons.arrow_downward, s.expenseColor, _expense, 'expense'),
                _stat(
                  Icons.account_balance_wallet_outlined,
                  left >= 0 ? s.incomeColor : s.expenseColor,
                  left,
                  'net',
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 2, color: fg.withValues(alpha: 0.3)),
          Expanded(
            child: ColoredBox(
              color: _lighter(accent.background),
              child: ListView(
                padding: const EdgeInsets.only(bottom: AppConstants.spaceMd),
                children: [
                  if (_view == 'all')
                    _AnalyticsDefault(
                      stats: _accountStats(_accounts, _entries),
                      typeOrder: _typeOrder,
                      entries: _entries,
                      reminders: _reminders,
                      range: _range,
                      fg: fg,
                      onOpen: (v) => setState(() => _view = v),
                    )
                  else if (_view == 'net')
                    _AccountsOverview(
                      stats: _accountStats(_accounts, _entries),
                      typeOrder: _typeOrder,
                      fg: fg,
                      onOpen: (a) => _showAccountView(
                        context,
                        a,
                        hidden: false,
                        analytics: true,
                        range: _range,
                      ),
                    )
                  else
                    _KindCharts(
                      entries: _entries,
                      kind: _view,
                      range: _range,
                      fg: fg,
                      onOpenCategory: _openCategory,
                    ),
                ],
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < 0) Navigator.of(context).pop();
            },
            child: ColoredBox(
              color: _lighter(accent.background),
              child: SizedBox(
                height: 28,
                width: double.infinity,
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: AppConstants.borderAlpha),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------
// Receipt pop-up
// ------------------------------------------------------------------

class _ReceiptData {
  final Color color;
  final IconData icon;
  final String title;
  final String kind; // Income / Expense / Transfer / Reminder
  final bool overdue;
  final List<(String, String, IconData?)> rows; // label, value, icon
  final String? note;
  final String? imagePath;
  final String totalLabel;
  final String totalText;

  const _ReceiptData({
    required this.color,
    required this.icon,
    required this.title,
    required this.kind,
    required this.rows,
    required this.totalLabel,
    required this.totalText,
    this.overdue = false,
    this.note,
    this.imagePath,
  });
}

/// [onDone] is only given for reminders (shows the Mark as Done button).
/// [reload] returns fresh data after the database changes (null = close).
Future<void> _showReceipt(
  BuildContext context,
  _ReceiptData data, {
  required Future<_ReceiptData?> Function() reload,
  required VoidCallback onEdit,
  VoidCallback? onDone,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: AppConstants.popupBarrier,
    builder: (ctx) => _ReceiptDialog(
      data: data,
      reload: reload,
      onEdit: onEdit, // the receipt stays open behind the edit sheet
      onDone: onDone == null
          ? null
          : () {
              Navigator.of(ctx).pop();
              onDone();
            },
    ),
  );
}

class _ReceiptDialog extends StatefulWidget {
  final _ReceiptData data;
  final Future<_ReceiptData?> Function() reload;
  final VoidCallback onEdit;
  final VoidCallback? onDone;

  const _ReceiptDialog({
    required this.data,
    required this.reload,
    required this.onEdit,
    this.onDone,
  });

  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<_ReceiptDialog> {
  /// Receipt size settings: edit these to resize it.
  static const double _radius = 20; // corner roundness
  static const double _imageMaxHeight = 400; // max picture height
  static const double _sideInset = 32; // space left/right of the popup
  static const double _bodyPad = 20; // side padding of the receipt body
  /// 20% of the body padding: the picture almost touches the edges.
  static const double _imageSidePad = _bodyPad * 0.5;

  late _ReceiptData _data = widget.data;

  @override
  void initState() {
    super.initState();
    DatabaseHelper.instance.changes.addListener(_refresh);
  }

  @override
  void dispose() {
    DatabaseHelper.instance.changes.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final fresh = await widget.reload();
      if (!mounted) return;
      if (fresh == null) {
        Navigator.of(context).pop();
      } else {
        setState(() => _data = fresh);
      }
    } catch (_) {
      // Keep showing what we have.
    }
  }

  Widget _row(String label, String value, IconData? icon, Color fg, Color tint) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: fg.withValues(alpha: AppConstants.mutedAlpha),
            ),
          ),
          const SizedBox(width: AppConstants.spaceMd),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: tint),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 14, color: fg),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final accentC = data.color;
    final onDone = widget.onDone;
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final body = accent.background;
    final isBW = _isBW(accentC);
    // Strong, saturated colors (not mixed with white).
    final header = Color.alphaBlend(accentC.withValues(alpha: 0.4), body);
    final bright = isBW ? accentC : _vivid(accentC);
    final dash = fg.withValues(alpha: 0.35);
    final note = data.note;
    final image = data.imagePath;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: _sideInset, vertical: 24),
      child: Stack(
        clipBehavior: Clip.none, // lets the edit button sit on the edge
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: Material(
              color: body,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ----- Colored top (taller) -----
                    Container(
                      width: double.infinity,
                      color: header,
                      padding: const EdgeInsets.fromLTRB(20, 40, 20, 26),
                      child: Column(
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: data.color.withValues(alpha: 0.3),
                              border: Border.all(color: bright, width: 3),
                            ),
                            child: Icon(data.icon, size: 32, color: bright),
                          ),
                          const SizedBox(height: AppConstants.spaceMd),
                          Text(
                            data.title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: fg,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            data.kind,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: bright,
                            ),
                          ),
                          if (data.overdue) ...[
                            const SizedBox(height: AppConstants.spaceSmMd),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: _darker(data.color)
                                    .withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 16,
                                    color: bright,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Overdue',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: bright,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Scalloped edge
                    LayoutBuilder(
                      builder: (context, c) {
                        final n = (c.maxWidth / 18).round();
                        final r = c.maxWidth / n / 2;
                        return SizedBox(
                          width: c.maxWidth,
                          height: r,
                          child: CustomPaint(
                            painter: _ScallopPainter(header, body, n),
                          ),
                        );
                      },
                    ),
                    // ----- Picture: nearly the full width -----
                    if (image != null && image.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          _imageSidePad,
                          AppConstants.spaceSm,
                          _imageSidePad,
                          0,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: _imageMaxHeight,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(image),
                              width: double.infinity,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => Padding(
                                padding: const EdgeInsets.all(16),
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: fg,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    // ----- Receipt body (more spaced out) -----
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        _bodyPad,
                        AppConstants.spaceMd,
                        _bodyPad,
                        28,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Dashed(color: dash),
                          const SizedBox(height: AppConstants.spaceSmMd),
                          for (final r in data.rows)
                            _row(r.$1, r.$2, r.$3, fg, bright),
                          if (note != null && note.isNotEmpty) ...[
                            const SizedBox(height: AppConstants.spaceSmMd),
                            _Dashed(color: dash),
                            const SizedBox(height: AppConstants.spaceSmMd),
                            _row('Note', note, null, fg, bright),
                          ],
                          const SizedBox(height: AppConstants.spaceSmMd),
                          _Dashed(color: dash),
                          const SizedBox(height: AppConstants.spaceMd),
                          Row(
                            children: [
                              Text(
                                data.totalLabel,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                  color: fg,
                                ),
                              ),
                              const SizedBox(width: AppConstants.spaceMd),
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    data.totalText,
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      color: bright,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (onDone != null) ...[
                            const SizedBox(height: AppConstants.spaceMd),
                            Center(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF1B6B3A),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(0, 46),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 22,
                                  ),
                                ),
                                onPressed: onDone,
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text(
                                  'Mark as Done',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Edit button: dulled version of the total's bright color, pen = glyph color
          Positioned(
            top: -10,
            right: -10,
            child: Material(
              // 0.75 = how much of the bright color is kept. Lower = duller.
              color: Color.alphaBlend(bright.withValues(alpha: 0.75), body),
              elevation: 0,
              shadowColor: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onEdit,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.edit,
                    size: 20,
                    color: fg,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dashed separator line (- - - - -).
class _Dashed extends StatelessWidget {
  final Color color;
  const _Dashed({required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final n = (c.maxWidth / 9).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < n; i++)
              Container(width: 5, height: 1.5, color: color),
          ],
        );
      },
    );
  }
}

/// The round bumps between the colored top and the receipt body.
class _ScallopPainter extends CustomPainter {
  final Color top;
  final Color body;
  final int count;
  const _ScallopPainter(this.top, this.body, this.count);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = top);
    final r = size.width / count / 2;
    final paint = Paint()..color = body;
    for (var i = 0; i < count; i++) {
      canvas.drawCircle(Offset(r * (2 * i + 1), size.height), r, paint);
    }
  }

  @override
  bool shouldRepaint(_ScallopPainter old) =>
      old.top != top || old.body != body || old.count != count;
}

// ------------------------------------------------------------------
// Date filter pop-up (Day / Week / Month / Year / All / Custom)
// ------------------------------------------------------------------

class _RangeDialog extends StatefulWidget {
  final _HistoryRange initial;
  final Color? background; // new
  final Color? foreground; // new
  const _RangeDialog({
    required this.initial,
    this.background,
    this.foreground,
  });

  @override
  State<_RangeDialog> createState() => _RangeDialogState();
}

class _RangeDialogState extends State<_RangeDialog> {
  /// Fixed height of the middle part, so the pop-up never changes shape.
  static const double _bodyHeight = 262;

  static const _tabs = <(_Period, String)>[
    (_Period.day, 'Day'),
    (_Period.week, 'Week'),
    (_Period.month, 'Month'),
    (_Period.year, 'Year'),
    (_Period.all, 'All'),
    (_Period.custom, 'Custom'),
  ];

  late _Period _period;
  late DateTime _view; // month shown / year shown / decade shown
  late DateTime _picked; // date only
  DateTime? _cStart;
  DateTime? _cEnd;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    final n = DateTime.now();
    _period = i.period;
    _picked = i.isAll ? DateTime(n.year, n.month, n.day) : i.start;
    if (i.period == _Period.custom) {
      _cStart = i.start;
      _cEnd = i.end;
    }
    _view = DateTime(_picked.year, _picked.month);
  }

  _HistoryRange get _result {
    switch (_period) {
      case _Period.all:
        return _HistoryRange.of(_Period.all, _picked);
      case _Period.custom:
        final s = _cStart ?? _picked;
        return _HistoryRange(_Period.custom, s, _cEnd ?? s);
      default:
        return _HistoryRange.of(_period, _picked);
    }
  }

  String get _pillText {
    final r = _result;
    if (r.period == _Period.day) {
      return '${_weekdayShort[r.start.weekday - 1]}, ${r.label}';
    }
    return r.label;
  }

  int get _decadeStart => ((_view.year - 1) ~/ 10) * 10 + 1;

  String get _viewTitle {
    switch (_period) {
      case _Period.month:
        return '${_view.year}';
      case _Period.year:
        return '$_decadeStart – ${_decadeStart + 9}';
      default:
        return '${_monthNames[_view.month - 1]} ${_view.year}';
    }
  }

  void _step(int by) {
    setState(() {
      switch (_period) {
        case _Period.month:
          _view = DateTime(_view.year + by);
        case _Period.year:
          _view = DateTime(_view.year + 10 * by);
        default:
          _view = DateTime(_view.year, _view.month + by);
      }
    });
  }

  void _tapDay(DateTime date) {
    setState(() {
      if (_period == _Period.custom) {
        final s = _cStart;
        if (s == null || _cEnd != null) {
          _cStart = date;
          _cEnd = null;
        } else if (date.isBefore(s)) {
          _cEnd = s;
          _cStart = date;
        } else {
          _cEnd = date;
        }
      } else {
        _picked = date;
      }
    });
  }

  Widget _tabBar(Color fg) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: AppConstants.tintAlpha),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final t in _tabs)
            Expanded(
              child: Material(
                color: t.$1 == _period
                    ? fg.withValues(alpha: 0.3)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => setState(() => _period = t.$1),
                  child: SizedBox(
                    height: 40,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          t.$2,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: t.$1 == _period
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: t.$1 == _period
                                ? fg
                                : fg.withValues(
                                    alpha: AppConstants.mutedAlpha,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _navRow(Color fg) {
    if (_period == _Period.all) return const SizedBox(height: 40);
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.chevron_left, color: fg),
          onPressed: () => _step(-1),
        ),
        Expanded(
          child: Center(
            child: Text(
              _viewTitle,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.chevron_right, color: fg),
          onPressed: () => _step(1),
        ),
      ],
    );
  }

  Widget _dayCell(int day, int days, Color fg) {
    if (day < 1 || day > days) return const SizedBox(height: 38);
    final date = DateTime(_view.year, _view.month, day);
    final today = _dateOnly(DateTime.now());
    final isToday = date == today;
    var inRange = false;
    var strong = false;
    switch (_period) {
      case _Period.day:
        strong = date == _picked;
      case _Period.week:
        final w = _HistoryRange.of(_Period.week, _picked);
        inRange = !date.isBefore(w.start) && !date.isAfter(w.end);
        strong = date == _picked;
      case _Period.custom:
        final s = _cStart;
        if (s != null) {
          final e = _cEnd ?? s;
          inRange = !date.isBefore(s) && !date.isAfter(e);
          strong = date == s || date == e;
        }
      default:
        break;
    }
    // Week tab: every day of the current week gets a soft outline.
    var inThisWeek = false;
    if (_period == _Period.week) {
      final tw = _HistoryRange.of(_Period.week, today);
      inThisWeek = !date.isBefore(tw.start) && !date.isAfter(tw.end);
    }
    final highlighted = inRange || strong;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _tapDay(date),
        child: Container(
          height: 34,
          alignment: Alignment.center,
                    decoration: BoxDecoration(
            color: strong
                ? fg.withValues(alpha: 0.38)
                : (inRange ? fg.withValues(alpha: 0.16) : null),
            borderRadius: BorderRadius.circular(12),
            border: isToday
                ? Border.all(color: fg, width: 2)
                : (inThisWeek
                    ? Border.all(color: fg.withValues(alpha: 0.5), width: 1.5)
                    : null),
          ),
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 16,
              fontWeight: (highlighted || isToday)
                  ? FontWeight.w700
                  : FontWeight.w400,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }

  Widget _calendar(Color fg) {
    final lead = DateTime(_view.year, _view.month, 1).weekday - 1; // Mon = 0
    final days = DateTime(_view.year, _view.month + 1, 0).day;
    return Column(
      children: [
        SizedBox(
          height: 28,
          child: Row(
            children: [
              for (final l in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Center(
                    child: Text(
                      l,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: fg.withValues(alpha: AppConstants.mutedAlpha),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Always 6 rows, so every month has the same height.
        for (var r = 0; r < 6; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(child: _dayCell(r * 7 + c - lead + 1, days, fg)),
            ],
          ),
      ],
    );
  }

  Widget _gridCell(
    String text,
    bool selected,
    Color fg,
    VoidCallback onTap, {
    bool current = false,
  }) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
                    decoration: BoxDecoration(
            color: selected ? fg.withValues(alpha: 0.3) : null,
            borderRadius: BorderRadius.circular(14),
            border: current ? Border.all(color: fg, width: 2) : null,
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 17,
              fontWeight: (selected || current)
                  ? FontWeight.w800
                  : FontWeight.w500,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }

  Widget _grid(int count, Widget Function(int i) cell) {
    return Center(
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisExtent: 54,
        ),
        itemCount: count,
        itemBuilder: (_, i) => cell(i),
      ),
    );
  }

  Widget _body(Color fg) {
    switch (_period) {
      case _Period.month:
        final now = DateTime.now();
        return _grid(
          12,
          (i) => _gridCell(
            _monthNames[i].substring(0, 3),
            _picked.year == _view.year && _picked.month == i + 1,
            fg,
            () => setState(() => _picked = DateTime(_view.year, i + 1)),
            current: now.year == _view.year && now.month == i + 1,
          ),
        );
      case _Period.year:
        final now = DateTime.now();
        return _grid(
          10,
          (i) => _gridCell(
            '${_decadeStart + i}',
            _picked.year == _decadeStart + i,
            fg,
            () => setState(() => _picked = DateTime(_decadeStart + i)),
            current: now.year == _decadeStart + i,
          ),
        );
      case _Period.all:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.all_inclusive,
                size: 64,
                color: fg.withValues(alpha: AppConstants.mutedAlpha),
              ),
              const SizedBox(height: AppConstants.spaceMd),
              Text(
                'Showing all transactions',
                style: TextStyle(
                  fontSize: 18,
                  color: fg.withValues(alpha: AppConstants.mutedAlpha),
                ),
              ),
            ],
          ),
        );
      default:
        return _calendar(fg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final fg = widget.foreground ?? accent.foreground;
    final bg = widget.background ?? accent.background;

    return Dialog(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tabBar(fg),
            const SizedBox(height: AppConstants.spaceSm),
            _navRow(fg),
            SizedBox(height: _bodyHeight, child: _body(fg)),
            const SizedBox(height: AppConstants.spaceSm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              ),
              child: Text(
                _pillText,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spaceMd),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                      foregroundColor: fg,
                      side: BorderSide(color: fg.withValues(alpha: 0.5)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: _sheetGap),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                      backgroundColor: fg,
                      foregroundColor: bg,
                    ),
                    onPressed: () => Navigator.of(context).pop(_result),
                    child: const Text(
                      'Apply',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Transaction pop-ups: Income, Expense, Transfer and Reminder
// ------------------------------------------------------------------

/// Opens the pop-up for [type] (called by the + button in main.dart).
/// Pass [entry] (or [reminder]) to edit an existing one.
Future<void> showTransactionSheet(
  BuildContext context,
  TransactionColorType type, {
  HistoryEntry? entry,
  ReminderItem? reminder,
}) {
  final accent = AppTheme.accentOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: accent.background,
    barrierColor: AppConstants.popupBarrier,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) =>
        _TransactionSheet(type: type, entry: entry, reminder: reminder),
  );
}

const double _sheetRadius = 4;
const double _sheetGap = 12;
const List<String> _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const List<String> _weekdayShort = [
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
];

String _two(int n) => n.toString().padLeft(2, '0');
String _fmtDate(DateTime d) => '${_two(d.month)}/${_two(d.day)}/${d.year}';

/// An account type with its accounts, for the grouped account picker.
class _AccountGroup {
  final int typeId;
  final String typeName;
  final String? typeIcon;
  final List<CategoryItem> items;
  const _AccountGroup(this.typeId, this.typeName, this.typeIcon, this.items);
}

/// Account picker: accounts grouped under their type. The types follow the
/// order of the Finance screen. [disabledId] is shown crossed out and can't
/// be tapped (used on a transfer for the account already chosen on the
/// other side).
Future<CategoryItem?> _pickGroupedAccount(
  BuildContext context, {
  required String title,
  required List<_AccountGroup> groups,
  CategoryItem? selected,
  int? disabledId,
}) {
  final base = Theme.of(context);
  final accent = AppTheme.accentOf(context);
  final fg = accent.foreground;

  return showModalBottomSheet<CategoryItem>(
    context: context,
    backgroundColor: accent.background,
    barrierColor: AppConstants.popupBarrier,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceLg,
        AppConstants.spaceSmMd,
        AppConstants.spaceLg,
        AppConstants.spaceLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: AppConstants.borderAlpha),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spaceLg),
          Text(
            title,
            style: base.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          const SizedBox(height: AppConstants.spaceMd),
          for (final group in groups) ...[
            // Type header
            Row(
              children: [
                Icon(
                  _iconForType(group.typeName, group.typeIcon),
                  size: 18,
                  color: fg.withValues(alpha: AppConstants.mutedAlpha),
                ),
                const SizedBox(width: AppConstants.spaceSm),
                Text(
                  group.typeName,
                  style: base.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: fg.withValues(alpha: AppConstants.mutedAlpha),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceSm),
            Wrap(
              spacing: AppConstants.spaceSm,
              runSpacing: AppConstants.spaceSm,
              children: [
                for (final item in group.items)
                  Opacity(
                    opacity: item.id == disabledId ? 0.4 : 1,
                    child: Material(
                      color: fg.withValues(
                        alpha: item.id == selected?.id
                            ? AppConstants.iconTileSelectedAlpha
                            : AppConstants.tintAlpha,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: item.id == disabledId
                            ? null
                            : () => Navigator.of(sheetContext).pop(item),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppConstants.spaceMd,
                            vertical: AppConstants.spaceSmMd + 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _iconForType(group.typeName, group.typeIcon),
                                size: 15,
                                color: fg,
                              ),
                              const SizedBox(width: AppConstants.spaceSm),
                              Text(
                                item.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: fg,
                                  decoration: item.id == disabledId
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: fg,
                                  decorationThickness: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceMd),
          ],
        ],
      ),
    ),
  );
}

/// Outlined field look shared by every field of the pop-ups.
InputDecoration _sheetDecoration(
  Color fg, {
  required String label,
  Widget? icon,
  Widget? suffix,
  FloatingLabelBehavior? floating,
  double vPad = 15,
  bool alignLabelWithHint = false,
  EdgeInsets? contentPadding,
}) {
  OutlineInputBorder border(double alpha, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(_sheetRadius),
        borderSide: BorderSide(
          color: fg.withValues(alpha: alpha),
          width: width,
        ),
      );
  return InputDecoration(
    isDense: true,
    labelText: label,
    alignLabelWithHint: alignLabelWithHint,
    labelStyle: TextStyle(color: fg.withValues(alpha: AppConstants.mutedAlpha)),
    floatingLabelStyle: TextStyle(color: fg),
    floatingLabelBehavior: floating,
    prefixIcon: icon,
    suffixIcon: suffix,
    contentPadding: contentPadding ??
        EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMd,
          vertical: vPad,
        ),
    border: border(AppConstants.borderAlpha, 1),
    enabledBorder: border(AppConstants.borderAlpha, 1),
    focusedBorder: border(1, 2),
  );
}

/// A tappable box that looks like the other fields.
Widget _sheetSelector({
  required Color fg,
  required String label,
  required Widget icon,
  required VoidCallback onTap,
  String? value,
  bool chevron = true,
  bool alwaysFloat = false,
  bool shrink = false,
  double vPad = 12,
}) {
  final style = TextStyle(color: fg, fontSize: 16);
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(_sheetRadius),
    child: InputDecorator(
      isEmpty: value == null,
      decoration: _sheetDecoration(
        fg,
        label: label,
        vPad: vPad,
        icon: icon,
        floating: alwaysFloat ? FloatingLabelBehavior.always : null,
        suffix: chevron ? Icon(Icons.expand_more, color: fg) : null,
      ),
      child: shrink
          ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value ?? '', maxLines: 1, style: style),
            )
          : Text(
              value ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
    ),
  );
}

class _TransactionSheet extends StatefulWidget {
  final TransactionColorType type;
  final HistoryEntry? entry;
  final ReminderItem? reminder;
  const _TransactionSheet({required this.type, this.entry, this.reminder});

  @override
  State<_TransactionSheet> createState() => _TransactionSheetState();
}

class _TransactionSheetState extends State<_TransactionSheet> {
  static const _repeatOptions = <CategoryItem>[
    CategoryItem(0, 'No repeat'),
    CategoryItem(1, 'Daily'),
    CategoryItem(2, 'Weekly'),
    CategoryItem(3, 'Monthly'),
    CategoryItem(4, 'Yearly'),
  ];
  static const _repeatKeys = ['none', 'daily', 'weekly', 'monthly', 'yearly'];

  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  List<CategoryItem> _incomeCategories = const [];
  List<CategoryItem> _expenseCategories = const [];
  List<_AccountGroup> _accountGroups = const [];
  final Map<int, String> _accountTypes = {};

  CategoryItem? _category;
  CategoryItem? _account; // "From" on a transfer
  CategoryItem? _toAccount;
  CategoryItem? _repeat; // null = nothing chosen yet (not prefilled)
  DateTime? _date;
  bool _reminderIncome = false; // reminder: false = Expense, true = Income
  String? _imagePath;
  bool _didSave = false;
  bool _saving = false;
  String? _error;

  String? _originalImage; // picture the edited item already had
  bool get _editing => widget.entry != null || widget.reminder != null;

  bool get _isReminder => widget.type == TransactionColorType.reminder;
  bool get _isTransfer => widget.type == TransactionColorType.transfer;
  bool get _incomeLike =>
      _isReminder ? _reminderIncome : widget.type == TransactionColorType.income;
  List<CategoryItem> get _categoryList =>
      _incomeLike ? _incomeCategories : _expenseCategories;

  @override
  void initState() {
    super.initState();
    if (!_isReminder) {
      final n = DateTime.now();
      _date = DateTime(n.year, n.month, n.day, n.hour, n.minute); // prefilled
    }
    // Edit mode: start with the saved values.
    final e = widget.entry;
    final r = widget.reminder;
    if (e != null) {
      _title.text = e.title;
      _amount.text = e.amount.toStringAsFixed(2);
      _note.text = e.note ?? '';
      _date = e.date;
      _imagePath = _originalImage = e.imagePath;
    }
    if (r != null) {
      _title.text = r.title;
      _amount.text = r.amount.toStringAsFixed(2);
      _note.text = r.note ?? '';
      _date = r.dueDate;
      _reminderIncome = r.type == 'income';
      final i = _repeatKeys.indexOf(r.repeat);
      _repeat = _repeatOptions[i < 0 ? 0 : i];
      _imagePath = _originalImage = r.imagePath;
    }
    _title.addListener(_refresh);
    _amount.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    _title.removeListener(_refresh);
    _amount.removeListener(_refresh);
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    // A picked image that was never saved is not kept.
    final path = _imagePath;
    if (!_didSave && path != null && path != _originalImage) _deleteFile(path);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _deleteFile(String path) {
    try {
      File(path).delete();
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final db = DatabaseHelper.instance;
      final income = await db.getCategoryItems(CategoryGroup.income);
      final expense = await db.getCategoryItems(CategoryGroup.expense);
      final accounts = await db.getAccountOptions();

      // Same type order as the Finance screen.
      final saved = await db.getTypeOrder();
      final rank = <int, int>{
        for (var i = 0; i < saved.length; i++) saved[i]: i,
      };
      final byType = <int, List<AccountOption>>{};
      for (final a in accounts) {
        byType.putIfAbsent(a.typeId, () => []).add(a);
      }
      const last = 1 << 30;
      final typeIds = byType.keys.toList()
        ..sort((a, b) {
          final ra = rank[a] ?? last;
          final rb = rank[b] ?? last;
          return ra != rb ? ra.compareTo(rb) : a.compareTo(b);
        });
      final groups = [
        for (final id in typeIds)
          _AccountGroup(
            id,
            byType[id]!.first.typeName,
            byType[id]!.first.typeIcon,
            [
              for (final a in byType[id]!)
                CategoryItem(a.id, a.name, a.typeIcon),
            ],
          ),
      ];
      CategoryItem? find(List<CategoryItem> list, int? id) {
        for (final i in list) {
          if (i.id == id) return i;
        }
        return null;
      }

      CategoryItem? findAccount(int? id) {
        for (final g in groups) {
          final f = find(g.items, id);
          if (f != null) return f;
        }
        return null;
      }

      if (!mounted) return;
      setState(() {
        _incomeCategories = income;
        _expenseCategories = expense;
        _accountGroups = groups;
        for (final a in accounts) {
          _accountTypes[a.id] = a.typeName;
        }
        // Edit mode: select the saved category / accounts.
        final e = widget.entry;
        final r = widget.reminder;
        if (e != null) {
          _account = findAccount(e.accountId);
          _toAccount = findAccount(e.toAccountId);
          if (e.type == 'income') _category = find(income, e.categoryId);
          if (e.type == 'expense') _category = find(expense, e.categoryId);
        }
        if (r != null) {
          _account = findAccount(r.accountId);
          _category = find(r.type == 'income' ? income : expense, r.categoryId);
        }
      });
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      // Saved order unreadable: the accounts just stay in the default order.
    }
  }

  // ---------- Rules ----------

  bool get _canSave {
    if (_saving) return false;
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0 || _date == null) return false;
    if (_isTransfer) return _account != null && _toAccount != null;
    if (_title.text.trim().isEmpty) return false;
    if (_isReminder) return true; // category, account and repeat are optional
    return _account != null && _category != null;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final db = DatabaseHelper.instance;
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    try {
      if (_editing) {
        await _saveEdit(db, amount);
      } else {
        switch (widget.type) {
          case TransactionColorType.income:
          case TransactionColorType.expense:
            await db.addTransaction(
              type: widget.type.name,
              title: _title.text,
              amount: amount,
              date: _date!,
              accountId: _account!.id,
              categoryId: _category!.id,
              note: _note.text,
              imagePath: _imagePath,
            );
          case TransactionColorType.transfer:
            await db.addTransfer(
              title: _title.text.trim().isEmpty ? 'Transfer' : _title.text,
              amount: amount,
              date: _date!,
              fromAccountId: _account!.id,
              toAccountId: _toAccount!.id,
              note: _note.text,
              imagePath: _imagePath,
            );
          case TransactionColorType.reminder:
            await db.addReminder(
              type: _reminderIncome ? 'income' : 'expense',
              title: _title.text,
              amount: amount,
              dueDate: _date!,
              categoryId: _category?.id,
              accountId: _account?.id,
              repeat: _repeatKeys[_repeat?.id ?? 0],
              note: _note.text,
              imagePath: _imagePath,
            );
        }
      }
      _didSave = true;
      if (mounted) Navigator.of(context).pop();
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      if (mounted) setState(() => _error = const UnknownFailure().message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveEdit(DatabaseHelper db, double amount) async {
    final e = widget.entry;
    if (e != null) {
      await db.updateTransaction(
        id: e.id,
        type: e.type,
        title: _isTransfer && _title.text.trim().isEmpty
            ? 'Transfer'
            : _title.text,
        amount: amount,
        date: _date!,
        accountId: _account!.id,
        toAccountId: _isTransfer ? _toAccount!.id : null,
        categoryId: _isTransfer ? null : _category!.id,
        note: _note.text,
        imagePath: _imagePath,
      );
    } else {
      await db.updateReminder(
        id: widget.reminder!.id,
        type: _reminderIncome ? 'income' : 'expense',
        title: _title.text,
        amount: amount,
        dueDate: _date!,
        categoryId: _category?.id,
        accountId: _account?.id,
        repeat: _repeatKeys[_repeat?.id ?? 0],
        note: _note.text,
        imagePath: _imagePath,
      );
    }
  }

  // ---------- Pickers ----------

  IconData _accountIcon(CategoryItem item) =>
      _iconForType(_accountTypes[item.id] ?? '', item.icon);

  Future<void> _pickCategory() async {
    final picked = await _pickItem(
      context,
      title: 'Category',
      items: _categoryList,
      selected: _category,
      iconFor: (item) => _iconForCategory(item.icon),
    );
    if (picked != null) setState(() => _category = picked);
  }

  Future<void> _pickAccount({bool isTo = false}) async {
    // On a transfer the account chosen on the other side is crossed out.
    final other = isTo ? _account : _toAccount;
    final picked = await _pickGroupedAccount(
      context,
      title: isTo ? 'To' : (_isTransfer ? 'From' : 'Account'),
      groups: _accountGroups,
      selected: isTo ? _toAccount : _account,
      disabledId: _isTransfer ? other?.id : null,
    );
    if (picked == null) return;
    setState(() {
      if (isTo) {
        _toAccount = picked;
      } else {
        _account = picked;
      }
    });
  }

  Future<void> _pickRepeat() async {
    final picked = await _pickItem(
      context,
      title: 'Repeat',
      items: _repeatOptions,
      selected: _repeat,
      iconFor: (item) =>
          item.id == 0 ? Icons.remove_circle_outline : Icons.repeat,
    );
    if (picked != null) setState(() => _repeat = picked);
  }

  Future<void> _pickDate(Color color) async {
    final picked = await _showDateTimeDialog(
      context,
      initial: _date ?? DateTime.now(),
      color: color,
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _swapAccounts() {
    setState(() {
      final tmp = _account;
      _account = _toAccount;
      _toAccount = tmp;
    });
  }

  // ---------- Image ----------

  Future<String> _copyToAppFolder(String source) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'attachments'));
    if (!await folder.exists()) await folder.create(recursive: true);
    final target = p.join(
      folder.path,
      '${DateTime.now().microsecondsSinceEpoch}${p.extension(source)}',
    );
    await File(source).copy(target);
    return target;
  }

  /// Asks Camera or Gallery, then keeps a copy inside the app.
  Future<void> _chooseImage() async {
    final choice = await _pickItem(
      context,
      title: 'Add image',
      items: const [CategoryItem(0, 'Camera'), CategoryItem(1, 'Gallery')],
      iconFor: (item) => item.id == 0
          ? Icons.photo_camera_outlined
          : Icons.photo_library_outlined,
    );
    if (choice == null || !mounted) return;
    try {
      final file = await ImagePicker().pickImage(
        source: choice.id == 0 ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (file == null) return;
      final saved = await _copyToAppFolder(file.path);
      final old = _imagePath;
      if (old != null && old != _originalImage) _deleteFile(old);
      if (mounted) setState(() => _imagePath = saved);
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t get that image.');
    }
  }

  void _removeImage() {
    final old = _imagePath;
    if (old != null && old != _originalImage) _deleteFile(old);
    setState(() => _imagePath = null);
  }

  Widget _imageTile(Color fg, double size) {
    final path = _imagePath;
    return InkWell(
      onTap: _chooseImage,
      borderRadius: BorderRadius.circular(_sheetRadius),
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_sheetRadius),
          border: Border.all(
            color: fg.withValues(alpha: AppConstants.borderAlpha),
          ),
        ),
        child: path == null
            ? Center(
                child: Icon(
                  Icons.add_photo_alternate_outlined,
                  color: fg,
                  size: 30,
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Center(
                      child: Icon(Icons.broken_image_outlined, color: fg),
                    ),
                  ),
                  Positioned(
                    top: 3,
                    right: 3,
                    child: GestureDetector(
                      onTap: _removeImage,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ---------- Pieces ----------

  Widget _kindButton({
    required bool selected,
    required Color color,
    required Color fg,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: selected
            ? color.withValues(alpha: 0.18)
            : fg.withValues(alpha: AppConstants.tintAlpha),
        shape: StadiumBorder(
          side: selected ? BorderSide(color: color, width: 2) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: selected ? color : fg),
                const SizedBox(width: AppConstants.spaceSm),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? color : fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateField(Color fg, Color color, {required bool due}) {
    final d = _date;
    return _sheetSelector(
      fg: fg,
      label: due ? 'Due date' : 'Date',
      icon: Icon(Icons.calendar_today_outlined, color: color),
      // Date and the Hour:Min of the transaction.
      value: d == null ? null : '${_fmtDate(d)}  ${Utils.formatTime(d)}',
      chevron: due,
      alwaysFloat: !due,
      shrink: true,
      vPad: 15,
      onTap: () => _pickDate(color),
    );
  }

  Widget _accountField(Color fg, {String label = 'Account', bool isTo = false}) {
    final value = isTo ? _toAccount : _account;
    return _sheetSelector(
      fg: fg,
      label: label,
      value: value?.name,
      icon: Icon(
        value == null ? Icons.touch_app_outlined : _accountIcon(value),
        color: fg,
      ),
      onTap: () => _pickAccount(isTo: isTo),
    );
  }

  Widget _categoryField(Color fg) {
    final value = _category;
    return _sheetSelector(
      fg: fg,
      label: 'Category',
      value: value?.name,
      icon: Icon(
        value == null
            ? (_isReminder ? Icons.label_outline : Icons.touch_app_outlined)
            : _iconForCategory(value.icon),
        color: fg,
      ),
      onTap: _pickCategory,
    );
  }

  Widget _repeatField(Color fg) {
    final value = _repeat;
    return _sheetSelector(
      fg: fg,
      label: 'Repeat',
      value: value?.name,
      icon: Icon(
        (value == null || value.id == 0)
            ? Icons.remove_circle_outline
            : Icons.repeat,
        color: fg,
      ),
      onTap: _pickRepeat,
    );
  }

  Widget _swapButton(Color color, double scale) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: _swapAccounts,
      child: Container(
        width: 40 * scale,
        height: 40 * scale,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.18),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Icon(Icons.swap_horiz, size: 20 * scale, color: color),
      ),
    );
  }

  String get _heading {
    final edit = _editing;
    switch (widget.type) {
      case TransactionColorType.income:
        return edit ? 'Edit Income' : 'New Income';
      case TransactionColorType.expense:
        return edit ? 'Edit Expense' : 'New Expense';
      case TransactionColorType.transfer:
        return edit ? 'Edit Transfer' : 'Transfer Funds';
      case TransactionColorType.reminder:
        return edit ? 'Edit Reminder' : 'New Reminder';
    }
  }

  String get _buttonLabel {
    if (_editing) return 'Save Changes';
    switch (widget.type) {
      case TransactionColorType.transfer:
        return 'Transfer';
      case TransactionColorType.reminder:
        return 'Add Reminder';
      default:
        return 'Add Transaction';
    }
  }

  IconData get _buttonIcon {
    if (_editing) return Icons.save;
    switch (widget.type) {
      case TransactionColorType.transfer:
        return Icons.swap_horiz;
      case TransactionColorType.reminder:
        return Icons.notifications_active;
      default:
        return Icons.add;
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    final settings = AppSettings.instance;

    final typeColor = settings.transactionColor(widget.type);
    // Icons inside the fields. A reminder follows its Expense / Income pick.
    final fieldColor = _isReminder
        ? (_reminderIncome ? settings.incomeColor : settings.expenseColor)
        : typeColor;

    final scale = _fontScale(context).clamp(0.9, 1.3).toDouble();
    final noteHeight = 96 * scale;
    final amountStyle = TextStyle(color: fg, fontSize: 16);

    final amountField = TextField(
      controller: _amount,
      style: amountStyle,
      cursorColor: fg,
      maxLines: 1,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      decoration: _sheetDecoration(
        fg,
        label: 'Amount (${AppConstants.currencySymbol})',
        icon: Icon(Icons.payments_outlined, color: fieldColor),
      ),
    );

    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          primary: fg,
          onPrimary: bg,
          onSurface: fg,
          onSurfaceVariant: muted,
        ),
        textSelectionTheme: TextSelectionThemeData(cursorColor: fg),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            AppConstants.spaceSmMd,
            20,
            AppConstants.spaceMd,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: AppConstants.borderAlpha),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceSmMd),

              // Header: icon box tinted with the transaction color
              Row(
                children: [
                  Container(
                    width: 40 * scale,
                    height: 40 * scale,
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: AppConstants.tintAlpha),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                    ),
                    child: Icon(widget.type.icon, color: typeColor),
                  ),
                  const SizedBox(width: AppConstants.spaceMd),
                  Text(
                    _heading,
                    style: base.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceMd),

              // Reminder: Expense | Income
              if (_isReminder) ...[
                Row(
                  children: [
                    _kindButton(
                      selected: !_reminderIncome,
                      color: settings.expenseColor,
                      fg: fg,
                      icon: TransactionColorType.expense.icon,
                      label: 'Expense',
                      onTap: () => setState(() {
                        _reminderIncome = false;
                        _category = null;
                      }),
                    ),
                    const SizedBox(width: _sheetGap),
                    _kindButton(
                      selected: _reminderIncome,
                      color: settings.incomeColor,
                      fg: fg,
                      icon: TransactionColorType.income.icon,
                      label: 'Income',
                      onTap: () => setState(() {
                        _reminderIncome = true;
                        _category = null;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: _sheetGap),
              ],

              // Title
              TextField(
                controller: _title,
                style: amountStyle,
                cursorColor: fg,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: _sheetDecoration(
                  fg,
                  label: 'Title',
                  icon: Icon(Icons.title, color: fg),
                ),
              ),
              const SizedBox(height: _sheetGap),

              // Transfer: From | swap | To
              if (_isTransfer) ...[
                Row(
                  children: [
                    Expanded(child: _accountField(fg, label: 'From')),
                    const SizedBox(width: AppConstants.spaceSm),
                    _swapButton(typeColor, scale),
                    const SizedBox(width: AppConstants.spaceSm),
                    Expanded(child: _accountField(fg, label: 'To', isTo: true)),
                  ],
                ),
                const SizedBox(height: _sheetGap),
              ],

              // Amount (+ Date, or full width on a reminder)
              if (_isReminder)
                amountField
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: amountField),
                    const SizedBox(width: _sheetGap),
                    Expanded(flex: 2, child: _dateField(fg, fieldColor, due: false)),
                  ],
                ),
              const SizedBox(height: _sheetGap),

              // Income / Expense: Category | Account
              if (!_isTransfer && !_isReminder) ...[
                Row(
                  children: [
                    Expanded(child: _categoryField(fg)),
                    const SizedBox(width: _sheetGap),
                    Expanded(child: _accountField(fg)),
                  ],
                ),
                const SizedBox(height: _sheetGap),
              ],

              // Reminder: Category | Due date, then Repeat | Account
              if (_isReminder) ...[
                Row(
                  children: [
                    Expanded(child: _categoryField(fg)),
                    const SizedBox(width: _sheetGap),
                    Expanded(child: _dateField(fg, fieldColor, due: true)),
                  ],
                ),
                const SizedBox(height: _sheetGap),
                Row(
                  children: [
                    Expanded(child: _repeatField(fg)),
                    const SizedBox(width: _sheetGap),
                    Expanded(child: _accountField(fg)),
                  ],
                ),
                const SizedBox(height: _sheetGap),
              ],

              // Image (square, left) + Note
              SizedBox(
                height: noteHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: noteHeight, child: _imageTile(fg, noteHeight)),
                    const SizedBox(width: _sheetGap),
                    Expanded(
                      // The note icon sits in the top left corner of the
                      // box, so it is drawn on top of the field instead
                      // of being the field's (centered) prefix icon.
                      child: Stack(
                        children: [
                          TextField(
                            controller: _note,
                            style: amountStyle,
                            cursorColor: fg,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: _sheetDecoration(
                              fg,
                              label: 'Note (optional)',
                              alignLabelWithHint: true,
                              contentPadding: const EdgeInsets.fromLTRB(
                                48,
                                15,
                                AppConstants.spaceMd,
                                15,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 12,
                            top: 12,
                            child: IgnorePointer(
                              child: Icon(
                                Icons.sticky_note_2_outlined,
                                color: fg,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: AppConstants.spaceSm),
                Text(
                  _error!,
                  style: base.textTheme.bodySmall?.copyWith(color: fg),
                ),
              ],
              const SizedBox(height: AppConstants.spaceMd),

              // Main button, colored with the transaction color
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _canSave ? _save : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: typeColor,
                    foregroundColor: AppTheme.onColor(typeColor),
                  ),
                  icon: Icon(_buttonIcon),
                  label: Text(_buttonLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Date + time pop-up
// ------------------------------------------------------------------

/// Calendar pop-up with a time row under it. [color] is the accent
/// (the transaction color). Returns the chosen date and time, or null.
Future<DateTime?> _showDateTimeDialog(
  BuildContext context, {
  required DateTime initial,
  required Color color,
}) {
  return showDialog<DateTime>(
    context: context,
    barrierColor: AppConstants.popupBarrier,
    builder: (_) => _DateTimeDialog(initial: initial, color: color),
  );
}

class _DateTimeDialog extends StatefulWidget {
  final DateTime initial;
  final Color color;
  const _DateTimeDialog({required this.initial, required this.color});

  @override
  State<_DateTimeDialog> createState() => _DateTimeDialogState();
}

class _DateTimeDialogState extends State<_DateTimeDialog> {
  static const double _wheelItem = 20; // height of one number on a wheel

  late DateTime _month; // first day of the month being shown
  late DateTime _selected; // date only
  late int _hour;
  late int _minute;
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _month = DateTime(i.year, i.month);
    _selected = DateTime(i.year, i.month, i.day);
    _hour = i.hour;
    _minute = i.minute;
    _hourController = FixedExtentScrollController(initialItem: _hour);
    _minuteController = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _shiftMonth(int by) =>
      setState(() => _month = DateTime(_month.year, _month.month + by));

  String get _weekdayText => _weekdayShort[_selected.weekday - 1];

  String get _dateText =>
      '${_monthNames[_selected.month - 1].substring(0, 3)} '
      '${_selected.day}, ${_selected.year}';

  Widget _pill(Color fg, {required Widget child, VoidCallback? onTap}) {
    final color = widget.color;
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }

  Widget _cell(int day, int daysInMonth, Color fg) {
    final color = widget.color;
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 38);
    final date = DateTime(_month.year, _month.month, day);
    final selected = date == _selected;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selected = date),
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.2) : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 16,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? color : fg,
            ),
          ),
        ),
      ),
    );
  }

  /// One wheel (hours or minutes). It loops, snaps to a number, and the
  /// number in the middle is drawn bigger and in the accent color.
  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required int current,
    required Color fg,
    required ValueChanged<int> onChanged,
  }) {
    final color = widget.color;
    return SizedBox(
      width: 46,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: _wheelItem,
        diameterRatio: 6, // large = flat, like a rectangle
        perspective: 0.002,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (index) {
          HapticFeedback.selectionClick();
          onChanged(index % count);
        },
        childDelegate: ListWheelChildLoopingListDelegate(
          children: [
            for (var i = 0; i < count; i++)
              Center(
                child: Text(
                  _two(i),
                  style: TextStyle(
                    fontSize: i == current ? 20 : 16,
                    fontWeight:
                        i == current ? FontWeight.w700 : FontWeight.w400,
                    color: i == current
                        ? color
                        : fg.withValues(alpha: AppConstants.mutedAlpha),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Rectangular box with the Hour : Minute wheels, a band marks the
  /// number that will be used.
  Widget _timeWheel(Color fg) {
    final color = widget.color;
    return Container(
      height: _wheelItem * 3,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Container(
              height: _wheelItem,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          SizedBox(
            height: _wheelItem * 3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _wheel(
                  controller: _hourController,
                  count: 24,
                  current: _hour,
                  fg: fg,
                  onChanged: (v) => setState(() => _hour = v),
                ),
                Text(
                  ':',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                _wheel(
                  controller: _minuteController,
                  count: 60,
                  current: _minute,
                  fg: fg,
                  onChanged: (v) => setState(() => _minute = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;
    final color = widget.color;
    final theme = Theme.of(context);

    final lead = DateTime(_month.year, _month.month, 1).weekday - 1; // Mon = 0
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    const rows = 6;

    return Dialog(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // < October 2026 >
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.chevron_left, color: fg),
                  onPressed: () => _shiftMonth(-1),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${_monthNames[_month.month - 1]} ${_month.year}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.chevron_right, color: fg),
                  onPressed: () => _shiftMonth(1),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceSm),
            // M T W T F S S
            Row(
              children: [
                for (final letter in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                  Expanded(
                    child: Center(
                      child: Text(
                        letter,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: fg.withValues(alpha: AppConstants.mutedAlpha),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceSm),
            // Days
            for (var r = 0; r < rows; r++)
              Row(
                children: [
                  for (var c = 0; c < 7; c++)
                    Expanded(child: _cell(r * 7 + c - lead + 1, days, fg)),
                ],
              ),
            const SizedBox(height: AppConstants.spaceMd),
            // Bottom of the calendar: chosen date (left) and the time
            // wheels (right).
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: _wheelItem * 3,
                    child: _pill(
                      fg,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _weekdayText,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: color.withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _dateText,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppConstants.spaceSm),
                _timeWheel(fg),
              ],
            ),
            const SizedBox(height: AppConstants.spaceMd),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                      foregroundColor: color,
                      side: BorderSide(color: color.withValues(alpha: 0.5)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: _sheetGap),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                      backgroundColor: color,
                      foregroundColor: AppTheme.onColor(color),
                    ),
                    onPressed: () => Navigator.of(context).pop(
                      DateTime(
                        _selected.year,
                        _selected.month,
                        _selected.day,
                        _hour,
                        _minute,
                      ),
                    ),
                    child: const Text(
                      'Apply',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Analytics charts (no packages: plain CustomPainters)
// ------------------------------------------------------------------

Color _sliceColor(int i) {
  const hues = <double>[210, 15, 140, 45, 280, 180, 330, 75, 240, 100];
  return HSLColor.fromAHSL(1, hues[i % hues.length], 0.65, 0.58).toColor();
}

/// The color saved for a category, or an automatic one.
Color _categoryColor(int? saved, int fallbackIndex) =>
    saved != null ? Color(saved) : _sliceColor(fallbackIndex);

String _short(double v) {
  final a = v.abs();
  final s = a >= 1e6
      ? '${(a / 1e6).toStringAsFixed(1)}M'
      : a >= 1e3
          ? '${(a / 1e3).toStringAsFixed(1)}k'
          : a < 10
              ? a.toStringAsFixed(a == a.roundToDouble() ? 0 : 1)
              : a.toStringAsFixed(0);
  return v < 0 ? '-$s' : s;
}

/// Rounds a value up to a "nice" axis maximum (1, 2, 5 or 10 x 10^n).
double _niceMax(double v) {
  if (v <= 0) return 1;
  final exp = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  final f = v / exp;
  final nice = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 5 ? 5 : 10));
  return nice * exp;
}

void _paintCentered(Canvas c, String s, double cx, double y, TextStyle st,
    {double maxWidth = 60}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: st),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  tp.paint(c, Offset(cx - tp.width / 2, y));
}

/// Text whose right edge is at [right] and which is centered on [cy].
void _paintRight(Canvas c, String s, double right, double cy, TextStyle st) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: st),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  tp.paint(c, Offset(right - tp.width, cy - tp.height / 2));
}

/// Soft rounded card around a chart. [title] is drawn INSIDE the card.
Widget _chartCard(Color fg, Widget child, {String? title, Color? dot}) =>
    Container(
      padding: const EdgeInsets.all(AppConstants.spaceSmMd),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) _chartTitle(fg, title, dot: dot),
          child,
        ],
      ),
    );

/// ALL graph title texts live here. Edit the strings to rename them.
class _ChartTitles {
  _ChartTitles._();

  /// Bar graph (default analytics + Net view)
  static const accounts = 'Account Analytics';

  /// Two-line graph (default views)
  static const overTime = 'Balance Over Time';

  /// GitHub-style day boxes
  static const transactionCount = 'Transaction Count';

  /// Two-column pie (default views)
  static const byCategory = 'Category Analytics';

  /// Column headings inside the two-column pie / line legend
  static const incomeColumn = 'Income';
  static const expenseColumn = 'Expense';

  /// Income-only / expense-only views ([label] = 'Income' or 'Expense')
  static String kindOverTime(String label) => '$label Over Time';
  static String kindByCategory(String label) => '$label by Category';

  /// Category pop-up line graph: "AccTitle | Category" when it was opened
  /// from an account, just the category name otherwise.
  static String category(String? account, String category) =>
      account == null ? category : '$account | $category';
}

Widget _chartTitle(Color fg, String text, {Color? dot}) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, AppConstants.spaceSm),
      child: Row(
        children: [
          if (dot != null) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );

/// Income / expense of one account in the chosen range.
class _AccountStat {
  final _AccountCardData account;
  final double income;
  final double expense;
  const _AccountStat(this.account, this.income, this.expense);
  double get net => income - expense;
}

List<_AccountStat> _accountStats(
  List<_AccountCardData> accounts,
  List<HistoryEntry> entries,
) {
  return [
    for (final a in accounts)
      _AccountStat(
        a,
        entries
            .where((e) => e.type == 'income' && e.accountId == a.id)
            .fold(0.0, (s, e) => s + e.amount),
        entries
            .where((e) => e.type == 'expense' && e.accountId == a.id)
            .fold(0.0, (s, e) => s + e.amount),
      ),
  ];
}

/// Stats grouped by account type, in the same type order as the Finance
/// screen (saved order first, new types last by id).
List<List<_AccountStat>> _groupStats(
  List<_AccountStat> stats,
  List<int> typeOrder,
) {
  final groups = <int, List<_AccountStat>>{};
  for (final s in stats) {
    groups.putIfAbsent(s.account.typeId, () => []).add(s);
  }
  final rank = {for (var i = 0; i < typeOrder.length; i++) typeOrder[i]: i};
  const last = 1 << 30;
  final ids = groups.keys.toList()
    ..sort((a, b) {
      final ra = rank[a] ?? last;
      final rb = rank[b] ?? last;
      return ra != rb ? ra.compareTo(rb) : a.compareTo(b);
    });
  return [for (final id in ids) groups[id]!];
}

// ---------- Bars: income + expense per account, grouped by type ----------

/// Fixed left axis (numbers). It does not scroll with the bars.
class _BarsAxisPainter extends CustomPainter {
  final double maxV;
  final Color fg;
  const _BarsAxisPainter(this.maxV, this.fg);

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height - _AccountBarsPainter.top - _AccountBarsPainter.bottom;
    final base = _AccountBarsPainter.top + h;
    final st = TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.65));
    for (var i = 0; i <= 4; i++) {
      _paintRight(canvas, _short(maxV * i / 4), size.width - 6,
          base - h * i / 4, st);
    }
  }

  @override
  bool shouldRepaint(_BarsAxisPainter o) => true;
}

class _AccountBarsPainter extends CustomPainter {
  final List<List<_AccountStat>> groups;
  final double maxV;
  final Color income, expense, fg;
  static const double slot = 64, top = 22, bottom = 44;
  const _AccountBarsPainter(
      this.groups, this.maxV, this.income, this.expense, this.fg);

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height - top - bottom;
    final base = top + h;

    final grid = Paint()
      ..color = fg.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (var i = 1; i <= 4; i++) {
      final y = base - h * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = fg.withValues(alpha: 0.35)
        ..strokeWidth = 1.5,
    );

    const bw = 14.0;
    final nameStyle = TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.85));
    final typeStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: fg.withValues(alpha: 0.55),
    );
    final sep = Paint()
      ..color = fg.withValues(alpha: 0.2)
      ..strokeWidth = 1;

    var index = 0;
    for (var g = 0; g < groups.length; g++) {
      final group = groups[g];
      final gx = slot * index;
      if (g > 0) canvas.drawLine(Offset(gx, top), Offset(gx, size.height), sep);

      for (final st in group) {
        final cx = slot * index + slot / 2;

        void bar(double x, double v, Color c) {
          final bh = v / maxV * h;
          if (bh > 0) {
            canvas.drawRRect(
              RRect.fromRectAndCorners(
                Rect.fromLTWH(x, base - bh, bw, bh),
                topLeft: const Radius.circular(5),
                topRight: const Radius.circular(5),
              ),
              Paint()..color = c,
            );
            _paintCentered(
              canvas,
              _short(v),
              x + bw / 2,
              base - bh - 13,
              TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: c,
              ),
              maxWidth: 34,
            );
          }
        }

        bar(cx - bw - 1, st.income, income);
        bar(cx + 1, st.expense, expense);
        _paintCentered(canvas, st.account.name, cx, base + 5, nameStyle,
            maxWidth: slot - 4);
        index++;
      }

      // Account type name, centered under its accounts.
      _paintCentered(
        canvas,
        group.first.account.typeName.toUpperCase(),
        gx + group.length * slot / 2,
        base + 24,
        typeStyle,
        maxWidth: group.length * slot - 8,
      );
    }
  }

  @override
  bool shouldRepaint(_AccountBarsPainter o) => true;
}

class _AccountBars extends StatelessWidget {
  final List<List<_AccountStat>> groups;
  final Color fg;
  const _AccountBars({required this.groups, required this.fg});

  Widget _legend(Color c, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  fontSize: 11, color: fg.withValues(alpha: 0.8))),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    var count = 0;
    var m = 0.0;
    for (final g in groups) {
      for (final st in g) {
        count++;
        m = math.max(m, math.max(st.income, st.expense));
      }
    }
    final maxV = _niceMax(m);
    const height = 220.0, axisW = 40.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              _legend(s.incomeColor, 'Income'),
              const SizedBox(width: AppConstants.spaceMd),
              _legend(s.expenseColor, 'Expense'),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, c) {
            final w = math.max(
                c.maxWidth - axisW, count * _AccountBarsPainter.slot);
            return Row(
              children: [
                SizedBox(
                  width: axisW,
                  height: height,
                  child: CustomPaint(painter: _BarsAxisPainter(maxV, fg)),
                ),
                Expanded(
                  child: SizedBox(
                    height: height,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: CustomPaint(
                        size: Size(w, height),
                        painter: _AccountBarsPainter(
                          groups,
                          maxV,
                          s.incomeColor,
                          s.expenseColor,
                          fg,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---------- Net view: bars + accounts grouped by type ----------

class _AccountsOverview extends StatelessWidget {
  final List<_AccountStat> stats;
  final List<int> typeOrder;
  final Color fg;
  final ValueChanged<_AccountCardData> onOpen;
  const _AccountsOverview({
    required this.stats,
    required this.typeOrder,
    required this.fg,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final theme = Theme.of(context);
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    String money(double v) =>
        Utils.formatCurrency(v, symbol: AppConstants.currencySymbol);

    if (stats.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppConstants.spaceXl),
        child: Center(child: Text('No accounts', style: TextStyle(color: muted))),
      );
    }

    final groups = _groupStats(stats, typeOrder);

    Widget row(_AccountStat st) => Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceMd,
            vertical: 3,
          ),
          child: Material(
            color: _lighter(AppTheme.accentOf(context).background, 0.08),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onOpen(st.account),
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.spaceSmMd),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: fg.withValues(alpha: AppConstants.tintAlpha),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        _iconForCategory(st.account.categoryIcon),
                        size: 22,
                        color: fg,
                      ),
                    ),
                    const SizedBox(width: AppConstants.spaceSmMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            st.account.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: fg,
                            ),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                Icon(Icons.arrow_upward,
                                    size: 11, color: s.incomeColor),
                                Text(money(st.income),
                                    style: TextStyle(
                                        fontSize: 12, color: s.incomeColor)),
                                const SizedBox(width: 10),
                                Icon(Icons.arrow_downward,
                                    size: 11, color: s.expenseColor),
                                Text(money(st.expense),
                                    style: TextStyle(
                                        fontSize: 12, color: s.expenseColor)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppConstants.spaceSm),
                    Text(
                      money(st.net),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: st.net >= 0 ? s.incomeColor : s.expenseColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    Widget groupHeader(List<_AccountStat> g) {
      final first = g.first.account;
      final net = g.fold(0.0, (sum, st) => sum + st.net);
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spaceMd + 4,
          AppConstants.spaceMd,
          AppConstants.spaceMd + 4,
          AppConstants.spaceSm,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(_iconForType(first.typeName, first.typeIcon),
                    size: 16, color: muted),
                const SizedBox(width: AppConstants.spaceSm),
                Expanded(
                  child: Text(
                    first.typeName.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: muted,
                    ),
                  ),
                ),
                Text(
                  money(net),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: net >= 0 ? s.incomeColor : s.expenseColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceXs),
            // Line that separates the type from its accounts.
            Divider(
              height: 1,
              thickness: 1,
              color: fg.withValues(alpha: AppConstants.dividerAlpha),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceMd,
            AppConstants.spaceMd,
            AppConstants.spaceMd,
            0,
          ),
          child: _chartCard(
            fg,
            _AccountBars(groups: groups, fg: fg),
            title: _ChartTitles.accounts,
          ),
        ),
        for (final g in groups) ...[
          groupHeader(g),
          for (final st in g) row(st),
        ],
      ],
    );
  }
}

// ---------- Line graph (axes + tappable vertices, 1 or 2 lines) ----------

const double _lcLeft = 46, _lcRight = 14, _lcTop = 20, _lcBottom = 28;

/// One line of the graph.
class _Series {
  final String kind; // income | expense
  final List<HistoryEntry> entries; // oldest first, not empty
  final Color color;
  const _Series(this.kind, this.entries, this.color);
}

/// Shared scale of all lines on one graph.
/// [zs] / [ze] = visible part of the time axis (0.0 - 1.0).
/// [vMin] / [vMax] = visible part of the amount axis (real values).
class _LineGeo {
  final double t0, span, vMin, vMax, zs, ze;
  const _LineGeo(this.t0, this.span, this.vMin, this.vMax, this.zs, this.ze);

  factory _LineGeo.of(
    List<_Series> series, [
    double zs = 0,
    double ze = 1,
    double ys = 0,
    double ye = 1,
  ]) {
    var lo = double.infinity;
    var hi = -double.infinity;
    var top = 0.0;
    for (final s in series) {
      for (final e in s.entries) {
        final t = e.date.millisecondsSinceEpoch.toDouble();
        lo = math.min(lo, t);
        hi = math.max(hi, t);
        top = math.max(top, e.amount);
      }
    }
    final span = hi - lo;
    // When zoomed sideways (and not zoomed vertically), the amount axis
    // fits the points that are visible.
    var visTop = 0.0;
    if (span > 0 && (ze - zs) < 1) {
      for (final s in series) {
        for (final e in s.entries) {
          final f = (e.date.millisecondsSinceEpoch - lo) / span;
          if (f >= zs && f <= ze) visTop = math.max(visTop, e.amount);
        }
      }
    }
    final yZoomed = ye - ys < 0.999;
    // When zoomed vertically the full scale stays fixed so the user's
    // up / down position doesn't jump around while panning sideways.
    final base = _niceMax(!yZoomed && visTop > 0 ? visTop : top);
    return _LineGeo(lo, span, base * ys, base * ye, zs, ze);
  }

  Offset at(HistoryEntry e, Size size) {
    final w = size.width - _lcLeft - _lcRight;
    final h = size.height - _lcTop - _lcBottom;
    final t = e.date.millisecondsSinceEpoch.toDouble();
    final x = span == 0 ? w / 2 : ((t - t0) / span - zs) / (ze - zs) * w;
    final y = (e.amount - vMin) / (vMax - vMin) * h;
    return Offset(_lcLeft + x, _lcTop + h - y);
  }
}

/// Axis number: more decimals when the zoomed range gets very small.
String _axisLabel(double v, double range) {
  if (range < 10) return v.toStringAsFixed(2);
  if (range < 100) return v.toStringAsFixed(1);
  return _short(v);
}

class _LinePainter extends CustomPainter {
  final List<_Series> series;
  final Color fg;
  final Color border; // outline of the node bubble
  final (int, int)? selected; // (line, point)
  final double zs, ze; // visible part of the time axis
  final double ys, ye; // visible part of the amount axis
  const _LinePainter(
    this.series,
    this.fg,
    this.border,
    this.selected,
    this.zs,
    this.ze,
    this.ys,
    this.ye,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final geo = _LineGeo.of(series, zs, ze, ys, ye);
    final w = size.width - _lcLeft - _lcRight;
    final h = size.height - _lcTop - _lcBottom;
    final axis = TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.65));
    final grid = Paint()
      ..color = fg.withValues(alpha: 0.12)
      ..strokeWidth = 1;

    // Side axis: amounts (of the visible part).
    final vRange = geo.vMax - geo.vMin;
    for (var i = 0; i <= 4; i++) {
      final y = _lcTop + h * i / 4;
      canvas.drawLine(
        Offset(_lcLeft, y),
        Offset(size.width - _lcRight, y),
        grid,
      );
      _paintRight(
        canvas,
        _axisLabel(geo.vMin + vRange * (4 - i) / 4, vRange),
        _lcLeft - 6,
        y,
        axis,
      );
    }

    // Bottom axis: dates of the visible part only.
    final visT0 = geo.t0 + geo.span * zs;
    final visSpan = geo.span * (ze - zs);
    final showTime = visSpan > 0 && visSpan < 3 * 24 * 3600 * 1000;
    final ticks = geo.span == 0 ? 1 : 4;
    for (var k = 0; k < ticks; k++) {
      final x = geo.span == 0 ? _lcLeft + w / 2 : _lcLeft + w * k / (ticks - 1);
      final d = DateTime.fromMillisecondsSinceEpoch(
        (visT0 + (geo.span == 0 ? 0 : visSpan * k / (ticks - 1))).round(),
      );
      canvas.drawLine(
        Offset(x, _lcTop + h),
        Offset(x, _lcTop + h + 4),
        Paint()
          ..color = fg.withValues(alpha: 0.4)
          ..strokeWidth = 1,
      );
      final label = showTime
          ? '${_monthNames[d.month - 1].substring(0, 3)} ${d.day} '
              '${_two(d.hour)}:${_two(d.minute)}'
          : '${_monthNames[d.month - 1].substring(0, 3)} ${d.day}';
      _paintCentered(
        canvas,
        label,
        x.clamp(32.0, size.width - 32).toDouble(),
        _lcTop + h + 8,
        axis,
        maxWidth: 64,
      );
    }

    // Lines and vertices are clipped to the plot area (needed for zoom).
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        _lcLeft - 8,
        _lcTop - 6,
        size.width - _lcRight + 8,
        _lcTop + h + 2,
      ),
    );

    final baseY = _lcTop + h;
    for (final s in series) {
      final pts = [for (final e in s.entries) geo.at(e, size)];
      if (pts.length > 1) {
        final fill = Path()..moveTo(pts.first.dx, baseY);
        for (final p in pts) {
          fill.lineTo(p.dx, p.dy);
        }
        fill
          ..lineTo(pts.last.dx, baseY)
          ..close();
        canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                s.color.withValues(alpha: series.length > 1 ? 0.2 : 0.35),
                s.color.withValues(alpha: 0.0),
              ],
            ).createShader(Rect.fromLTWH(0, _lcTop, size.width, h)),
        );
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (final p in pts.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = s.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }

    // Vertices.
    for (var si = 0; si < series.length; si++) {
      final s = series[si];
      for (var i = 0; i < s.entries.length; i++) {
        final p = geo.at(s.entries[i], size);
        final sel = selected == (si, i);
        if (sel) {
          canvas.drawCircle(p, 11, Paint()..color = s.color.withValues(alpha: 0.25));
        }
        canvas.drawCircle(p, sel ? 6 : 4, Paint()..color = s.color);
        canvas.drawCircle(p, sel ? 3 : 1.8, Paint()..color = fg.withValues(alpha: 0.9));
      }
    }
    canvas.restore();

    // Bubble of the selected vertex (only while that point is visible).
    final sel = selected;
    if (sel != null && sel.$1 < series.length) {
      final s = series[sel.$1];
      if (sel.$2 < s.entries.length) {
        final e = s.entries[sel.$2];
        final p = geo.at(e, size);
        if (p.dx < _lcLeft - 1 || p.dx > size.width - _lcRight + 1) return;
        if (p.dy < _lcTop - 1 || p.dy > _lcTop + h + 1) return;
        final on = AppTheme.onColor(s.color);
        final amountTp = TextPainter(
          text: TextSpan(
            text: Utils.formatCurrency(e.amount, symbol: AppConstants.currencySymbol),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: on),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final dateTp = TextPainter(
          text: TextSpan(
            text: _fmtLong(e.date),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: on.withValues(alpha: 0.85),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
                const padX = 8.0, padY = 4.0, gap = 12.0;
        final bw = math.max(amountTp.width, dateTp.width) + padX * 2;
        final bh = amountTp.height + dateTp.height + padY * 2 + 1;
        final left = (p.dx - bw / 2).clamp(0.0, size.width - bw).toDouble();
        final bTop = math.max(0.0, p.dy - gap - bh);

        // Bubble + arrow as one shape, filled, then outlined.
        final bubble = Path.combine(
          PathOperation.union,
          Path()
            ..addRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(left, bTop, bw, bh),
                const Radius.circular(8),
              ),
            ),
          Path()
            ..moveTo(p.dx - 5, bTop + bh)
            ..lineTo(p.dx + 5, bTop + bh)
            ..lineTo(p.dx, bTop + bh + 6)
            ..close(),
        );
        canvas.drawPath(bubble, Paint()..color = s.color);
        canvas.drawPath(
          bubble,
          Paint()
            ..color = border
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeJoin = StrokeJoin.round,
        );

        amountTp.paint(canvas, Offset(left + (bw - amountTp.width) / 2, bTop + padY));
        dateTp.paint(
          canvas,
          Offset(left + (bw - dateTp.width) / 2, bTop + padY + amountTp.height + 1),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter o) => true;
}

/// A scale recognizer that takes over a ONE-finger drag as soon as the
/// graph is zoomed. That way dragging up / down moves the zoomed graph
/// instead of scrolling the page behind it. While the graph is not zoomed
/// a one-finger drag still scrolls the page, and two fingers always zoom.
class _ChartScaleRecognizer extends ScaleGestureRecognizer {
  _ChartScaleRecognizer({required this.canPan});
  final bool Function() canPan;

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    if (event is PointerMoveEvent && canPan()) {
      resolvePointer(event.pointer, GestureDisposition.accepted);
    }
  }
}

class _TxLineChart extends StatefulWidget {
  final List<_Series> series; // not empty
  final Color fg;

  /// When given, the Income / Expense legend chips open that kind.
  final ValueChanged<String>? onOpenKind;

  /// Links the line graph with the Transaction Count boxes:
  /// a pressed box picks a node, a pressed node picks the box.
  final _DayLink? link;
  const _TxLineChart({
    required this.series,
    required this.fg,
    this.onOpenKind,
    this.link,
  });

  @override
  State<_TxLineChart> createState() => _TxLineChartState();
}

class _TxLineChartState extends State<_TxLineChart> {
  static const double _minWindow = 0.02; // closest zoom (2% of the dates)
  static const double _minWindowY = 0.02; // closest zoom (2% of the amounts)

  (int, int)? _selected;

  // Visible part of the time axis (0.0 - 1.0). 0 -> 1 = not zoomed.
  double _zs = 0;
  double _ze = 1;

  // Visible part of the amount axis (0.0 = bottom, 1.0 = top).
  double _ys = 0;
  double _ye = 1;

  // Values saved when a pinch / drag starts.
  double _startWindow = 1;
  double _startFocalData = 0;
  double _startWindowY = 1;
  double _startFocalDataY = 0;

  bool get _zoomedX => _ze - _zs < 0.999;
  bool get _zoomedY => _ye - _ys < 0.999;
  bool get _zoomed => _zoomedX || _zoomedY;

  @override
  void initState() {
    super.initState();
    final day = widget.link?.day;
    _selected = day == null ? _latest() : _pickForDay(day);
    widget.link?.addListener(_onLink);
  }

  @override
  void dispose() {
    widget.link?.removeListener(_onLink);
    super.dispose();
  }

  (int, int)? _latest() {
    (int, int)? latest;
    DateTime? latestDate;
    for (var si = 0; si < widget.series.length; si++) {
      final entries = widget.series[si].entries;
      for (var pi = 0; pi < entries.length; pi++) {
        final date = entries[pi].date;
        if (latestDate == null || date.isAfter(latestDate)) {
          latestDate = date;
          latest = (si, pi);
        }
      }
    }
    return latest;
  }

  /// The highest-amount point of that day (income or expense, whichever is
  /// higher), or null when the day has no point on this graph.
  (int, int)? _pickForDay(DateTime day) {
    (int, int)? best;
    var bestAmount = -1.0;
    for (var si = 0; si < widget.series.length; si++) {
      final list = widget.series[si].entries;
      for (var pi = 0; pi < list.length; pi++) {
        final e = list[pi];
        if (_dateOnly(e.date) == day && e.amount > bestAmount) {
          bestAmount = e.amount;
          best = (si, pi);
        }
      }
    }
    return best;
  }

  /// Keeps the current node if it is already on [day], else the day's
  /// highest point.
  (int, int)? _resolveDay(DateTime day) {
    final cur = _selected;
    if (cur != null &&
        cur.$1 < widget.series.length &&
        cur.$2 < widget.series[cur.$1].entries.length &&
        _dateOnly(widget.series[cur.$1].entries[cur.$2].date) == day) {
      return cur;
    }
    return _pickForDay(day);
  }

  /// The link changed (a count box was pressed or unpressed).
  void _onLink() {
    if (!mounted) return;
    final day = widget.link?.day;
    if (day == null) {
      if (_selected != null) setState(() => _selected = null);
      return;
    }
    final next = _resolveDay(day);
    if (next != _selected) setState(() => _selected = next);
  }

  /// Deselects the node and the matching count box.
  void _deselect() {
    setState(() => _selected = null);
    widget.link?.set(null);
  }

  @override
  void didUpdateWidget(_TxLineChart old) {
    super.didUpdateWidget(old);
    if (old.link != widget.link) {
      old.link?.removeListener(_onLink);
      widget.link?.addListener(_onLink);
    }
    final day = widget.link?.day;
    if (day != null) {
      _selected = _resolveDay(day);
      return;
    }
    // Only fix a selection that no longer exists. A deselected graph
    // stays deselected.
    final sel = _selected;
    if (sel != null &&
        (sel.$1 >= widget.series.length ||
            sel.$2 >= widget.series[sel.$1].entries.length)) {
      _selected = _latest();
    }
  }

  // ---------- Zoom ----------

  double _plotFraction(double dx, double width) {
    final w = width - _lcLeft - _lcRight;
    return ((dx - _lcLeft) / w).clamp(0.0, 1.0).toDouble();
  }

  /// 0.0 = bottom of the plot, 1.0 = top of the plot.
  double _plotFractionY(double dy, double height) {
    final h = height - _lcTop - _lcBottom;
    return (1 - (dy - _lcTop) / h).clamp(0.0, 1.0).toDouble();
  }

  void _onScaleStart(ScaleStartDetails d, Size size) {
    _startWindow = _ze - _zs;
    _startFocalData =
        _zs + _plotFraction(d.localFocalPoint.dx, size.width) * _startWindow;
    _startWindowY = _ye - _ys;
    _startFocalDataY =
        _ys + _plotFractionY(d.localFocalPoint.dy, size.height) * _startWindowY;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    // Sideways: horizontalScale. Up / down: verticalScale.
    // (A normal pinch moves both, a vertical pinch only the second.)
    final newW =
        (_startWindow / d.horizontalScale).clamp(_minWindow, 1.0).toDouble();
    final fx = _plotFraction(d.localFocalPoint.dx, size.width);
    final newS =
        (_startFocalData - fx * newW).clamp(0.0, 1.0 - newW).toDouble();

    final newWY =
        (_startWindowY / d.verticalScale).clamp(_minWindowY, 1.0).toDouble();
    final fy = _plotFractionY(d.localFocalPoint.dy, size.height);
    final newSY =
        (_startFocalDataY - fy * newWY).clamp(0.0, 1.0 - newWY).toDouble();

    setState(() {
      _zs = newS;
      _ze = newS + newW;
      _ys = newSY;
      _ye = newSY + newWY;
    });
  }

  /// Zoom around the middle of the visible part (buttons, sideways).
  void _zoomBy(double factor) {
    final w = _ze - _zs;
    final newW = (w / factor).clamp(_minWindow, 1.0).toDouble();
    final mid = (_zs + _ze) / 2;
    final newS = (mid - newW / 2).clamp(0.0, 1.0 - newW).toDouble();
    setState(() {
      _zs = newS;
      _ze = newS + newW;
    });
  }

  void _resetZoom() => setState(() {
        _zs = 0;
        _ze = 1;
        _ys = 0;
        _ye = 1;
      });

  /// Tap on the plot: select the nearest node (and pop up its box on the
  /// Transaction Count), or deselect when no node is near.
  void _onTapAt(Offset pos, Size size) {
    final geo = _LineGeo.of(widget.series, _zs, _ze, _ys, _ye);
    (int, int)? best;
    var bestD = 28.0;
    for (var si = 0; si < widget.series.length; si++) {
      final list = widget.series[si].entries;
      for (var pi = 0; pi < list.length; pi++) {
        final dist = (geo.at(list[pi], size) - pos).distance;
        if (dist < bestD) {
          bestD = dist;
          best = (si, pi);
        }
      }
    }
    if (best != null) {
      setState(() => _selected = best);
      final e = widget.series[best.$1].entries[best.$2];
      widget.link?.set(_dateOnly(e.date));
    } else {
      _deselect();
    }
  }

  Widget _zoomButton(IconData icon, VoidCallback? onTap) {
    final c = widget.fg.withValues(alpha: onTap == null ? 0.25 : 0.85);
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: SizedBox(
        width: 30,
        height: 28,
        child: Icon(icon, size: 18, color: c),
      ),
    );
  }

  Widget _legend(_Series s) {
    final label = s.kind == 'income'
        ? _ChartTitles.incomeColumn
        : _ChartTitles.expenseColumn;
    final open = widget.onOpenKind;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: open == null ? null : () => open(s.kind),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: widget.fg.withValues(alpha: 0.85),
              ),
            ),
            if (open != null)
              Icon(Icons.chevron_right,
                  size: 14, color: widget.fg.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.fg;
    final border = Color.alphaBlend(
      fg.withValues(alpha: 0.06),
      _lighter(AppTheme.accentOf(context).background),
    );
    final selIdx = _selected;
    final sel =
        selIdx == null ? null : widget.series[selIdx.$1].entries[selIdx.$2];

    // Tapping anywhere on this chart that is not a node, a legend chip or
    // a zoom button deselects the node (and the count box).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _deselect,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Legend (left) + zoom buttons (right)
          Row(
            children: [
              Expanded(
                child: (widget.series.length > 1 || widget.onOpenKind != null)
                    ? Wrap(
                        spacing: 8,
                        children: [for (final s in widget.series) _legend(s)],
                      )
                    : const SizedBox.shrink(),
              ),
              _zoomButton(Icons.remove, _zoomedX ? () => _zoomBy(0.5) : null),
              _zoomButton(Icons.add, () => _zoomBy(2)),
              // Resets both the sideways and the up / down zoom.
              _zoomButton(Icons.zoom_out_map, _zoomed ? _resetZoom : null),
            ],
          ),
          LayoutBuilder(
            builder: (context, c) {
              final size = Size(c.maxWidth, 210);
              return RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: <Type, GestureRecognizerFactory>{
                  // Pinch = zoom (sideways, up / down or both).
                  // Drag = move the zoomed graph in any direction.
                  _ChartScaleRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          _ChartScaleRecognizer>(
                    () => _ChartScaleRecognizer(canPan: () => _zoomed),
                    (_ChartScaleRecognizer r) {
                      r.onStart =
                          (ScaleStartDetails d) => _onScaleStart(d, size);
                      r.onUpdate =
                          (ScaleUpdateDetails d) => _onScaleUpdate(d, size);
                    },
                  ),
                  TapGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          TapGestureRecognizer>(
                    () => TapGestureRecognizer(),
                    (r) {
                      r.onTapUp = (d) => _onTapAt(d.localPosition, size);
                    },
                  ),
                  DoubleTapGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          DoubleTapGestureRecognizer>(
                    () => DoubleTapGestureRecognizer(),
                    (r) {
                      r.onDoubleTap = _resetZoom;
                    },
                  ),
                },
                child: CustomPaint(
                  size: size,
                  painter: _LinePainter(
                    widget.series,
                    fg,
                    border,
                    _selected,
                    _zs,
                    _ze,
                    _ys,
                    _ye,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppConstants.spaceSm),
          Text(
            sel == null
                ? 'Tap a point to see its amount'
                : (sel.categoryName == null
                    ? sel.title
                    : '${sel.title}  •  ${sel.categoryName}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg.withValues(alpha: AppConstants.mutedAlpha),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Pie / donut by category (uses the saved category colors) ----------

class _PiePainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  const _PiePainter(this.values, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold(0.0, (a, b) => a + b);
    if (total <= 0) return;
    final stroke = size.width * 0.2;
    final arcRect = (Offset.zero & size).deflate(stroke / 2);
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * math.pi;
      canvas.drawArc(
        arcRect,
        start,
        values.length == 1 ? sweep : math.max(sweep - 0.03, 0.001),
        false,
        Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_PiePainter o) => true;
}

/// One category's total inside a list of transactions.
class _CatSlice {
  final int? id;
  final String name;
  final String? icon;
  Color color;
  double sum;
  _CatSlice(this.id, this.name, this.icon, this.color, this.sum);
}

/// Totals per category, biggest first, with the saved (or automatic) colors.
List<_CatSlice> _slices(List<HistoryEntry> entries) {
  final map = <int?, _CatSlice>{};
  final saved = <int?, int?>{};
  for (final e in entries) {
    final c = map[e.categoryId] ??= _CatSlice(
        e.categoryId, e.categoryName ?? 'Other', e.categoryIcon, Colors.grey, 0);
    c.sum += e.amount;
    saved[e.categoryId] = e.categoryColor;
  }
  final list = map.values.toList()..sort((a, b) => b.sum.compareTo(a.sum));
  for (var i = 0; i < list.length; i++) {
    list[i].color = _categoryColor(saved[list[i].id], i);
  }
  return list;
}

Widget _donut(List<_CatSlice> slices, Color fg, double size) {
  final total = slices.fold(0.0, (a, b) => a + b.sum);
  final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
  return SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _PiePainter(
        [for (final s in slices) s.sum],
        [for (final s in slices) s.color],
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: size * 0.24),
          child: FittedBox(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Total', style: TextStyle(fontSize: 10, color: muted)),
                Text(
                  Utils.formatCurrency(total,
                      symbol: AppConstants.currencySymbol),
                  style: TextStyle(fontWeight: FontWeight.w800, color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Full donut + the list of categories. Tap a row to open that category.
class _CategoryPie extends StatelessWidget {
  final List<HistoryEntry> entries;
  final Color fg;
  final ValueChanged<_CatSlice>? onOpen;
  const _CategoryPie({required this.entries, required this.fg, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final slices = _slices(entries);
    final total = slices.fold(0.0, (a, b) => a + b.sum);

    return Column(
      children: [
        _donut(slices, fg, 180),
        const SizedBox(height: AppConstants.spaceMd),
        for (final c in slices)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onOpen == null ? null : () => onOpen!(c),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c.color.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_iconForCategory(c.icon),
                        size: 17, color: c.color),
                  ),
                  const SizedBox(width: AppConstants.spaceSmMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${c.name}  ${(c.sum / total * 100).toStringAsFixed(0)}%',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: c.sum / total,
                            minHeight: 5,
                            color: c.color,
                            backgroundColor: c.color.withValues(alpha: 0.15),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceSmMd),
                  Text(
                    Utils.formatCurrency(c.sum,
                        symbol: AppConstants.currencySymbol),
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800, color: fg),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------- Transaction Count (GitHub-style day boxes) ----------

/// Transactions of one day, split by kind.
class _DayCount {
  int income = 0, expense = 0, transfer = 0, reminder = 0;

  int get total => income + expense + transfer + reminder;

  int of(String kind) {
    switch (kind) {
      case 'income':
        return income;
      case 'expense':
        return expense;
      case 'transfer':
        return transfer;
      default:
        return reminder;
    }
  }

  /// The kind with the most transactions that day.
  /// Ties: income, expense, transfer, reminder (in that order).
  String get dominant {
    var best = 'income';
    var most = income;
    if (expense > most) {
      best = 'expense';
      most = expense;
    }
    if (transfer > most) {
      best = 'transfer';
      most = transfer;
    }
    if (reminder > most) {
      best = 'reminder';
    }
    return best;
  }
}

const List<String> _countKinds = ['income', 'expense', 'transfer', 'reminder'];
const Map<String, String> _countKindLabels = {
  'income': 'Income',
  'expense': 'Expense',
  'transfer': 'Transfer',
  'reminder': 'Reminder',
};

Color _countKindColor(String kind) {
  final s = AppSettings.instance;
  switch (kind) {
    case 'income':
      return s.incomeColor;
    case 'expense':
      return s.expenseColor;
    case 'transfer':
      return s.transferColor;
    default:
      return s.reminderColor;
  }
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Links the Transaction Count boxes to the line graph: the day that was
/// pressed (null = none).
class _DayLink extends ChangeNotifier {
  DateTime? _day;
  DateTime? get day => _day;
  void set(DateTime? d) {
    if (_day == d) return;
    _day = d;
    notifyListeners();
  }
}

/// Owns one [_DayLink] for the graphs built inside it.
class _DayLinked extends StatefulWidget {
  final Widget Function(_DayLink link) builder;
  const _DayLinked({required this.builder});

  @override
  State<_DayLinked> createState() => _DayLinkedState();
}

class _DayLinkedState extends State<_DayLinked> {
  final _link = _DayLink();

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_link);
}

/// The Transaction Count card.
/// [kind] null = every kind (colored by the busiest kind of each day),
/// 'income' / 'expense' = only that kind. [reminders] are only counted
/// when [kind] is null. [link] picks the matching point on a line graph.
Widget _txCountCard({
  required List<HistoryEntry> entries,
  required _HistoryRange range,
  required Color fg,
  List<ReminderItem> reminders = const [],
  String? kind,
  _DayLink? link,
}) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    // Tap anywhere on the card that isn't a day box: deselect.
    onTap: link == null ? null : () => link.set(null),
    child: _chartCard(
      fg,
      _TxCountGraph(
        entries: entries,
        reminders: reminders,
        range: range,
        kind: kind,
        fg: fg,
        link: link,
      ),
      title: _ChartTitles.transactionCount,
      dot: kind == null ? null : _countKindColor(kind),
    ),
  );
}

class _TxCountPainter extends CustomPainter {
  static const double gap = 3; // space between boxes
  static const double pad = 3; // room for the glow
  static const double headH = 16; // month names / weekday letters row

  final Map<int, _DayCount> days;
  final DateTime gridStart; // UTC, the Monday of the first week
  final int weeks, firstIdx, lastIdx, maxTotal;
  final double cellW, cellH;
  final bool horizontal; // true = calendar (days go left to right)
  final String? kind;
  final Color fg;
  final Color border; 
  final int? selected;

  const _TxCountPainter({
    required this.days,
    required this.gridStart,
    required this.weeks,
    required this.firstIdx,
    required this.lastIdx,
    required this.maxTotal,
    required this.cellW,
    required this.cellH,
    required this.horizontal,
    required this.kind,
    required this.fg,
    required this.border,
    required this.selected,
  });

  /// Top left corner of the box of day [idx].
  static Offset origin(int idx, double cellW, double cellH, bool horizontal) {
    final week = idx ~/ 7;
    final wd = idx % 7;
    final col = horizontal ? wd : week;
    final row = horizontal ? week : wd;
    return Offset(pad + col * (cellW + gap), headH + row * (cellH + gap));
  }

  /// The day under a tap (null = no day there).
  static int? indexAt(
    Offset p,
    double cellW,
    double cellH,
    bool horizontal,
    int weeks,
    int firstIdx,
    int lastIdx,
  ) {
    final x = p.dx - pad;
    final y = p.dy - headH;
    if (x < 0 || y < 0) return null;
    final col = (x / (cellW + gap)).floor();
    final row = (y / (cellH + gap)).floor();
    final week = horizontal ? row : col;
    final wd = horizontal ? col : row;
    if (wd >= 7 || week >= weeks) return null;
    final idx = week * 7 + wd;
    if (idx < firstIdx || idx > lastIdx) return null;
    return idx;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(math.min(cellW, cellH) * 0.22);
    final labelStyle = TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.65));

    // Header: weekday letters (calendar) or month names (week columns).
    if (horizontal) {
      const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
      for (var i = 0; i < 7; i++) {
        _paintCentered(
          canvas,
          letters[i],
          pad + i * (cellW + gap) + cellW / 2,
          2,
          labelStyle,
          maxWidth: cellW,
        );
      }
    } else {
      var lastLabelCol = -10;
      int? lastMonth;
      for (var col = 0; col < weeks; col++) {
        final idx = math.max(col * 7, firstIdx);
        if (idx > lastIdx) break;
        final d = gridStart.add(Duration(days: idx));
        if (d.month != lastMonth) {
          lastMonth = d.month;
          if (col - lastLabelCol >= 3) {
            lastLabelCol = col;
            final tp = TextPainter(
              text: TextSpan(
                text: _monthNames[d.month - 1].substring(0, 3),
                style: labelStyle,
              ),
              textDirection: TextDirection.ltr,
              maxLines: 1,
            )..layout();
            tp.paint(
              canvas,
              Offset(pad + col * (cellW + gap), (headH - tp.height) / 2),
            );
          }
        }
      }
    }

    const alphas = [0.0, 0.35, 0.55, 0.78, 1.0];
    for (var idx = firstIdx; idx <= lastIdx; idx++) {
      final o = origin(idx, cellW, cellH, horizontal);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(o.dx, o.dy, cellW, cellH),
        radius,
      );
      final c = days[idx];
      if (c == null || c.total == 0) {
        canvas.drawRRect(rect, Paint()..color = fg.withValues(alpha: 0.08));
      } else {
        final color = _countKindColor(kind ?? c.dominant);
        final level = (c.total / maxTotal * 4).ceil().clamp(1, 4).toInt();
        final a = alphas[level];
        // Glow, then the box.
        canvas.drawRRect(
          rect,
          Paint()
            ..color = color.withValues(alpha: 0.55 * a)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: a));
      }
      // Day number inside the box (calendar layout only).
      if (horizontal && cellH >= 16) {
        final day = gridStart.add(Duration(days: idx)).day;
        final tp = TextPainter(
          text: TextSpan(
            text: '$day',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: fg.withValues(alpha: 0.75),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(o.dx + (cellW - tp.width) / 2, o.dy + (cellH - tp.height) / 2),
        );
      }
      if (idx == selected) {
        canvas.drawRRect(
          rect.inflate(1.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = fg,
        );
      }
    }

    // Bubble of the selected box (same look as the line graph nodes).
    final sel = selected;
    if (sel != null) {
      final c = days[sel];
      final n = c?.total ?? 0;
      final color = n == 0 ? fg : _countKindColor(kind ?? c!.dominant);
      final on = AppTheme.onColor(color);
      final u = gridStart.add(Duration(days: sel));
      final date = DateTime(u.year, u.month, u.day);
      final countTp = TextPainter(
        text: TextSpan(
          text: '$n transaction${n == 1 ? '' : 's'}',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: on),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dateTp = TextPainter(
        text: TextSpan(
          text: _fmtLong(date),
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: on.withValues(alpha: 0.85),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      const padX = 8.0, padY = 4.0, arrow = 6.0, gapB = 2.0;
      final bw = math.max(countTp.width, dateTp.width) + padX * 2;
      final bh = countTp.height + dateTp.height + padY * 2 + 1;
      final o = origin(sel, cellW, cellH, horizontal);
      final cx = o.dx + cellW / 2;
      final left = (cx - bw / 2).clamp(0.0, math.max(0.0, size.width - bw)).toDouble();

      var bTop = o.dy - gapB - arrow - bh;
      final above = bTop >= 0; // no room on top: open below the box
      if (!above) bTop = o.dy + cellH + gapB + arrow;

      final bubble = Path.combine(
        PathOperation.union,
        Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(left, bTop, bw, bh),
              const Radius.circular(8),
            ),
          ),
        above
            ? (Path()
              ..moveTo(cx - 5, bTop + bh)
              ..lineTo(cx + 5, bTop + bh)
              ..lineTo(cx, bTop + bh + arrow)
              ..close())
            : (Path()
              ..moveTo(cx - 5, bTop)
              ..lineTo(cx + 5, bTop)
              ..lineTo(cx, bTop - arrow)
              ..close()),
      );
      canvas.drawPath(bubble, Paint()..color = color);
      canvas.drawPath(
        bubble,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );

      countTp.paint(canvas, Offset(left + (bw - countTp.width) / 2, bTop + padY));
      dateTp.paint(
        canvas,
        Offset(left + (bw - dateTp.width) / 2, bTop + padY + countTp.height + 1),
      );
    }
  }

  @override
  bool shouldRepaint(_TxCountPainter o) => true;
}

class _TxCountGraph extends StatefulWidget {
  final List<HistoryEntry> entries;
  final List<ReminderItem> reminders;
  final _HistoryRange range;
  final String? kind; // null = all kinds
  final Color fg;
  final _DayLink? link;
  const _TxCountGraph({
    required this.entries,
    required this.reminders,
    required this.range,
    required this.kind,
    required this.fg,
    this.link,
  });

  @override
  State<_TxCountGraph> createState() => _TxCountGraphState();
}

class _TxCountGraphState extends State<_TxCountGraph> {
  static const double _minCell = 12;
  static const double _maxCell = 26;
  static const double _labelW = 22;

  DateTime? _selectedDate; // date only

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.link?.day;
    widget.link?.addListener(_onLink);
  }

  @override
  void dispose() {
    widget.link?.removeListener(_onLink);
    super.dispose();
  }

  void _onLink() {
    if (!mounted) return;
    final d = widget.link?.day;
    if (d != _selectedDate) setState(() => _selectedDate = d);
  }

  void _clearSelection() {
    setState(() => _selectedDate = null);
    widget.link?.set(null);
  }

  @override
  void didUpdateWidget(_TxCountGraph old) {
      if (old.link != widget.link) {
      old.link?.removeListener(_onLink);
      widget.link?.addListener(_onLink);
    }
    super.didUpdateWidget(old);
    // A new date range: forget the picked box (and the line graph pick).
    if (!identical(old.range, widget.range) && _selectedDate != null) {
      _selectedDate = null;
      final link = widget.link;
      WidgetsBinding.instance.addPostFrameCallback((_) => link?.set(null));
    }
  }

  void _onTap(
    Offset p,
    double cellW,
    double cellH,
    bool horizontal,
    int weeks,
    int firstIdx,
    int lastIdx,
    DateTime gridStart,
  ) {
    final idx = _TxCountPainter.indexAt(
      p,
      cellW,
      cellH,
      horizontal,
      weeks,
      firstIdx,
      lastIdx,
    );
    if (idx == null) {
      _clearSelection();
      return;
    }
    final u = gridStart.add(Duration(days: idx));
    final date = DateTime(u.year, u.month, u.day);
    final next = _selectedDate == date ? null : date;
    setState(() => _selectedDate = next);
    // The line graph picks that day's point (or nothing).
    widget.link?.set(next);
  }

  Widget _weekdayLabels(double cell, Color fg) {
    const names = {0: 'M', 2: 'W', 4: 'F'};
    final style = TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.65));
    return SizedBox(
      width: _labelW,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: _TxCountPainter.headH),
          for (var r = 0; r < 7; r++) ...[
            SizedBox(
              height: cell,
              child: Align(
                alignment: Alignment.centerLeft,
                child: names.containsKey(r) ? Text(names[r]!, style: style) : null,
              ),
            ),
            if (r < 6) const SizedBox(height: _TxCountPainter.gap),
          ],
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  @override
  Widget build(BuildContext context) {
    final fg = widget.fg;
    final border = Color.alphaBlend(
      fg.withValues(alpha: 0.06),
      _lighter(AppTheme.accentOf(context).background),
    );
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    final kind = widget.kind;
    final today = _dateOnly(DateTime.now());

    // Everything that counts: (day, kind).
    final items = <(DateTime, String)>[];
    for (final e in widget.entries) {
      if (kind == null || e.type == kind) items.add((_dateOnly(e.date), e.type));
    }
    if (kind == null) {
      for (final r in widget.reminders) {
        items.add((_dateOnly(r.dueDate), 'reminder'));
      }
    }

    // First and last day shown.
    final r = widget.range;
    DateTime first;
    DateTime last;
    if (r.isAll) {
      first = today;
      last = today;
      for (final i in items) {
        if (i.$1.isBefore(first)) first = i.$1;
        if (i.$2 != 'reminder' && i.$1.isAfter(last)) last = i.$1;
      }
    } else {
      first = _dateOnly(r.start);
      last = _dateOnly(r.end);
      if (last.isBefore(first)) last = first;
    }

    // Day / Week / Month fill the card as a calendar.
    final horizontal = r.period == _Period.day ||
        r.period == _Period.week ||
        r.period == _Period.month;

    // Weeks (Monday first) are numbered from the Monday of the first day.
    final gridStart = DateTime.utc(first.year, first.month, first.day)
        .subtract(Duration(days: first.weekday - 1));
    final firstIdx = first.weekday - 1;
    final lastIdx =
        DateTime.utc(last.year, last.month, last.day).difference(gridStart).inDays;
    final weeks = lastIdx ~/ 7 + 1;

    final days = <int, _DayCount>{};
    for (final i in items) {
      final idx = DateTime.utc(i.$1.year, i.$1.month, i.$1.day)
          .difference(gridStart)
          .inDays;
      if (idx < firstIdx || idx > lastIdx) continue;
      final c = days.putIfAbsent(idx, _DayCount.new);
      switch (i.$2) {
        case 'income':
          c.income++;
        case 'expense':
          c.expense++;
        case 'transfer':
          c.transfer++;
        default:
          c.reminder++;
      }
    }
    var maxTotal = 1;
    for (final c in days.values) {
      maxTotal = math.max(maxTotal, c.total);
    }

    // Selected day.
    int? selIdx;
    final sd = _selectedDate;
    if (sd != null) {
      final i = DateTime.utc(sd.year, sd.month, sd.day).difference(gridStart).inDays;
      if (i >= firstIdx && i <= lastIdx) selIdx = i;
    }

    // Legend: normal = all kinds. A box selected = only the kinds on that
    // day, with their counts, most to least.
    final selCount = selIdx == null ? null : days[selIdx];
    final legendKinds = <String>[
      for (final k in _countKinds)
        if (selIdx == null || (selCount?.of(k) ?? 0) > 0) k,
    ];
    if (selCount != null) {
      legendKinds.sort((a, b) {
        final c = selCount.of(b).compareTo(selCount.of(a));
        return c != 0 ? c : _countKinds.indexOf(a).compareTo(_countKinds.indexOf(b));
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Colors legend (default views only)
        if (kind == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, AppConstants.spaceSm),
            child: legendKinds.isEmpty
                ? Text(
                    'No transactions',
                    style: TextStyle(fontSize: 11, color: muted),
                  )
                : Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    children: [
                      for (final k in legendKinds)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _dot(_countKindColor(k)),
                            const SizedBox(width: 5),
                            Text(
                              selCount == null
                                  ? _countKindLabels[k]!
                                  : '${_countKindLabels[k]} ${selCount.of(k)}',
                              style: TextStyle(fontSize: 11, color: muted),
                            ),
                          ],
                        ),
                    ],
                  ),
          ),
        LayoutBuilder(
          builder: (context, c) {
            const gap = _TxCountPainter.gap;
            const pad = _TxCountPainter.pad;
            final labelW = horizontal ? 0.0 : _labelW;
            final avail = c.maxWidth - labelW;

            double cellW, cellH, gridW, gridH;
            if (horizontal) {
              // 7 columns that fill the whole card.
              cellW = (avail - pad * 2 - 6 * gap) / 7;
              cellH = (cellW * 0.7).clamp(18.0, 34.0).toDouble();
              gridW = avail;
              gridH = _TxCountPainter.headH +
                  weeks * cellH +
                  (weeks - 1) * gap +
                  pad +
                  // Room for the bubble that opens below the first row.
                  (weeks < 3 ? 46 : 0);
            } else {
              final fit = (avail - pad * 2 - (weeks - 1) * gap) / weeks;
              cellW = cellH = fit.clamp(_minCell, _maxCell).toDouble();
              gridW = weeks * cellW + (weeks - 1) * gap + pad * 2;
              gridH = _TxCountPainter.headH + 7 * cellH + 6 * gap + pad;
            }

            final grid = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _onTap(
                d.localPosition,
                cellW,
                cellH,
                horizontal,
                weeks,
                firstIdx,
                lastIdx,
                gridStart,
              ),
              child: CustomPaint(
                size: Size(gridW, gridH),
                painter: _TxCountPainter(
                  days: days,
                  gridStart: gridStart,
                  weeks: weeks,
                  firstIdx: firstIdx,
                  lastIdx: lastIdx,
                  maxTotal: maxTotal,
                  cellW: cellW,
                  cellH: cellH,
                  horizontal: horizontal,
                  kind: kind,
                  fg: fg,
                  border: border,
                  selected: selIdx,
                ),
              ),
            );

            if (horizontal) return grid;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _weekdayLabels(cellH, fg),
                Expanded(
                  // Long ranges scroll sideways, starting at the newest days.
                  child: gridW > avail
                      ? SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: grid,
                        )
                      : Align(alignment: Alignment.centerLeft, child: grid),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---------- Default (all-graphs) cards ----------

/// Two lines (income + expense). Tap a legend chip to open that kind.
Widget _dualLineCard(
  List<HistoryEntry> entries,
  Color fg,
  ValueChanged<String> onOpenKind, {
  _DayLink? link,
}) {
  final s = AppSettings.instance;
  List<HistoryEntry> of(String k) => [
        for (final e in entries)
          if (e.type == k) e,
      ]..sort((a, b) => a.date.compareTo(b.date));
  final inc = of('income');
  final exp = of('expense');
  final series = [
    if (inc.isNotEmpty) _Series('income', inc, s.incomeColor),
    if (exp.isNotEmpty) _Series('expense', exp, s.expenseColor),
  ];
  return _chartCard(
    fg,
    series.isEmpty
        ? SizedBox(
            height: 80,
            width: double.infinity,
            child: Center(
              child: Text('No data',
                  style: TextStyle(
                      color: fg.withValues(alpha: AppConstants.mutedAlpha))),
            ),
          )
        : _TxLineChart(
            series: series,
            fg: fg,
            onOpenKind: onOpenKind,
            link: link,
          ),
    title: _ChartTitles.overTime,
  );
}

/// Two columns: income categories | expense categories.
/// Tapping a column opens that kind's specific content.
Widget _dualPieCard(
  List<HistoryEntry> entries,
  Color fg,
  ValueChanged<String> onOpen,
) {
  final s = AppSettings.instance;
  final muted = fg.withValues(alpha: AppConstants.mutedAlpha);

  Widget column(String kind, String label, Color color) {
    final slices = _slices([
      for (final e in entries)
        if (e.type == kind) e,
    ]);
    final total = slices.fold(0.0, (a, b) => a + b.sum);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onOpen(kind),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 8),
            if (slices.isEmpty)
              SizedBox(
                height: 112,
                child: Center(
                    child: Text('No data', style: TextStyle(color: muted))),
              )
            else ...[
              _donut(slices, fg, 112),
              const SizedBox(height: 8),
              for (final c in slices.take(5))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: c.color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: fg),
                        ),
                      ),
                      Text(
                        '${(c.sum / total * 100).toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),
              if (slices.length > 5)
                Text('+${slices.length - 5} more',
                    style: TextStyle(fontSize: 11, color: muted)),
            ],
          ],
        ),
      ),
    );
  }

  return _chartCard(
    fg,
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        column('income', _ChartTitles.incomeColumn, s.incomeColor),
        const SizedBox(width: 12),
        column('expense', _ChartTitles.expenseColumn, s.expenseColor),
      ],
    ),
    title: _ChartTitles.byCategory,
  );
}

/// Default content of the main Analytics pop-up: account bar graph (NO
/// account list under it), two-line graph, two-column pie.
/// Pressing the bars opens the Net view, pressing the other graphs opens
/// income / expense.
class _AnalyticsDefault extends StatelessWidget {
  final List<_AccountStat> stats;
  final List<int> typeOrder;
  final List<HistoryEntry> entries;
  final List<ReminderItem> reminders;
  final _HistoryRange range;
  final Color fg;
  final ValueChanged<String> onOpen; // 'net' | 'income' | 'expense'
  const _AnalyticsDefault({
    required this.stats,
    required this.typeOrder,
    required this.entries,
    required this.reminders,
    required this.range,
    required this.fg,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    return _DayLinked(
      builder: (link) => Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onOpen('net'),
              child: _chartCard(
                fg,
                stats.isEmpty
                    ? SizedBox(
                        height: 80,
                        child: Center(
                          child: Text('No accounts',
                              style: TextStyle(color: muted)),
                        ),
                      )
                    : _AccountBars(
                        groups: _groupStats(stats, typeOrder), fg: fg),
                title: _ChartTitles.accounts,
              ),
            ),
            const SizedBox(height: AppConstants.spaceMd),
            _txCountCard(
              entries: entries,
              reminders: reminders,
              range: range,
              fg: fg,
              link: link,
            ),
            const SizedBox(height: AppConstants.spaceMd),
            _dualLineCard(entries, fg, onOpen, link: link),
            const SizedBox(height: AppConstants.spaceMd),
            _dualPieCard(entries, fg, onOpen),
          ],
        ),
      ),
    );
  }
}

/// Line graph + donut for one kind ('income' | 'expense').
/// [entries] can be in any order and any type; they are filtered here.
/// [onOpenCategory] makes the category rows open the category pop-up.
class _KindCharts extends StatelessWidget {
  final List<HistoryEntry> entries;
  final String kind;
  final _HistoryRange range;
  final Color fg;
  final ValueChanged<_CatSlice>? onOpenCategory;
  const _KindCharts({
    required this.entries,
    required this.kind,
    required this.range,
    required this.fg,
    this.onOpenCategory,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final color = kind == 'income' ? s.incomeColor : s.expenseColor;
    final list = [
      for (final e in entries)
        if (e.type == kind) e,
    ]..sort((a, b) => a.date.compareTo(b.date));
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppConstants.spaceXl),
        child: Center(
          child: Text('No data',
              style: TextStyle(
                  color: fg.withValues(alpha: AppConstants.mutedAlpha))),
        ),
      );
    }
    final label = kind == 'income' ? 'Income' : 'Expense';
    return _DayLinked(
      builder: (link) => Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _txCountCard(
              entries: list,
              range: range,
              kind: kind,
              fg: fg,
              link: link,
            ),
            const SizedBox(height: AppConstants.spaceMd),
            _chartCard(
              fg,
              _TxLineChart(
                series: [_Series(kind, list, color)],
                fg: fg,
                link: link,
              ),
              title: _ChartTitles.kindOverTime(label),
              dot: color,
            ),
            const SizedBox(height: AppConstants.spaceMd),
            _chartCard(
              fg,
              _CategoryPie(entries: list, fg: fg, onOpen: onOpenCategory),
              title: _ChartTitles.kindByCategory(label),
              dot: color,
            ),
          ],
        ),
      ),
    );
  }
}