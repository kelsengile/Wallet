import 'package:flutter/material.dart';

// ── Category group types ────────────────────────────────────────────────────
//
// Every category lives in one of three independent groups. Account types and
// account categories are completely separate from transaction categories —
// editing one group never affects the others.
const kCategoryGroupAccountType = 'account_type';
const kCategoryGroupAccountCategory = 'account_category';
const kCategoryGroupTransactionCategory = 'transaction_category';

// ── Transaction category sub-types ─────────────────────────────────────────
//
// Within [kCategoryGroupTransactionCategory] every category is tagged with
// one of these sub-types so the Category Manager can show income and expense
// categories in separate sections. The system "Transfer" category uses an
// empty string (no sub-type).
const kSubTypeIncome = 'income';
const kSubTypeExpense = 'expense';

/// The name of the built-in, non-deletable, non-editable transaction
/// category used for transfer-in/transfer-out legs. It is seeded once and
/// is hidden from the regular "add transaction" category picker.
const kTransferCategoryName = 'Transfer';

/// The name of the built-in system transaction category seeded for both
/// income and expense sub-types. It appears in the category picker just like
/// any user-added category (unlike Transfer, which is hidden), but cannot be
/// edited, deleted, or renamed.
const kMiscellaneousCategoryName = 'Miscellaneous';

// ── Icon registry ────────────────────────────────────────────────────────────
//
// Maps a stable string key (stored in the DB) to a Material icon. The
// Category Manager's icon picker offers these as choices, so icons stay
// consistent even as categories are renamed.
const Map<String, IconData> kCategoryIcons = {
  'wallet': Icons.account_balance_wallet_outlined,
  'cash': Icons.payments_outlined,
  'bank': Icons.account_balance_outlined,
  'ewallet': Icons.phone_android_outlined,
  'credit_card': Icons.credit_card_outlined,
  'handshake': Icons.handshake_outlined,
  'trending_up': Icons.trending_up_outlined,
  'savings': Icons.savings_outlined,
  'restaurant': Icons.restaurant,
  'transport': Icons.directions_car,
  'shopping': Icons.shopping_bag,
  'bills': Icons.receipt_long,
  'health': Icons.favorite,
  'entertainment': Icons.movie,
  'work': Icons.work,
  'swap': Icons.swap_horiz,
  'home': Icons.home,
  'gift': Icons.card_giftcard,
  'pet': Icons.pets,
  'school': Icons.school,
  'fitness': Icons.fitness_center,
  'travel': Icons.flight,
  'family': Icons.family_restroom,
  'business': Icons.business_center,
  'goal': Icons.flag,
  'emergency': Icons.local_hospital,
  'star': Icons.star,
  'category': Icons.category,
  'label': Icons.label_outline,
};

IconData iconForKey(String key) => kCategoryIcons[key] ?? Icons.label_outline;

/// Best-effort reverse lookup — used when migrating/seeding so we can store
/// a stable key instead of an [IconData].
String keyForIcon(IconData icon) {
  for (final entry in kCategoryIcons.entries) {
    if (entry.value == icon) return entry.key;
  }
  return 'label';
}

// ── Color palette ────────────────────────────────────────────────────────────
//
// Preset swatches offered in the Category Manager's color picker.
const List<String> kCategoryColorPalette = [
  '#22C55E',
  '#3B82F6',
  '#A855F7',
  '#EF4444',
  '#F97316',
  '#0EA5E9',
  '#14B8A6',
  '#6366F1',
  '#EC4899',
  '#F59E0B',
  '#10B981',
  '#8B5CF6',
  '#64748B',
];

Color colorFromHex(String hex) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}

String colorToHex(Color color) {
  return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
}

/// Returns a two-stop gradient (darker → lighter) derived from [base], used
/// for account cards so custom account types still look good without the
/// app needing a hand-curated gradient for every possible color.
List<Color> gradientForColor(Color base) {
  final lighter = Color.lerp(base, Colors.white, 0.35)!;
  return [base, lighter];
}

// ── Category model ────────────────────────────────────────────────────────────

class WalletCategory {
  final int? id;
  final String name;
  final String groupType;
  final String icon; // key into kCategoryIcons
  final String colorHex;
  final int sortOrder;
  final bool isDefault;

  /// System categories (currently only "Transfer") can never be edited,
  /// deleted, renamed, or set/unset as default.
  final bool isSystem;

  /// For [kCategoryGroupTransactionCategory] only: either [kSubTypeIncome]
  /// or [kSubTypeExpense]. Empty string for the system Transfer category and
  /// for categories in the other two groups.
  final String subType;

  const WalletCategory({
    this.id,
    required this.name,
    required this.groupType,
    required this.icon,
    required this.colorHex,
    this.sortOrder = 0,
    this.isDefault = false,
    this.isSystem = false,
    this.subType = '',
  });

