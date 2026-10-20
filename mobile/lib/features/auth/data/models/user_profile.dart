class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.preferredLanguage,
    required this.isActive,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String email;
  final String preferredLanguage;
  final bool isActive;
  final DateTime createdAt;
}
