class User {
  final String id;
  final String email;
  final String? name;
  final String? role;

  const User({
    required this.id,
    required this.email,
    this.name,
    this.role,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: (json['id'] ?? '').toString(),
        email: json['email'] ?? json['username'] ?? '',
        name: json['name'] ?? json['fullName'],
        role: json['role']?.toString(),
      );
}