  IconData get iconData => iconForKey(icon);
  Color get color => colorFromHex(colorHex);

  WalletCategory copyWith({
    int? id,
    String? name,
    String? groupType,
    String? icon,
    String? colorHex,
    int? sortOrder,
    bool? isDefault,
    bool? isSystem,
    String? subType,
  }) {
    return WalletCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      groupType: groupType ?? this.groupType,
      icon: icon ?? this.icon,
      colorHex: colorHex ?? this.colorHex,
      sortOrder: sortOrder ?? this.sortOrder,
      isDefault: isDefault ?? this.isDefault,
      isSystem: isSystem ?? this.isSystem,
      subType: subType ?? this.subType,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'group_type': groupType,
      'icon': icon,
      'color_hex': colorHex,
      'sort_order': sortOrder,
      'is_default': isDefault ? 1 : 0,
      'is_system': isSystem ? 1 : 0,
      'sub_type': subType,
    };
  }

  factory WalletCategory.fromMap(Map<String, dynamic> map) {
    return WalletCategory(
      id: map['id'] as int?,
      name: map['name'] as String,
      groupType: map['group_type'] as String,
      icon: map['icon'] as String? ?? 'label',
      colorHex: map['color_hex'] as String? ?? '#6366F1',
      sortOrder: (map['sort_order'] as int?) ?? 0,
      isDefault: (map['is_default'] as int? ?? 0) == 1,
      isSystem: (map['is_system'] as int? ?? 0) == 1,
      subType: map['sub_type'] as String? ?? '',
    );
  }
}

// ── Small helpers ────────────────────────────────────────────────────────────

/// Null-safe "first matching element" lookup without pulling in
/// package:collection.
T? firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

String capitalizeWords(String s) {
  if (s.isEmpty) return s;
  return s.split(' ').map((w) {
    if (w.isEmpty) return w;
    return w[0].toUpperCase() + w.substring(1);
  }).join(' ');
}

/// Bundles the three category groups together and provides convenient
/// lookups so pages don't need to repeatedly scan lists or fall back to
/// hard-coded constants.
class CategoryRegistry {
  final List<WalletCategory> accountTypes;
  final List<WalletCategory> accountCategories;
  final List<WalletCategory> transactionCategories;

  const CategoryRegistry({
    required this.accountTypes,
    required this.accountCategories,
    required this.transactionCategories,
  });

  factory CategoryRegistry.empty() => const CategoryRegistry(
        accountTypes: [],
        accountCategories: [],
        transactionCategories: [],
      );

  // ── Account types ───────────────────────────────────────────────────────

  WalletCategory? findAccountType(String name) =>
      firstWhereOrNull(accountTypes, (c) => c.name == name);

  Color typeColor(String name) =>
      findAccountType(name)?.color ?? const Color(0xFF6366F1);

  IconData typeIcon(String name) =>
      findAccountType(name)?.iconData ?? Icons.account_balance_wallet;

  List<Color> typeGradient(String name) => gradientForColor(typeColor(name));

  String typeLabel(String name) => capitalizeWords(name);

  String typeColorHex(String name) =>
      findAccountType(name)?.colorHex ?? '#6366F1';

  List<String> get accountTypeNames => accountTypes.map((c) => c.name).toList();

  String get defaultAccountType {
    final found = firstWhereOrNull(accountTypes, (c) => c.isDefault);
    if (found != null) return found.name;
    return accountTypes.isNotEmpty ? accountTypes.first.name : 'cash';
  }

  // ── Account categories ──────────────────────────────────────────────────

  List<String> get accountCategoryNames =>
      accountCategories.map((c) => c.name).toList();

  String get defaultAccountCategory {
    final found = firstWhereOrNull(accountCategories, (c) => c.isDefault);
    if (found != null) return found.name;
    return accountCategories.isNotEmpty
        ? accountCategories.first.name
        : 'personal';
  }

  // ── Transaction categories ──────────────────────────────────────────────

  /// All transaction categories *except* the system "Transfer" category —
  /// this is the list shown in the add/edit transaction form.
  /// Miscellaneous (also system) IS included so it appears as a pick option.
  List<WalletCategory> get selectableTransactionCategories =>
      transactionCategories
          .where((c) => c.name != kTransferCategoryName)
          .toList();

  WalletCategory? findTransactionCategory(String name) =>
      firstWhereOrNull(transactionCategories, (c) => c.name == name);

  IconData transactionCategoryIcon(String name) =>
      findTransactionCategory(name)?.iconData ?? Icons.category;

  String get defaultTransactionCategory {
    final found = firstWhereOrNull(
        transactionCategories, (c) => c.isDefault && !c.isSystem);
    if (found != null) return found.name;
    final firstSelectable = selectableTransactionCategories;
    return firstSelectable.isNotEmpty ? firstSelectable.first.name : 'Other';
  }
}
