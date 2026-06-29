// ignore: unused_import
import 'package:flutter/material.dart';

// ── Card theme kinds ───────────────────────────────────────────────────────────

enum CardThemeKind {
  system,
  customPhoto,
}

// ── Card theme model ───────────────────────────────────────────────────────────

/// Describes the visual theme applied to an account card's background.
///
/// Stored as three columns on the `accounts` / `trash_accounts` row:
///   • `theme_name`       TEXT  ('classic' → default pattern)
///   • `theme_front_img`  TEXT  (absolute path for custom front photo)
///   • `theme_back_img`   TEXT  (absolute path for custom back  photo)
class CardThemeModel {
  final String name;
  final String frontImagePath;
  final String backImagePath;

  const CardThemeModel({
    this.name = 'classic',
    this.frontImagePath = '',
    this.backImagePath = '',
  });

  bool get isCustomPhoto => name == 'custom';
  bool get isSystem => !isCustomPhoto;

  CardThemeKind get kind {
    if (isCustomPhoto) return CardThemeKind.customPhoto;
    return CardThemeKind.system;
  }

  SystemCardTheme? get systemTheme => CardThemeModel.systemThemes[name];

  @override
  bool operator ==(Object other) =>
      other is CardThemeModel &&
      name == other.name &&
      frontImagePath == other.frontImagePath &&
      backImagePath == other.backImagePath;

  @override
  int get hashCode => Object.hash(name, frontImagePath, backImagePath);

  // ── System themes catalog ──────────────────────────────────────────────────

  static final Map<String, SystemCardTheme> systemThemes = {
    for (final t in _kSystemThemes) t.id: t,
  };

  static List<SystemCardTheme> get orderedSystemThemes => _kSystemThemes;
}

// ── System theme definition ────────────────────────────────────────────────────

/// A system theme is purely a named overlay pattern applied on top of the
/// account-color-derived gradient. The base color always comes from
/// [Account.colorHex] so cards of the same account type share a consistent
/// color identity.
class SystemCardTheme {
  final String id;
  final String label;
  final CardOverlayPattern overlay;

  const SystemCardTheme({
    required this.id,
    required this.label,
    required this.overlay,
  });
}

// ── Overlay patterns ───────────────────────────────────────────────────────────

enum CardOverlayPattern {
  circles,
  diagonalStripes,
  grid,
  rings,
  waves,
  none,
}

// ── Built-in system themes ─────────────────────────────────────────────────────

const List<SystemCardTheme> _kSystemThemes = [
  SystemCardTheme(
    id: 'classic',
    label: 'Classic',
    overlay: CardOverlayPattern.circles,
  ),
  SystemCardTheme(
    id: 'lined',
    label: 'Lined',
    overlay: CardOverlayPattern.diagonalStripes,
  ),
  SystemCardTheme(
    id: 'grid',
    label: 'Grid',
    overlay: CardOverlayPattern.grid,
  ),
  SystemCardTheme(
    id: 'rings',
    label: 'Rings',
    overlay: CardOverlayPattern.rings,
  ),
  SystemCardTheme(
    id: 'waves',
    label: 'Waves',
    overlay: CardOverlayPattern.waves,
  ),
  SystemCardTheme(
    id: 'clean',
    label: 'Clean',
    overlay: CardOverlayPattern.none,
  ),
];
