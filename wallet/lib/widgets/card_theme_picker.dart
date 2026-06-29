import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/account_model.dart';
import '../models/card_theme_model.dart';
import '../utils/color_helpers.dart';
import '../currency.dart';

// ── Number formatter (mirrors the one in accounts_page) ───────────────────────

final _currencyFmt = NumberFormat('#,##0.00', 'en_PH');
String _fmt(double v) => _currencyFmt.format(v);

// ── Public entry-point ────────────────────────────────────────────────────────

/// Shows the card-theme picker modal and returns the chosen [CardThemeModel],
/// or `null` if the user dismissed without applying.
Future<CardThemeModel?> showCardThemePicker({
  required BuildContext context,
  required Account account,
  required CardThemeModel current,
}) {
  return showModalBottomSheet<CardThemeModel>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _CardThemePickerSheet(account: account, current: current),
  );
}

// ── Sheet ─────────────────────────────────────────────────────────────────────

class _CardThemePickerSheet extends StatefulWidget {
  final Account account;
  final CardThemeModel current;
  const _CardThemePickerSheet({required this.account, required this.current});

  @override
  State<_CardThemePickerSheet> createState() => _CardThemePickerSheetState();
}

class _CardThemePickerSheetState extends State<_CardThemePickerSheet> {
  late CardThemeModel _selected;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
  }

  void _selectSystem(SystemCardTheme t) =>
      setState(() => _selected = CardThemeModel(name: t.id));

  Future<void> _pickPhoto({required bool forFront}) async {
    final xfile = await _picker.pickImage(source: ImageSource.gallery);
    if (xfile == null) return;
    setState(() {
      _selected = CardThemeModel(
        name: 'custom',
        frontImagePath: forFront ? xfile.path : _selected.frontImagePath,
        backImagePath: forFront ? _selected.backImagePath : xfile.path,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Use the account type's own color as the accent for the Apply button,
    // theme tile selection rings, and photo-picker highlights.
    // Falls back to a muted dark-surface neutral in dark mode when no type
    // has been chosen yet (colorHex is still the generic indigo placeholder).
    const kFallbackHex = '#6366F1';
    const kDarkMutedHex = '#5C5C6E';
    final colorHex = widget.account.colorHex;
    final bool hasRealColor = colorHex.isNotEmpty &&
        colorHex != kFallbackHex &&
        colorHex != kDarkMutedHex;
    final Color accent = hasRealColor
        ? colorFromHex(colorHex)
        : (isDark ? const Color(0xFF5C5C6E) : theme.colorScheme.primary);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  Icon(Icons.style_outlined, size: 20, color: accent),
                  const SizedBox(width: 8),
                  Text('Card Theme',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    style: FilledButton.styleFrom(
                      backgroundColor: HSLColor.fromColor(accent)
                          .withLightness(
                            (HSLColor.fromColor(accent).lightness - 0.15)
                                .clamp(0.0, 1.0),
                          )
                          .toColor(),
                      foregroundColor:
                          isDark ? Colors.white : theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            Expanded(
              child: CustomScrollView(
                controller: scrollCtrl,
                slivers: [
                  // ── Live front-card preview ───────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: _CardPreview(
                          account: widget.account,
                          themeModel: _selected,
                        ),
                      ),
                    ),
                  ),

                  // ── System themes ─────────────────────────────────────────
                  _SliverSectionLabel(label: 'System Themes'),

                  // System theme grid
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.2,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final t = CardThemeModel.orderedSystemThemes[i];
                          return _ThemeTile(
                            label: t.label,
                            selected: _selected.name == t.id,
                            preview: _SystemThemeSwatch(
                              systemTheme: t,
                              account: widget.account,
                            ),
                            onTap: () => _selectSystem(t),
                            accent: accent,
                          );
                        },
                        childCount: CardThemeModel.orderedSystemThemes.length,
                      ),
                    ),
                  ),

                  // ── Custom photos ─────────────────────────────────────────
                  _SliverSectionLabel(label: 'Custom Photos'),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      child: Column(
                        children: [
                          _PhotoPickerRow(
                            label: 'Front photo',
                            imagePath: _selected.isCustomPhoto
                                ? _selected.frontImagePath
                                : '',
                            onPick: () => _pickPhoto(forFront: true),
                            onClear: _selected.isCustomPhoto &&
                                    _selected.frontImagePath.isNotEmpty
                                ? () => setState(() {
                                      final hasBack =
                                          _selected.backImagePath.isNotEmpty;
                                      _selected = hasBack
                                          ? CardThemeModel(
                                              name: 'custom',
                                              backImagePath:
                                                  _selected.backImagePath)
                                          : const CardThemeModel();
                                    })
                                : null,
                            accent: accent,
                          ),
                          const SizedBox(height: 10),
                          _PhotoPickerRow(
                            label: 'Back photo',
                            imagePath: _selected.isCustomPhoto
                                ? _selected.backImagePath
                                : '',
                            onPick: () => _pickPhoto(forFront: false),
                            onClear: _selected.isCustomPhoto &&
                                    _selected.backImagePath.isNotEmpty
                                ? () => setState(() {
                                      final hasFront =
                                          _selected.frontImagePath.isNotEmpty;
                                      _selected = hasFront
                                          ? CardThemeModel(
                                              name: 'custom',
                                              frontImagePath:
                                                  _selected.frontImagePath)
                                          : const CardThemeModel();
                                    })
                                : null,
                            accent: accent,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Photos are stored locally on your device.',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Live card preview (front face only) ───────────────────────────────────────

class _CardPreview extends StatelessWidget {
  final Account account;
  final CardThemeModel themeModel;
  const _CardPreview({required this.account, required this.themeModel});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accountColor = account.colorHex.isNotEmpty
        ? colorFromHex(account.colorHex)
        : const Color(0xFF6366F1);

    final systemTheme = themeModel.systemTheme;
    final customPath =
        themeModel.isCustomPhoto ? themeModel.frontImagePath : '';
    final hasPhoto = customPath.isNotEmpty;

    // The gradient always comes from the account color so all cards of the
    // same account type share the same color identity. System themes only
    // change the overlay pattern painted on top.
    final List<Color> gradColors =
        gradientForColor(accountColor, isDark: isDark);
    const begin = Alignment.topLeft;
    const end = Alignment.bottomRight;
    final overlay = systemTheme?.overlay ?? CardOverlayPattern.circles;
    const onColor = Colors.white;

    return Container(
      width: 255,
      height: 155,
      decoration: BoxDecoration(
        gradient: hasPhoto
            ? null
            : LinearGradient(begin: begin, end: end, colors: gradColors),
        color: hasPhoto ? Colors.black : null,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (hasPhoto)
            Positioned.fill(
              child: Image.file(
                File(customPath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade800,
                  child: const Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: Colors.white54)),
                ),
              ),
            ),
          if (!hasPhoto)
            Positioned.fill(
              child: CustomPaint(painter: _OverlayPainter(overlay)),
            ),
          if (hasPhoto)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        account.name,
                        style: TextStyle(
                          color: onColor.withValues(alpha: 0.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: onColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(Icons.folder_outlined,
                          color: onColor.withValues(alpha: 0.7), size: 14),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  '${currencySymbolNotifier.value} ${_fmt(account.balance)}',
                  style: TextStyle(
                    color: account.balance >= 0 ? onColor : Colors.red.shade200,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: onColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    account.category.toUpperCase(),
                    style: TextStyle(
                      color: onColor,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
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

// ── Overlay pattern painter ────────────────────────────────────────────────────

class _OverlayPainter extends CustomPainter {
  final CardOverlayPattern pattern;
  const _OverlayPainter(this.pattern);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.09);
    switch (pattern) {
      case CardOverlayPattern.circles:
        canvas.drawCircle(Offset(size.width + 22, -22), 50, paint);
        canvas.drawCircle(Offset(-10, size.height + 22), 37.5,
            Paint()..color = Colors.white.withValues(alpha: 0.06));
        break;
      case CardOverlayPattern.diagonalStripes:
        final sp = Paint()
          ..color = Colors.white.withValues(alpha: 0.06)
          ..strokeWidth = 14
          ..style = PaintingStyle.stroke;
        for (double x = -size.height; x < size.width + size.height; x += 28) {
          canvas.drawLine(
              Offset(x, 0), Offset(x + size.height, size.height), sp);
        }
        break;
      case CardOverlayPattern.grid:
        final gp = Paint()
          ..color = Colors.white.withValues(alpha: 0.07)
          ..strokeWidth = 1;
        for (double x = 0; x < size.width; x += 22) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), gp);
        }
        for (double y = 0; y < size.height; y += 22) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), gp);
        }
        break;
      case CardOverlayPattern.rings:
        final rp = Paint()
          ..color = Colors.white.withValues(alpha: 0.07)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        final center = Offset(size.width * 0.7, size.height * 0.3);
        for (double r = 30; r < 160; r += 30) {
          canvas.drawCircle(center, r, rp);
        }
        break;
      case CardOverlayPattern.waves:
        final wp = Paint()
          ..color = Colors.white.withValues(alpha: 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        for (double y = 0; y < size.height + 24; y += 24) {
          final path = Path()..moveTo(0, y);
          for (double x = 0; x < size.width; x += 20) {
            path.relativeQuadraticBezierTo(10, -12, 20, 0);
          }
          canvas.drawPath(path, wp);
        }
        break;
      case CardOverlayPattern.none:
        break;
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.pattern != pattern;
}

// ── Section label ──────────────────────────────────────────────────────────────

class _SliverSectionLabel extends StatelessWidget {
  final String label;
  const _SliverSectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

// ── Theme tile ─────────────────────────────────────────────────────────────────

class _ThemeTile extends StatelessWidget {
  final String label;
  final bool selected;
  final Widget preview;
  final VoidCallback onTap;
  final Color accent;

  const _ThemeTile({
    required this.label,
    required this.selected,
    required this.preview,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : theme.colorScheme.outlineVariant,
            width: selected ? 2.5 : 1,
          ),
          color: selected
              ? accent.withValues(alpha: 0.07)
              : theme.colorScheme.surfaceContainerLow,
        ),
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(width: 56, height: 34, child: preview),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? accent : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}

// ── Preview swatches ───────────────────────────────────────────────────────────

class _SystemThemeSwatch extends StatelessWidget {
  final SystemCardTheme systemTheme;
  final Account account;
  const _SystemThemeSwatch({required this.systemTheme, required this.account});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = account.colorHex.isNotEmpty
        ? colorFromHex(account.colorHex)
        : const Color(0xFF6366F1);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientForColor(color, isDark: isDark),
        ),
      ),
      child: CustomPaint(
        painter: _OverlayPainter(systemTheme.overlay),
        child: const SizedBox.expand(),
      ),
    );
  }
}

// ── Photo picker row ───────────────────────────────────────────────────────────

class _PhotoPickerRow extends StatelessWidget {
  final String label;
  final String imagePath;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final Color accent;

  const _PhotoPickerRow({
    required this.label,
    required this.imagePath,
    required this.onPick,
    required this.onClear,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = imagePath.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasImage ? accent : theme.colorScheme.outlineVariant,
          width: hasImage ? 1.5 : 1,
        ),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 48,
              height: 30,
              child: hasImage
                  ? Image.file(File(imagePath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade700,
                            child: const Icon(Icons.broken_image_outlined,
                                size: 16, color: Colors.white54),
                          ))
                  : Container(
                      color: theme.colorScheme.surfaceContainerHigh,
                      child: Icon(Icons.image_outlined,
                          size: 18, color: theme.colorScheme.onSurfaceVariant),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hasImage ? label : '$label (none)',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: hasImage ? FontWeight.w600 : FontWeight.w400,
                color: hasImage ? null : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (onClear != null)
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded, size: 18),
              color: theme.colorScheme.error,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Remove photo',
            ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onPick,
            icon: Icon(
              hasImage
                  ? Icons.swap_horiz_rounded
                  : Icons.add_photo_alternate_outlined,
              size: 16,
            ),
            label: Text(hasImage ? 'Change' : 'Choose'),
            style: TextButton.styleFrom(
              foregroundColor: accent,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}
