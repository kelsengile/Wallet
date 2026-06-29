import 'card_theme_model.dart';

class Account {
  final int? id;
  final String name;
  final double balance;
  final String
      type; // 'cash', 'bank', 'e-wallet', etc. — managed in Category Manager
  final String
      category; // 'personal', 'business', etc. — managed in Category Manager
  final String colorHex;
  final String icon;

  /// Optional short title shown on the back of the account card (≤ 30 chars).
  final String? noteHeader;

  /// Optional longer note shown below the header on the card back (≤ 120 chars).
  final String? noteBody;

  // ── Card theme ──────────────────────────────────────────────────────────────

  /// Name key of the chosen card theme.
  ///   • `''`        → default color-derived gradient
  ///   • system id   → one of [CardThemeModel.systemThemes]
  ///   • `'custom'`  → user-supplied photos
  final String themeName;

  /// Absolute path to the custom front-face photo (empty when unused).
  final String themeFrontImg;

  /// Absolute path to the custom back-face photo (empty when unused).
  final String themeBackImg;

  Account({
    this.id,
    required this.name,
    required this.balance,
    required this.type,
    this.category = 'personal',
    required this.colorHex,
    required this.icon,
    this.noteHeader,
    this.noteBody,
    this.themeName = '',
    this.themeFrontImg = '',
    this.themeBackImg = '',
  });

  /// Convenience getter — resolves the three raw columns into a [CardThemeModel].
  CardThemeModel get cardTheme => CardThemeModel(
        name: themeName,
        frontImagePath: themeFrontImg,
        backImagePath: themeBackImg,
      );

  Account copyWith({
    int? id,
    String? name,
    double? balance,
    String? type,
    String? category,
    String? colorHex,
    String? icon,
    // Use Object? sentinel so callers can explicitly clear these to null.
    Object? noteHeader = _sentinel,
    Object? noteBody = _sentinel,
    String? themeName,
    String? themeFrontImg,
    String? themeBackImg,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      balance: balance ?? this.balance,
      type: type ?? this.type,
      category: category ?? this.category,
      colorHex: colorHex ?? this.colorHex,
      icon: icon ?? this.icon,
      noteHeader:
          noteHeader == _sentinel ? this.noteHeader : noteHeader as String?,
      noteBody: noteBody == _sentinel ? this.noteBody : noteBody as String?,
      themeName: themeName ?? this.themeName,
      themeFrontImg: themeFrontImg ?? this.themeFrontImg,
      themeBackImg: themeBackImg ?? this.themeBackImg,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'balance': balance,
      'type': type,
      'category': category,
      'color_hex': colorHex,
      'icon': icon,
      'note_header': noteHeader ?? '',
      'note_body': noteBody ?? '',
      'theme_name': themeName,
      'theme_front_img': themeFrontImg,
      'theme_back_img': themeBackImg,
    };
  }

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'] as int?,
      name: map['name'] as String,
      balance: (map['balance'] as num).toDouble(),
      type: map['type'] as String,
      category: (map['category'] as String?) ?? 'personal',
      colorHex: map['color_hex'] as String,
      icon: map['icon'] as String,
      noteHeader: (map['note_header'] as String?)?.isEmpty == true
          ? null
          : map['note_header'] as String?,
      noteBody: (map['note_body'] as String?)?.isEmpty == true
          ? null
          : map['note_body'] as String?,
      themeName: (map['theme_name'] as String?) ?? '',
      themeFrontImg: (map['theme_front_img'] as String?) ?? '',
      themeBackImg: (map['theme_back_img'] as String?) ?? '',
    );
  }
}

/// Private sentinel used by [Account.copyWith] to distinguish "not provided"
/// from an explicit `null` for the nullable [noteHeader] / [noteBody] fields.
const Object _sentinel = Object();
