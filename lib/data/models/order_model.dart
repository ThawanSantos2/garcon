class OrderModel {
  final String id;
  final String establishmentId;
  final String customerId;
  final String tableId;
  final List<OrderItem> items;
  final String notes;
  final String status; // pending, accepted, preparing, ready, completed
  final String? assignedWaiter;
  final double totalAmount;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? completedAt;

  OrderModel({
    required this.id,
    required this.establishmentId,
    required this.customerId,
    required this.tableId,
    required this.items,
    required this.notes,
    required this.status,
    this.assignedWaiter,
    required this.totalAmount,
    required this.createdAt,
    this.acceptedAt,
    this.completedAt,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      id: json['id'],
      establishmentId: json['establishmentId'],
      customerId: json['customerId'],
      tableId: json['tableId'],
      items: List<OrderItem>.from(
        (json['items'] as List).map((item) => OrderItem.fromJson(item))
      ),
      notes: json['notes'],
      status: json['status'],
      assignedWaiter: json['assignedWaiter'],
      totalAmount: json['totalAmount']?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(json['createdAt']),
      acceptedAt: json['acceptedAt'] != null 
        ? DateTime.parse(json['acceptedAt']) 
        : null,
      completedAt: json['completedAt'] != null 
        ? DateTime.parse(json['completedAt']) 
        : null,
    );
  }
}

class OrderItem {
  final String id;
  final String name;
  final int quantity;
  final double price;
  final String? notes;

  OrderItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.price,
    this.notes,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'],
      name: json['name'],
      quantity: json['quantity'],
      price: json['price']?.toDouble() ?? 0.0,
      notes: json['notes'],
    );
  }
}