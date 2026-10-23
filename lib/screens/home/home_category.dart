/// A parcel category shown in the home screen's "Send Anything, Anywhere"
/// grid, sourced from `GET /home`.
class HomeCategory {
  const HomeCategory({required this.id, required this.name, this.iconUrl});

  final int id;
  final String name;
  final String? iconUrl;

  factory HomeCategory.fromJson(Map<String, dynamic> json) {
    return HomeCategory(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      iconUrl: json['icon'] as String?,
    );
  }
}
