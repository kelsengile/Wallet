import 'package:flutter/material.dart';

/// App-wide constants. Every fixed value that is shared between files
/// (or is a tuning knob for a screen) lives here.
class AppConstants {
  AppConstants._();

  // ---------- App ----------
  static const String appName = 'Momentum';
  static const String appVersion = '1.0.0'; // keep in sync with pubspec.yaml
  static const String databaseName = 'momentum.db';
  static const int databaseVersion = 1;

  // ---------- Database ----------
  static const String schemaAsset = 'lib/database/schema.sql';
  static const String seedAsset = 'lib/database/seed.sql';

  /// Written into backup files and checked again on import.
  static const String exportApp = 'momentum';
  static const int exportFormat = 1;

  // ---------- Money ----------
  static const String currencySymbol = '₱';

  /// Symbol followed by a space, used on the big balance numbers.
  static const String currencyPrefix = '$currencySymbol ';

  /// Money is stored as whole centavos.
  static const int centavosPerPeso = 100;

  static const Color incomeColor = Color(0xFF4CAF50);
  static const Color expenseColor = Color(0xFFF44A5A);

  // ---------- Spacing scale ----------
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceSmMd = 12; // between Sm and Md
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;

  // ---------- Radii ----------
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 20;

  // ---------- Common sizes ----------
  /// Height of the progress bar under an app bar.
  static const double progressBarHeight = 3;

  /// Big icon on "empty" screens.
  static const double emptyStateIconSize = 48;

  /// Space at the top of the drawer list.
  static const double drawerTopGap = 10;

  /// Normal body font size, used to read the current text scale.
  static const double baseFontSize = 14;

  /// Slide time when changing pages.
  static const Duration pageAnimationDuration = Duration(milliseconds: 250);

  // ---------- Opacity / blending ----------
  /// Softer text and icons (secondary text).
  static const double mutedAlpha = 0.7;

  /// Lines between rows / header and content inside a card.
  static const double dividerAlpha = 0.25;

  /// Outlines of fields and boxes.
  static const double borderAlpha = 0.5;

  /// Light tint behind icons and chips drawn on the accent color.
  static const double tintAlpha = 0.18;

  /// Thin vertical separator between income and expense.
  static const double separatorAlpha = 0.3;

  /// How far the divider color moves from the accent toward its glyph color.
  static const double dividerBlend = 0.18;

  // ---------- Pop-ups ----------
  /// Darker dim behind every pop-up, so the pop-up colors stand out more.
  static const Color popupBarrier = Color(0xCC000000);
  static const double popupRadius = 24;
  static const EdgeInsets popupInsetPadding =
      EdgeInsets.symmetric(horizontal: 40, vertical: 24);
  static const EdgeInsets popupTitlePadding = EdgeInsets.fromLTRB(20, 18, 20, 0);
  static const EdgeInsets popupContentPadding =
      EdgeInsets.fromLTRB(20, 12, 20, 4);
  static const EdgeInsets popupActionsPadding =
      EdgeInsets.fromLTRB(12, 0, 12, 10);

  /// Shorter version (used by the delete pop-up).
  static const EdgeInsets popupTitlePaddingCompact =
      EdgeInsets.fromLTRB(20, 14, 20, 0);
  static const EdgeInsets popupContentPaddingCompact =
      EdgeInsets.fromLTRB(20, 6, 20, 0);
  static const EdgeInsets popupActionsPaddingCompact =
      EdgeInsets.fromLTRB(12, 0, 12, 6);

  // ---------- Categories screen ----------
  static const double categoryBarRadius = 16;
  static const double categoryCardHeaderHeight = 48;
  static const int iconGridColumns = 8;
  static const double iconGridGap = 4;
  static const double iconTileRadius = 10;
  static const double categoryBarLighten = 0.15;
  static const double categoryAvatarAlpha = 0.12;
  static const double iconTileAlpha = 0.10;
  static const double iconTileSelectedAlpha = 0.28;

  // ---------- Settings screen ----------
  static const String prefTheme = 'settings.theme';
  static const String prefColor = 'settings.customColor';
  static const String prefAccent = 'settings.accentColor';
  static const String prefText = 'settings.textColor';
  static const String prefTextSize = 'settings.textSizeIndex';
  static const String prefFontStyle = 'settings.fontStyle';
  static const String prefBoldText = 'settings.boldText';

  static const List<String> textSizeLabels = [
    'Smallest',
    'Small',
    'Default (system)',
    'Big',
    'Biggest',
  ];
  static const List<double> textScales = [0.8, 0.9, 1.0, 1.15, 1.3];
  static const int defaultTextSizeIndex = 2;

  static const double fontSliderWidth = 150;
  static const double colorBoxHeight = 72;
  static const double hexFontSize = 18;
  static const int hexInputLength = 7; // "#" + 6 digits
  static const double hueGradientStep = 60;
  static const double gradientSliderHeight = 32;
  static const double gradientTrackHeight = 12;
  static const double segmentSelectedAlpha = 0.25;

  // ---------- Finance screen: account cards ----------
  // The card has the real card ratio (ISO/IEC 7810 ID-1: 85.60 x 53.98 mm).
  // Every size inside the card is a multiple of "u" = card width / 612.
  // At the "Big" font size the card and its text match the sample.
  // cardFollow / textFollow = how much of the font size change the CARD /
  // TEXT follows (0 = never changes, 1 = changes as much as the setting).
  static const double cardSampleWidth = 612;
  static const double cardRatio = 85.60 / 53.98;
  static const double bigTextScale = 1.15;
  static const double baseCardWidth = 250 * bigTextScale;
  static const double cardFollow = 0.25;
  static const double textFollow = 0.4;
  static const Duration cardFlipDuration = Duration(milliseconds: 400);
  static const double cardBandAlpha = 0.6;

  // ---------- Finance screen: total balance card ----------
  /// true  = keep the exact debit/credit card ratio (taller).
  /// false = only as tall as the content.
  static const bool totalCardUseRatio = false;

  /// Space between the app bar and "Total Balance".
  static const double totalCardTopMargin = 60;

  /// Space between the balance row and the bottom edge of the card.
  static const double totalCardBottomMargin = 35;
  static const double totalCardSideMargin = spaceLg - spaceXs;

  /// Space between "Total Balance" and the balance row.
  static const double totalCardLabelGap = 10;
  static const double totalCardRadius = 28;

  /// w300 = light ... w700 = bold.
  static const FontWeight balanceWeight = FontWeight.w700;
  static const double balanceFontSize = 38;

  /// Moves the * down. Fraction of the font size.
  static const double maskDrop = 0.25;

  /// Shown instead of amounts when hidden.
  static const String maskText = '****';
}