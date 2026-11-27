import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../database/helper.dart';
import '../constants.dart';
import '../failures.dart';
import '../themes.dart';
import 'settings.dart';
import 'trash.dart'; // showConfirmDialog

// ------------------------------------------------------------------
// Data
// ------------------------------------------------------------------

const Object _keep = Object();

/// One identification card: a picture of its front and of its back.
class IdCard {
  final String id; // unique, used as the widget key
  final String? front;
  final String? back;
  final String name; // kept only, never displayed
  final String details; // kept only, never displayed
  const IdCard({
    required this.id,
    this.front,
    this.back,
    this.name = '',
    this.details = '',
  });

  IdCard copyWith({
    Object? front = _keep,
    Object? back = _keep,
    String? name,
    String? details,
  }) => IdCard(
    id: id,
    front: identical(front, _keep) ? this.front : front as String?,
    back: identical(back, _keep) ? this.back : back as String?,
    name: name ?? this.name,
    details: details ?? this.details,
  );

  List<String> get paths => [front, back].whereType<String>().toList();

  Map<String, Object?> toJson() => {
    'id': id,
    'front': front,
    'back': back,
    'name': name,
    'details': details,
  };
}

/// Everything the profile holds. Saved as one JSON value in the `settings`
/// table (key AppConstants.prefProfile), so it is part of backups.
class ProfileData {
  final String name;
  final String username;
  final String bio;
  final String? picture;
  final String? banner;
  final List<IdCard> ids;

  const ProfileData({
    this.name = '',
    this.username = '',
    this.bio = '',
    this.picture,
    this.banner,
    this.ids = const [],
  });

  static const ProfileData empty = ProfileData();

  /// Pass a value (or null to clear it) to change a picture. Leave it out
  /// to keep what is there.
  ProfileData copyWith({
    String? name,
    String? username,
    String? bio,
    Object? picture = _keep,
    Object? banner = _keep,
    List<IdCard>? ids,
  }) => ProfileData(
    name: name ?? this.name,
    username: username ?? this.username,
    bio: bio ?? this.bio,
    picture: identical(picture, _keep) ? this.picture : picture as String?,
    banner: identical(banner, _keep) ? this.banner : banner as String?,
    ids: ids ?? this.ids,
  );

  bool get isEmpty =>
      name.isEmpty &&
      username.isEmpty &&
      bio.isEmpty &&
      picture == null &&
      banner == null &&
      ids.isEmpty;

  /// Every picture file this profile points to.
  List<String> get paths => [
    picture,
    banner,
    for (final card in ids) ...card.paths,
  ].whereType<String>().toList();

  /// True when the picture file is really there.
  bool get hasPicture => picture != null && File(picture!).existsSync();

  Map<String, Object?> toJson() => {
    'name': name,
    'username': username,
    'bio': bio,
    'picture': picture,
    'banner': banner,
    'ids': [for (final card in ids) card.toJson()],
  };

  factory ProfileData.decode(String? raw) {
    if (raw == null) return empty;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return empty;
      String text(String k) => m[k] is String ? m[k] as String : '';
      String? pathOf(Object? v) => (v is String && v.isNotEmpty) ? v : null;

      final ids = <IdCard>[];
      final list = m['ids'];
      if (list is List) {
        for (final e in list) {
          if (e is Map && e['id'] is String) {
            ids.add(
              IdCard(
                id: e['id'] as String,
                front: pathOf(e['front']),
                back: pathOf(e['back']),
                name: e['name'] is String ? e['name'] as String : '',
                details: e['details'] is String ? e['details'] as String : '',
              ),
            );
          }
        }
      } else {
        // First version kept a single ID as idFront / idBack.
        final front = pathOf(m['idFront']);
        final back = pathOf(m['idBack']);
        if (front != null || back != null) {
          ids.add(IdCard(id: 'legacy', front: front, back: back));
        }
      }

      return ProfileData(
        name: text('name'),
        username: text('username'),
        bio: text('bio'),
        picture: pathOf(m['picture']),
        banner: pathOf(m['banner']),
        ids: ids,
      );
    } catch (_) {
      return empty;
    }
  }
}

/// The saved profile. Listens to the database, so it reloads after an
/// import or a reset.
class AppProfile extends ChangeNotifier {
  AppProfile._() {
    DatabaseHelper.instance.changes.addListener(load);
  }
  static final AppProfile instance = AppProfile._();

