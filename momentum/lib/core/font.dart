import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/helper.dart';
import 'constants.dart';

/// One selectable font. [family] == null means the platform default font.
/// [path] is only set for fonts the user imported.
class AppFont {
  final String label;
  final String? family;
  final String? path;

  const AppFont(this.label, this.family, [this.path]);

  bool get isImported => path != null;
}

class AppFonts {
  AppFonts._();

  static const defaultFont = AppFont('System default', null);

  /// Fonts that come with the app.
  /// Names like 'serif' / 'monospace' / 'casual' / 'cursive' are built into
  /// Android. To offer more fonts on every platform, add the font files to
  /// pubspec.yaml (under `flutter: fonts:`) and add an entry here using the
  /// same family name.
  static const builtIn = <AppFont>[
    defaultFont,
    AppFont('Roboto', 'Roboto'),
    AppFont('Sans Serif', 'sans-serif'),
    AppFont('Condensed', 'sans-serif-condensed'),
    AppFont('Serif', 'serif'),
    AppFont('Monospace', 'monospace'),
    AppFont('Casual', 'casual'),
    AppFont('Cursive', 'cursive'),
  ];

  /// Fonts imported by the user (Font Style > import button).
  static final List<AppFont> imported = [];

  /// Fonts shown in the Font Style list: built-in first, then imported.
  static List<AppFont> get all => [...builtIn, ...imported];

  /// Finds a font by its saved label. Falls back to the default font.
  static AppFont byLabel(String? label) {
    for (final f in all) {
      if (f.label == label) return f;
    }
    return defaultFont;
  }

  /// Returns [theme] with [family] applied to all of its text styles.
  static ThemeData apply(ThemeData theme, String? family) {
    if (family == null) return theme;
    return theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: family),
      primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: family),
    );
  }

  // ---------- Imported fonts ----------

  static Future<void> _register(String family, Uint8List bytes) async {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  static Future<void> _saveLibrary() {
    return DatabaseHelper.instance.setSetting(
      AppConstants.prefFontLibrary,
      jsonEncode([
        for (final f in imported)
          {'label': f.label, 'family': f.family, 'path': f.path},
      ]),
    );
  }

  /// Registers every saved imported font. Call before the theme is built
  /// (AppSettings.load does this). Files that are gone are skipped.
  static Future<void> loadImported(Map<String, String> store) async {
    imported.clear();
    final raw = store[AppConstants.prefFontLibrary];
    if (raw == null) return;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return;
      for (final entry in list) {
        if (entry is! Map) continue;
        final label = entry['label'];
        final family = entry['family'];
        final path = entry['path'];
        if (label is! String || family is! String || path is! String) continue;
        try {
          final file = File(path);
          if (!await file.exists()) continue;
          await _register(family, await file.readAsBytes());
          imported.add(AppFont(label, family, path));
        } catch (_) {}
      }
    } on FormatException {
      // Unreadable list: no imported fonts.
    }
  }

  /// Copies a font file into the app, registers it and saves it.
  /// Throws when the file can't be used as a font.
  static Future<AppFont> importFont(String fileName, Uint8List bytes) async {
    final family = 'imported_${DateTime.now().microsecondsSinceEpoch}';
    await _register(family, bytes); // throws on an invalid font

    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, AppConstants.fontFolder));
    if (!await folder.exists()) await folder.create(recursive: true);
    final ext = p.extension(fileName).toLowerCase();
    final path = p.join(folder.path, '$family${ext.isEmpty ? '.ttf' : ext}');
    await File(path).writeAsBytes(bytes);

    // Unique label (the saved choice is stored by label).
    final base = p.basenameWithoutExtension(fileName).trim();
    final name = base.isEmpty ? 'Imported font' : base;
    var label = name;
    var n = 2;
    while (all.any((f) => f.label == label)) {
      label = '$name ($n)';
      n++;
    }

    final font = AppFont(label, family, path);
    imported.add(font);
    try {
      await _saveLibrary();
    } catch (_) {
      imported.remove(font);
      try {
        await File(path).delete();
      } catch (_) {}
      rethrow;
    }
    return font;
  }

  static Future<void> removeImported(AppFont font) async {
    imported.removeWhere((f) => f.label == font.label);
    await _saveLibrary();
    final path = font.path;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }
}