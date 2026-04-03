/// Простые справочные сущности для формы создания кампании.

class Customer {
  final int id;
  final String name;
  const Customer({required this.id, required this.name});

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: (json['id'] as num).toInt(),
        name: json['name']?.toString() ?? '',
      );
}

class Brand {
  final int id;
  final String name;
  const Brand({required this.id, required this.name});

  factory Brand.fromJson(Map<String, dynamic> json) => Brand(
        id: (json['id'] as num).toInt(),
        name: json['name']?.toString() ?? '',
      );
}

class Region {
  final int id;
  final String name;
  const Region({required this.id, required this.name});

  factory Region.fromJson(Map<String, dynamic> json) => Region(
        id: (json['id'] as num).toInt(),
        name: json['name']?.toString() ?? '',
      );
}
