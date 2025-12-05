class EstablishmentModel {
  final String id;
  final String ownerId;
  final String name;
  final String address;
  final String phone;
  final String email;
  final int totalTables;
  final int totalWaiters;
  final String? profileImageUrl;
  final String subscriptionStatus; // trial, active, cancelled
  final DateTime subscriptionEndDate;
  final DateTime? lastPaymentDate;
  final EstablishmentStats stats;
  final bool isActive;
  final DateTime createdAt;

  EstablishmentModel({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.address,
    required this.phone,
    required this.email,
    required this.totalTables,
    required this.totalWaiters,
    this.profileImageUrl,
    required this.subscriptionStatus,
    required this.subscriptionEndDate,
    this.lastPaymentDate,
    required this.stats,
    required this.isActive,
    required this.createdAt,
  });

  factory EstablishmentModel.fromJson(Map<String, dynamic> json) {
    return EstablishmentModel(
      id: json['id'],
      ownerId: json['ownerId'],
      name: json['name'],
      address: json['address'],
      phone: json['phone'],
      email: json['email'],
      totalTables: json['totalTables'] ?? 0,
      totalWaiters: json['totalWaiters'] ?? 0,
      profileImageUrl: json['profileImageUrl'],
      subscriptionStatus: json['subscriptionStatus'] ?? 'trial',
      subscriptionEndDate: DateTime.parse(json['subscriptionEndDate']),
      lastPaymentDate: json['lastPaymentDate'] != null
        ? DateTime.parse(json['lastPaymentDate'])
        : null,
      stats: EstablishmentStats.fromJson(json['stats'] ?? {}),
      isActive: json['isActive'] ?? true,
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

class EstablishmentStats {
  final int totalOrders;
  final double totalRevenue;
  final double avgServiceTime;

  EstablishmentStats({
    required this.totalOrders,
    required this.totalRevenue,
    required this.avgServiceTime,
  });

  factory EstablishmentStats.fromJson(Map<String, dynamic> json) {
    return EstablishmentStats(
      totalOrders: json['totalOrders'] ?? 0,
      totalRevenue: (json['totalRevenue'] ?? 0).toDouble(),
      avgServiceTime: (json['avgServiceTime'] ?? 0).toDouble(),
    );
  }
}