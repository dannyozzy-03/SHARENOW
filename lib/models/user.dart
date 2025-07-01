class UserModel {
  final String id;
  final String bannerImageUrl;
  final String profileImageUrl;
  final String name;
  final String email;
  final String role;
  final String? phoneNumber;

  // Constructor
  UserModel({
    required this.id,
    required this.bannerImageUrl,
    required this.profileImageUrl,
    required this.name,
    required this.email,
    required this.role,
    this.phoneNumber,
  });

  // Factory method to convert Firestore data into UserModel
  factory UserModel.fromMap(String id, Map<String, dynamic> data) {
    return UserModel(
      id: id,
      bannerImageUrl: data['bannerImageUrl'] ?? '',
      profileImageUrl: data['profileImageUrl'] ?? '',
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      role: data['role'] ?? 'user',
      phoneNumber: data['phoneNumber'],
    );
  }
}
