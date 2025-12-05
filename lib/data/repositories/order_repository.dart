import '../models/order_model.dart';

abstract class OrderRepository {
  Future<String> createOrder(OrderModel order);
  Future<void> updateOrderStatus(String orderId, String status);
  Future<OrderModel?> getOrderById(String orderId);
  Future<List<OrderModel>> getOrdersByEstablishment(String establishmentId);
  Future<List<OrderModel>> getOrdersByCustomer(String customerId);
  Stream<List<OrderModel>> watchOrdersByEstablishment(String establishmentId);
  Stream<List<OrderModel>> watchOrdersByWaiter(String waiterId);
}