  ProfileData _data = ProfileData.empty;
  ProfileData get data => _data;
  int _version = 0; // lets a save win over a reload that started earlier

  /// Call before runApp (main.dart).
  Future<void> load() async {
    final started = _version;
    try {
      final all = await DatabaseHelper.instance.getAllSettings();
      if (started != _version) return;
      _data = ProfileData.decode(all[AppConstants.prefProfile]);
      notifyListeners();
    } catch (_) {}
  }

  /// Saves [next] and removes picture files nothing points to anymore.
  /// Throws when it can't be saved (the old profile stays).
  Future<void> save(ProfileData next) async {
    final old = _data;
    _version++;
    _data = next;
    notifyListeners();
    try {
      final db = DatabaseHelper.instance;
      if (next.isEmpty) {
        await db.removeSetting(AppConstants.prefProfile);
      } else {
        await db.setSetting(AppConstants.prefProfile, jsonEncode(next.toJson()));
      }
    } catch (_) {
      _data = old;
      notifyListeners();
      rethrow;
    } finally {
      _version++;
    }
    final kept = next.paths;
    for (final path in old.paths) {
      if (!kept.contains(path)) _deleteFile(path);
    }
  }
}

// ------------------------------------------------------------------
// Picture helpers
// ------------------------------------------------------------------

/// Copies a picked picture into the app's own profile folder.
Future<String> _storeImage(String source) async {
  final dir = await getApplicationDocumentsDirectory();
  final folder = Directory(p.join(dir.path, AppConstants.profileFolder));
  if (!await folder.exists()) await folder.create(recursive: true);
  final target = p.join(
    folder.path,
    '${DateTime.now().microsecondsSinceEpoch}${p.extension(source)}',
  );
  await File(source).copy(target);
  return target;
}

void _deleteFile(String? path) {
  if (path == null) return;
  try {
    File(path).delete();
  } catch (_) {}
}

enum _Pick { camera, gallery, remove, deleteId }

/// Result of choosing a picture. [path] null = the picture was removed.
class _Picked {
  final String? path;
  final bool deleteId;
  const _Picked(this.path, {this.deleteId = false});
}

