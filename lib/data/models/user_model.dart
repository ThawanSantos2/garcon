class UserModel {
  final String uid;
  final String name;
  final String email;
  final String phoneNumber;
  final String role; // cliente, garcom, estabelecimento
  final String? establishmentId;
  final String? currentSessionId;
  final String? profileImageUrl;
  final bool isActive;
  final String? fcmToken;
  final DateTime createdAt;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phoneNumber,
    required this.role,
    this.establishmentId,
    this.currentSessionId,
    this.profileImageUrl,
    required this.isActive,
    this.fcmToken,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      uid: json['uid'],
      name: json['name'],
      email: json['email'],
      phoneNumber: json['phoneNumber'],
      role: json['role'],
      establishmentId: json['establishmentId'],
      currentSessionId: json['currentSessionId'],
      profileImageUrl: json['profileImageUrl'],
      isActive: json['isActive'] ?? true,
      fcmToken: json['fcmToken'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'name': name,
    'email': email,
    'phoneNumber': phoneNumber,
    'role': role,
    'establishmentId': establishmentId,
    'currentSessionId': currentSessionId,
    'profileImageUrl': profileImageUrl,
    'isActive': isActive,
    'fcmToken': fcmToken,
    'createdAt': createdAt.toIso8601String(),
  };
}