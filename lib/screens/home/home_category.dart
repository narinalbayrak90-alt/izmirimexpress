/// A parcel category shown in the home screen's "Send Anything, Anywhere"
/// grid, sourced from `GET /home`.
class HomeCategory {
  const HomeCategory({required this.id, required this.name, this.description, this.iconUrl});

  final int id;
  final String name;

  /// Admin-written note on what fits this category; null when there's none.
  final String? description;
  final String? iconUrl;

  factory HomeCategory.fromJson(Map<String, dynamic> json) {
    return HomeCategory(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      description: (json['description'] as String?)?.trim().isEmpty ?? true ? null : (json['description'] as String).trim(),
      iconUrl: json['icon'] as String?,
    );
  }
}
