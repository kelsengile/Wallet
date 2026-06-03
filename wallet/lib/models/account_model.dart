class Account {
  final int? id;
  final String name;
  final double balance;
  final String type; // 'cash', 'bank', 'e-wallet'
  final String colorHex;
  final String icon;

  Account({
    this.id,
    required this.name,
    required this.balance,
    required this.type,
    required this.colorHex,
    required this.icon,
  });

  Account copyWith({
    int? id,
    String? name,
    double? balance,
    String? type,
    String? colorHex,
    String? icon,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      balance: balance ?? this.balance,
      type: type ?? this.type,
      colorHex: colorHex ?? this.colorHex,
      icon: icon ?? this.icon,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'balance': balance,
      'type': type,
      'color_hex': colorHex,
      'icon': icon,
    };
  }

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'] as int?,
      name: map['name'] as String,
      balance: (map['balance'] as num).toDouble(),
      type: map['type'] as String,
      colorHex: map['color_hex'] as String,
      icon: map['icon'] as String,
    );
  }
}
