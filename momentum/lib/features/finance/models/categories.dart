enum CategoryKind {
  income('income'),
  expense('expense');

  final String dbValue;
  const CategoryKind(this.dbValue);

  static CategoryKind fromDb(String? value) => CategoryKind.values.firstWhere(
        (k) => k.dbValue == value,
        orElse: () => CategoryKind.expense,
      );
}

/// A row of the `categories` table (Food & Dining, Salary, ...).
class TransactionCategory {
  final int? id;
  final String name;
  final CategoryKind kind;
  final String? icon;
  final int? color;

  const TransactionCategory({
    this.id,
    required this.name,
    required this.kind,
    this.icon,
    this.color,
  });

  factory TransactionCategory.fromMap(Map<String, Object?> m) =>
      TransactionCategory(
        id: m['id'] as int?,
        name: m['name'] as String,
        kind: CategoryKind.fromDb(m['kind'] as String?),
        icon: m['icon'] as String?,
        color: m['color'] as int?,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'kind': kind.dbValue,
        'icon': icon,
        'color': color,
      };
}