/// Same design as the Type / Category picker of the account and
/// transaction pop-ups: a sheet with a title and a wrap of chips.
Future<_Pick?> _chooseSource(
  BuildContext context, {
  required String title,
  required bool canRemove,
  bool canDeleteId = false,
}) {
  final base = Theme.of(context);
  final accent = AppTheme.accentOf(context);
  final fg = accent.foreground;
  final red = AppSettings.instance.deleteColor;

  Widget chip(
    BuildContext ctx,
    IconData icon,
    String label,
    _Pick value, {
    Color? color,
  }) {
    final c = color ?? fg;
    return Material(
      color: fg.withValues(alpha: AppConstants.tintAlpha),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(ctx).pop(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceMd,
            vertical: AppConstants.spaceSmMd + 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: c),
              const SizedBox(width: AppConstants.spaceSm),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: c,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  return showModalBottomSheet<_Pick>(
    context: context,
    backgroundColor: accent.background,
    barrierColor: AppConstants.popupBarrier,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => SingleChildScrollView(
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
              chip(ctx, Icons.photo_camera_outlined, 'Camera', _Pick.camera),
              chip(ctx, Icons.photo_library_outlined, 'Gallery', _Pick.gallery),
              if (canRemove)
                chip(
                  ctx,
                  Icons.delete_outline,
                  'Remove picture',
                  _Pick.remove,
                  color: red,
                ),
              if (canDeleteId)
                chip(
                  ctx,
                  Icons.delete_forever,
                  'Delete ID',
                  _Pick.deleteId,
                  color: red,
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Asks Camera / Gallery (/ Remove), takes the picture and keeps a copy
/// inside the app. null = cancelled. Throws when the picture can't be used.
Future<_Picked?> _pickImage(
  BuildContext context, {
  required String title,
  required bool canRemove,
  bool canDeleteId = false,
  double maxWidth = 1600,
}) async {
  final choice = await _chooseSource(
    context,
    title: title,
    canRemove: canRemove,
    canDeleteId: canDeleteId,
  );
  if (choice == null) return null;
  if (choice == _Pick.remove) return const _Picked(null);
  if (choice == _Pick.deleteId) return const _Picked(null, deleteId: true);
  final file = await ImagePicker().pickImage(
    source: choice == _Pick.camera ? ImageSource.camera : ImageSource.gallery,
    imageQuality: 85,
    maxWidth: maxWidth,
  );
  if (file == null) return null;
  return _Picked(await _storeImage(file.path));
}

// ------------------------------------------------------------------
// Small widgets
// ------------------------------------------------------------------

/// Round profile picture (or a person icon when there is none).
class _AvatarImage extends StatelessWidget {
  final String? path;
  final double size;
  final Color fg;
  final Color bg;
  const _AvatarImage({
    required this.path,
    required this.size,
    required this.fg,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    final path = this.path;
    final placeholder = Icon(
      Icons.person,
      size: size * 0.55,
      color: fg.withValues(alpha: AppConstants.mutedAlpha),
    );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.alphaBlend(fg.withValues(alpha: 0.18), bg),
      ),
      child: (path != null && File(path).existsSync())
          ? Image.file(
              File(path),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            )
          : placeholder,
    );
  }
}

/// Round dark button that stays readable on top of a picture.
class _TopButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _TopButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const size = 40.0;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.black.withValues(alpha: 0.4),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: Colors.white, size: size * 0.55),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Side panel profile tile
// ------------------------------------------------------------------

/// The profile tile at the bottom of the side panel. Pressing it opens
/// the profile. It just says "Profile" until a profile picture AND a
/// username are set, then it shows the picture, username and name.
class ProfileDrawerTile extends StatelessWidget {
  final VoidCallback onTap;
  const ProfileDrawerTile({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppProfile.instance,
      builder: (context, _) {
        final theme = Theme.of(context);
        final accent = AppTheme.accentOf(context);
        final data = AppProfile.instance.data;
        final custom = data.hasPicture && data.username.isNotEmpty;

        // Same compact sizing as every other drawer tile.
        const density = VisualDensity(vertical: -2);

        if (!custom) {
          return ListTile(
            dense: true,
            visualDensity: density,
            minVerticalPadding: 0,
            leading: const Icon(Icons.person_outline),
            title: Text('Profile'.tr),
            onTap: onTap,
          );
        }

        return ListTile(
          dense: true,
          visualDensity: density,
          minVerticalPadding: 0,
          leading: _AvatarImage(
            path: data.picture,
            size: 28,
            fg: accent.foreground,
            bg: accent.background,
          ),
          title: Text(
            data.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: data.name.isNotEmpty
              ? Text(
                  data.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                )
              : null,
          onTap: onTap,
        );
      },
    );
  }
}

// ------------------------------------------------------------------
// Profile screen
// ------------------------------------------------------------------

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const double _bannerHeight = 250;
  static const double _overlap = 28; // how far the panel covers the banner
  static const double _avatarSize = 155;
  static const double _ring = 5;

  final _profile = AppProfile.instance;
  bool _idsOpen = true;

  Future<void> _edit() {
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
      builder: (_) => const _EditProfileSheet(),
    );
  }

  /// New ID (card == null) or edit an existing one.
  Future<void> _openIdSheet({IdCard? card}) {
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
      builder: (_) => _IdSheet(card: card),
    );
  }

  // ---------- Pieces ----------

  Widget _banner(ProfileData d, Color fg, Color bg) {
    final path = d.banner;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (path != null && File(path).existsSync())
          Image.file(
            File(path),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          )
        else
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.alphaBlend(fg.withValues(alpha: 0.35), bg), bg],
              ),
            ),
          ),
        // Soft shade so the back / edit buttons stay visible.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.35),
                Colors.transparent,
              ],
              stops: const [0, 0.5],
            ),
          ),
        ),
      ],
    );
  }

  /// "Identification" with the + button on the right side.
  Widget _idHeader(Color fg) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: fg.withValues(alpha: AppConstants.tintAlpha),
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
          ),
          child: Icon(Icons.badge_outlined, size: 20, color: fg),
        ),
        const SizedBox(width: AppConstants.spaceSmMd),
        Expanded(
          child: Text(
            'Identification'.tr,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.add, color: fg),
          tooltip: 'Add ID',
          onPressed: () => _openIdSheet(),
        ),
        // Up arrow = retract the section, down arrow = expand it.
        IconButton(
          icon: Icon(
            _idsOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            color: fg,
          ),
          tooltip: _idsOpen ? 'Hide IDs' : 'Show IDs',
          onPressed: () => setState(() => _idsOpen = !_idsOpen),
        ),
      ],
    );
  }

  Widget _content(ProfileData d, Color fg, Color bg) {
    final theme = Theme.of(context);
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    final hasName = d.name.isNotEmpty;
    final isBlank = !hasName && d.username.isEmpty && d.bio.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Name, @username and bio (the two lines under the circle).
        Text(
          hasName ? d.name : 'Your name',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: hasName ? fg : muted,
          ),
        ),
        if (d.username.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            '@${d.username}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: muted),
          ),
        ],
        if (d.bio.isNotEmpty) ...[
          const SizedBox(height: AppConstants.spaceSmMd),
          Text(
            d.bio,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.4,
              color: fg.withValues(alpha: 0.85),
            ),
          ),
        ],
        if (isBlank) ...[
          const SizedBox(height: AppConstants.spaceXs),
          Text(
            'Tap the pencil at the top to set up your profile.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: muted),
          ),
        ],
        const SizedBox(height: AppConstants.spaceLg),
        Divider(
          height: 1,
          thickness: 1,
          color: fg.withValues(alpha: AppConstants.dividerAlpha),
        ),
        const SizedBox(height: AppConstants.spaceSm),

        // ----- Identification -----
        _idHeader(fg),
        AnimatedSize(
          duration: AppConstants.pageAnimationDuration,
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: (_idsOpen && d.ids.isNotEmpty)
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppConstants.spaceSm),
                    for (final card in d.ids) ...[
                      _IdFlipCard(
                        key: ValueKey(card.id),
                        card: card,
                        fg: fg,
                        bg: bg,
                        onLongPress: () => _openIdSheet(card: card),
                      ),
                      const SizedBox(height: AppConstants.spaceMd),
                    ],
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;
    final d = _profile.data;

    final topInset = MediaQuery.viewPaddingOf(context).top;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final bannerH = topInset + _bannerHeight;
    final panelTop = bannerH - _overlap;
    const outer = _avatarSize;

    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: Stack(
          children: [
            // Banner
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: bannerH,
              child: _banner(d, fg, bg),
            ),
            // Main profile contents (rounded top, covers the banner's edge)
            Column(
              children: [
                SizedBox(height: panelTop),
                Container(
                  width: double.infinity,
                  constraints: BoxConstraints(
                    minHeight: math.max(0.0, c.maxHeight - panelTop),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    AppConstants.spaceLg - 4,
                    outer / 2 + AppConstants.spaceSmMd,
                    AppConstants.spaceLg - 4,
                    bottomInset + AppConstants.spaceXl,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: _content(d, fg, bg),
                ),
              ],
            ),
            // Profile picture: the circle on the edge of the banner
            Positioned(
              top: panelTop - outer / 2,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(_ring),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
                  child: _AvatarImage(
                    path: d.picture,
                    size: outer - _ring * 2,
                    fg: fg,
                    bg: bg,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 60,
        // No "Profile" text in the header: only back and edit.
        leading: Padding(
          padding: const EdgeInsets.only(left: AppConstants.spaceSmMd),
          child: Center(
            child: _TopButton(
              icon: Icons.arrow_back,
              label: 'Back',
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        actions: [
          _TopButton(icon: Icons.edit_outlined, label: 'Edit profile', onTap: _edit),
          const SizedBox(width: AppConstants.spaceSmMd),
        ],
      ),
      body: ListenableBuilder(
        listenable: _profile,
        builder: (context, _) => _body(context),
      ),
    );
  }
}

// ------------------------------------------------------------------
// ID card that flips (same flip as the account cards)
// ------------------------------------------------------------------

class _IdFlipCard extends StatefulWidget {
  final IdCard card;
  final Color fg;
  final Color bg;

  /// Long press on the card opens the Edit ID pop-up.
  final VoidCallback onLongPress;
  const _IdFlipCard({
    super.key,
    required this.card,
    required this.fg,
    required this.bg,
    required this.onLongPress,
  });

  @override
  State<_IdFlipCard> createState() => _IdFlipCardState();
}

class _IdFlipCardState extends State<_IdFlipCard>
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

  Widget _empty(bool back) {
    final muted = widget.fg.withValues(alpha: AppConstants.mutedAlpha);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.badge_outlined, size: 38, color: muted),
          const SizedBox(height: 6),
          Text(
            back ? 'No back picture yet' : 'No front picture yet',
            style: TextStyle(color: muted),
          ),
        ],
      ),
    );
  }

  Widget _face(String? path, bool back, double w, double h) {
    final fg = widget.fg;
    return Container(
      width: w,
      height: h,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Color.alphaBlend(fg.withValues(alpha: 0.12), widget.bg),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: (path != null && File(path).existsSync())
          ? Image.file(
              File(path),
              width: w,
              height: h,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _empty(back),
            )
          : _empty(back),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = w / AppConstants.cardRatio; // real ID-1 card ratio
        return SizedBox(
          width: w,
          height: h,
          child: GestureDetector(
            onTap: _flip,
            onLongPress: () {
              HapticFeedback.mediumImpact();
              widget.onLongPress();
            },
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
                      ? _face(widget.card.front, false, w, h)
                      : Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateY(math.pi),
                          child: _face(widget.card.back, true, w, h),
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

// ------------------------------------------------------------------
// Edit profile pop-up (built like the Edit Account sheet)
// ------------------------------------------------------------------

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet();

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  static const double _fieldRadius = 4;
  static const double _sidePad = 20;
  static const double _gap = 12;
  static const double _bannerHeight = 120;
  static const double _avatarSize = 84;
  static const int _nameMax = 30;
  static const int _usernameMax = 20;
  static const int _usernameMin = 3;
  static const int _bioMax = 120;

  final _name = TextEditingController();
  final _username = TextEditingController();
  final _bio = TextEditingController();

  String? _picture;
  String? _banner;
  final List<String> _staged = []; // pictures picked in this pop-up
  bool _saving = false;
  bool _didSave = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final d = AppProfile.instance.data;
    _name.text = d.name;
    _username.text = d.username;
    _bio.text = d.bio;
    _picture = d.picture;
    _banner = d.banner;
  }

  @override
  void dispose() {
    // Pictures picked but never saved are not kept.
    if (!_didSave) {
      for (final path in _staged) {
        _deleteFile(path);
      }
    }
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _change({required bool banner}) async {
    final current = banner ? _banner : _picture;
    try {
      final picked = await _pickImage(
        context,
        title: banner ? 'Banner picture' : 'Profile picture',
        canRemove: current != null,
        maxWidth: banner ? 1600 : 800,
      );
      if (picked == null) return;
      if (!mounted) {
        _deleteFile(picked.path);
        return;
      }
      // A picture picked earlier in this pop-up and replaced again.
      if (current != null && _staged.remove(current)) _deleteFile(current);
      final path = picked.path;
      if (path != null) _staged.add(path);
      setState(() {
        if (banner) {
          _banner = path;
        } else {
          _picture = path;
        }
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t get that image.');
    }
  }

  Future<void> _save() async {
    final username = _username.text.trim();
    if (username.isNotEmpty && username.length < _usernameMin) {
      setState(
        () => _error = 'Username must be at least $_usernameMin characters.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = AppProfile.instance;
      // The IDs are kept as they are (they are changed on the page).
      await profile.save(
        profile.data.copyWith(
          name: _name.text.trim(),
          username: username,
          bio: _bio.text.trim(),
          picture: _picture,
          banner: _banner,
        ),
      );
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

  // ---------- Pieces ----------

  InputDecoration _decoration(
    Color fg, {
    required String label,
    required Widget icon,
  }) {
    OutlineInputBorder border(double alpha, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(_fieldRadius),
      borderSide: BorderSide(color: fg.withValues(alpha: alpha), width: width),
    );
    return InputDecoration(
      isDense: true,
      labelText: label,
      labelStyle: TextStyle(
        color: fg.withValues(alpha: AppConstants.mutedAlpha),
      ),
      floatingLabelStyle: TextStyle(color: fg),
      counterStyle: TextStyle(
        color: fg.withValues(alpha: AppConstants.mutedAlpha),
      ),
      prefixIcon: icon,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMd,
        vertical: 15,
      ),
      border: border(AppConstants.borderAlpha, 1),
      enabledBorder: border(AppConstants.borderAlpha, 1),
      focusedBorder: border(1, 2),
    );
  }

  Widget _badge(IconData icon) => Container(
    width: 26,
    height: 26,
    decoration: const BoxDecoration(
      color: Colors.black54,
      shape: BoxShape.circle,
    ),
    child: Icon(icon, size: 14, color: Colors.white),
  );

  /// Banner on top, the profile picture circle overlapping it.
  /// Tap either one to change it.
  Widget _preview(Color fg, Color bg) {
    final banner = _banner;
    final hasBanner = banner != null && File(banner).existsSync();
    return SizedBox(
      height: _bannerHeight + _avatarSize / 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: _bannerHeight,
            child: Material(
              color: fg.withValues(alpha: AppConstants.tintAlpha),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _change(banner: true),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasBanner)
                      Image.file(
                        File(banner),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      )
                    else
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined, color: fg),
                            const SizedBox(height: 4),
                            Text(
                              'Banner picture',
                              style: TextStyle(
                                fontSize: 12,
                                color: fg.withValues(
                                  alpha: AppConstants.mutedAlpha,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: _badge(Icons.photo_camera_outlined),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: AppConstants.spaceMd,
            top: _bannerHeight - _avatarSize / 2,
            child: GestureDetector(
              onTap: () => _change(banner: false),
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: bg,
                    ),
                    child: _AvatarImage(
                      path: _picture,
                      size: _avatarSize - 8,
                      fg: fg,
                      bg: bg,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: _badge(Icons.photo_camera_outlined),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    final style = TextStyle(color: fg, fontSize: 16);

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
                    child: Icon(Icons.person_outline, color: fg),
                  ),
                  const SizedBox(width: AppConstants.spaceMd),
                  Text(
                    'Edit Profile',
                    style: base.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceMd),

              // Banner picture + profile picture
              _preview(fg, bg),
              const SizedBox(height: AppConstants.spaceSm),

              // Name
              TextField(
                controller: _name,
                style: style,
                cursorColor: fg,
                maxLength: _nameMax,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: _decoration(
                  fg,
                  label: 'Name',
                  icon: Icon(Icons.badge_outlined, color: fg),
                ).copyWith(counterText: ''),
              ),
              const SizedBox(height: _gap),

              // Username
              TextField(
                controller: _username,
                style: style,
                cursorColor: fg,
                maxLength: _usernameMax,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._]')),
                ],
                decoration: _decoration(
                  fg,
                  label: 'Username',
                  icon: Icon(Icons.alternate_email, color: fg),
                ).copyWith(counterText: ''),
              ),
              const SizedBox(height: _gap),

              // Bio
              TextField(
                controller: _bio,
                style: style,
                cursorColor: fg,
                maxLength: _bioMax,
                minLines: 3,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: _decoration(
                  fg,
                  label: 'Bio',
                  icon: Icon(Icons.notes, color: fg),
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

              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Changes'),
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
// New ID / Edit ID pop-up
// ------------------------------------------------------------------

InputDecoration _idDecoration(
  Color fg, {
  required String label,
  required Widget icon,
}) {
  OutlineInputBorder border(double alpha, double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(4),
    borderSide: BorderSide(color: fg.withValues(alpha: alpha), width: width),
  );
  return InputDecoration(
    isDense: true,
    labelText: label.tr,
    labelStyle: TextStyle(color: fg.withValues(alpha: AppConstants.mutedAlpha)),
    floatingLabelStyle: TextStyle(color: fg),
    counterStyle: TextStyle(color: fg.withValues(alpha: AppConstants.mutedAlpha)),
    prefixIcon: icon,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppConstants.spaceMd,
      vertical: 15,
    ),
    border: border(AppConstants.borderAlpha, 1),
    enabledBorder: border(AppConstants.borderAlpha, 1),
    focusedBorder: border(1, 2),
  );
}

/// Add an ID ([card] == null) or edit one. A front picture, a back picture,
/// a name and details. The name and details are only saved, never shown.
class _IdSheet extends StatefulWidget {
  final IdCard? card;
  const _IdSheet({this.card});

  @override
  State<_IdSheet> createState() => _IdSheetState();
}

class _IdSheetState extends State<_IdSheet> {
  static const double _sidePad = 20;
  static const double _gap = 12;
  static const int _nameMax = 30;
  static const int _detailsMax = 120;

  final _name = TextEditingController();
  final _details = TextEditingController();
  String? _front;
  String? _back;
  final List<String> _staged = []; // pictures picked in this pop-up
  bool _saving = false;
  bool _didSave = false;
  String? _error;

  bool get _editing => widget.card != null;

  bool get _canSave =>
      !_saving &&
      (_front != null || _back != null || _name.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    final c = widget.card;
    if (c != null) {
      _name.text = c.name;
      _details.text = c.details;
      _front = c.front;
      _back = c.back;
    }
    _name.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    if (!_didSave) {
      for (final path in _staged) {
        _deleteFile(path);
      }
    }
    _name.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _change({required bool back}) async {
    final current = back ? _back : _front;
    try {
      final picked = await _pickImage(
        context,
        title: back ? 'ID back' : 'ID front',
        canRemove: current != null,
        maxWidth: 2000,
      );
      if (picked == null) return;
      if (!mounted) {
        _deleteFile(picked.path);
        return;
      }
      // A picture picked earlier in this pop-up and replaced again.
      if (current != null && _staged.remove(current)) _deleteFile(current);
      final path = picked.path;
      if (path != null) _staged.add(path);
      setState(() {
        if (back) {
          _back = path;
        } else {
          _front = path;
        }
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t get that image.');
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = AppProfile.instance;
      final data = profile.data;
      final name = _name.text.trim();
      final details = _details.text.trim();
      final editId = widget.card?.id;
      final List<IdCard> next = editId == null
          ? [
              ...data.ids,
              IdCard(
                id: '${DateTime.now().microsecondsSinceEpoch}',
                front: _front,
                back: _back,
                name: name,
                details: details,
              ),
            ]
          : [
              for (final c in data.ids)
                if (c.id == editId)
                  c.copyWith(
                    front: _front,
                    back: _back,
                    name: name,
                    details: details,
                  )
                else
                  c,
            ];
      await profile.save(data.copyWith(ids: next));
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
    final ok = await showConfirmDialog(
      context,
      destructive: true,
      icon: Icons.delete_forever,
      title: 'Delete ID'.tr,
      message: 'This ID and its pictures will be permanently deleted.'.tr,
      points: [
        ConfirmPoint(Icons.warning_amber_rounded, 'This can\'t be undone.'.tr),
      ],
      confirmLabel: 'Delete'.tr,
      confirmIcon: Icons.delete,
    );
    if (!ok || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = AppProfile.instance;
      final data = profile.data;
      await profile.save(
        data.copyWith(
          ids: [
            for (final c in data.ids)
              if (c.id != widget.card!.id) c,
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      if (mounted) setState(() => _error = const UnknownFailure().message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _tile(bool back, Color fg) {
    final path = back ? _back : _front;
    final has = path != null && File(path).existsSync();
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    return Expanded(
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: AppConstants.cardRatio,
            child: Material(
              color: fg.withValues(alpha: AppConstants.tintAlpha),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _change(back: back),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (has)
                      Image.file(
                        File(path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      )
                    else
                      Center(
                        child: Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 30,
                          color: fg,
                        ),
                      ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.photo_camera_outlined,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            (back ? 'Back' : 'Front').tr,
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    final style = TextStyle(color: fg, fontSize: 16);
    final red = AppSettings.instance.deleteColor;

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
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: AppConstants.tintAlpha),
                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    ),
                    child: Icon(Icons.badge_outlined, color: fg),
                  ),
                  const SizedBox(width: AppConstants.spaceMd),
                  Text(
                    (_editing ? 'Edit ID' : 'New ID').tr,
                    style: base.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceMd),

              // Front + back pictures
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _tile(false, fg),
                  const SizedBox(width: _gap),
                  _tile(true, fg),
                ],
              ),
              const SizedBox(height: _gap),

              TextField(
                controller: _name,
                style: style,
                cursorColor: fg,
                maxLength: _nameMax,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: _idDecoration(
                  fg,
                  label: 'Name',
                  icon: Icon(Icons.label_outline, color: fg),
                ).copyWith(counterText: ''),
              ),
              const SizedBox(height: _gap),
              TextField(
                controller: _details,
                style: style,
                cursorColor: fg,
                maxLength: _detailsMax,
                minLines: 3,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: _idDecoration(
                  fg,
                  label: 'Details',
                  icon: Icon(Icons.notes, color: fg),
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

              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _canSave ? _save : null,
                  icon: Icon(_editing ? Icons.save : Icons.add),
                  label: Text((_editing ? 'Save Changes' : 'Add ID').tr),
                ),
              ),
              if (_editing) ...[
                const SizedBox(height: AppConstants.spaceSm),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: red,
                      side: BorderSide(color: red, width: 1.5),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: Text('Delete ID'.tr),
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