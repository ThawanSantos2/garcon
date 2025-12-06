// ignore_for_file: unused_field, unused_local_variable

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import 'dart:typed_data';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Uuid _uuid = const Uuid();

  // ==========================================
  // USUÁRIOS
  // ==========================================

  Future<Map<String, dynamic>?> getUserData(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      return doc.data();
    } catch (e) {
      throw Exception('Erro ao obter dados do usuário: $e');
    }
  }

  Future<void> updateUserData(
    String userId,
    Map<String, dynamic> data,
  ) async {
    try {
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _firestore.collection('users').doc(userId).update(data);
    } catch (e) {
      throw Exception('Erro ao atualizar dados: $e');
    }
  }

  // ==========================================
  // ESTABELECIMENTO - CRIAÇÃO E ATUALIZAÇÃO
  // ==========================================

  Future<String> createEstablishment({
    required String userId,
    required String name,
    required String address,
    required String phone,
    required String email,
  }) async {
    try {
      final establishmentId = _uuid.v4();

      await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .set({
        'id': establishmentId,
        'ownerId': userId,
        'name': name,
        'address': address,
        'phone': phone,
        'email': email,
        'totalTables': 0,
        'totalWaiters': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'subscriptionStatus': 'trial',
        'subscriptionEndDate': DateTime.now().add(const Duration(days: 7)),
        'stats': {
          'totalOrders': 0,
          'totalRevenue': 0,
          'avgServiceTime': 0,
        },
      });

      // Atualizar usuário com estabelecimento
      await _firestore.collection('users').doc(userId).update({
        'establishmentId': establishmentId,
        'role': 'estabelecimento',
      });

      return establishmentId;
    } catch (e) {
      throw Exception('Erro ao criar estabelecimento: $e');
    }
  }

  Future<Map<String, dynamic>?> getEstablishmentData(
    String establishmentId,
  ) async {
    try {
      final doc = await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .get();
      return doc.data();
    } catch (e) {
      throw Exception('Erro ao obter dados do estabelecimento: $e');
    }
  }

  Future<void> updateEstablishmentData(
    String establishmentId,
    Map<String, dynamic> data,
  ) async {
    try {
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .update(data);
    } catch (e) {
      throw Exception('Erro ao atualizar estabelecimento: $e');
    }
  }

  Future<void> deleteEstablishment(String establishmentId) async {
    try {
      await _firestore.collection('establishments').doc(establishmentId).delete();
    } catch (e) {
      throw Exception('Erro ao deletar estabelecimento: $e');
    }
  }

  // ==========================================
  // MESAS
  // ==========================================

  Future<String> createTable( {
    required String establishmentId,
    required String name,
    required int capacity,
  }) async {
    try {
      final tableId = _uuid.v4();
      final qrCodeData =
          'est:$establishmentId|table:$name|id:$tableId|capacity:$capacity';

      await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .collection('tables')
          .doc(tableId)
          .set({
        'id': tableId,
        'name': name,
        'capacity': capacity,
        'qrCode': qrCodeData,
        'status': 'available',
        'isOccupied': false,
        'currentCustomerId': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return qrCodeData;
    } catch (e) {
      throw Exception('Erro ao criar mesa: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getTables(String establishmentId) async {
    try {
      final snapshot = await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .collection('tables')
          .get();

      return snapshot.docs
          .map((doc) => {...doc.data(), 'id': doc.id})
          .toList();
    } catch (e) {
      throw Exception('Erro ao obter mesas: $e');
    }
  }

  Future<void> updateTable(
    String establishmentId,
    String tableId,
    Map<String, dynamic> data,
  ) async {
    try {
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .collection('tables')
          .doc(tableId)
          .update(data);
    } catch (e) {
      throw Exception('Erro ao atualizar mesa: $e');
    }
  }

  Future<void> deleteTable(String establishmentId, String tableId) async {
    try {
      await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .collection('tables')
          .doc(tableId)
          .delete();
    } catch (e) {
      throw Exception('Erro ao deletar mesa: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getTableOrderHistory(
    String tableId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('orders')
          .where('tableId', isEqualTo: tableId)
          .where('createdAt',
              isGreaterThan: Timestamp.fromDate(
                  DateTime.now().subtract(const Duration(days: 1))))
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => {...doc.data(), 'id': doc.id})
          .toList();
    } catch (e) {
      throw Exception('Erro ao obter histórico: $e');
    }
  }

  Stream<QuerySnapshot> getEstablishmentTables(String establishmentId) {
    return _firestore
        .collection('establishments')
        .doc(establishmentId)
        .collection('tables')
        .snapshots();
  }

  // ==========================================
  // PEDIDOS
  // ==========================================

  Future<void> createOrder({
    required String establishmentId,
    required String customerId,
    required String tableId,
    required String sessionId,
    required List<Map<String, dynamic>> items,
    required String notes,
    String? assignedWaiter,
  }) async {
    try {
      final orderId = _uuid.v4();

      await _firestore.collection('orders').doc(orderId).set({
        'id': orderId,
        'establishmentId': establishmentId,
        'customerId': customerId,
        'tableId': tableId,
        'sessionId': sessionId,
        'items': items,
        'notes': notes,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'assignedWaiter': assignedWaiter,
        'acceptedAt': null,
        'completedAt': null,
        'totalPrice': _calculateTotal(items),
      });
    } catch (e) {
      throw Exception('Erro ao criar pedido: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getRecentOrders(
    String establishmentId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('orders')
          .where('establishmentId', isEqualTo: establishmentId)
          .where('createdAt',
              isGreaterThan: Timestamp.fromDate(
                  DateTime.now().subtract(const Duration(hours: 5))))
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => {...doc.data(), 'id': doc.id})
          .toList();
    } catch (e) {
      throw Exception('Erro ao obter pedidos: $e');
    }
  }

  Future<void> updateOrderStatus(String orderId, String status) async {
    try {
      await _firestore.collection('orders').doc(orderId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Erro ao atualizar pedido: $e');
    }
  }

  Stream<QuerySnapshot> getOrdersStream(String establishmentId) {
    return _firestore
        .collection('orders')
        .where('establishmentId', isEqualTo: establishmentId)
        .where('createdAt',
            isGreaterThan: Timestamp.fromDate(
                DateTime.now().subtract(const Duration(hours: 5))))
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> getWaiterOrders(String waiterId) {
    return _firestore
        .collection('orders')
        .where('assignedWaiter', isEqualTo: waiterId)
        .where('status', isNotEqualTo: 'completed')
        .snapshots();
  }

  double _calculateTotal(List<Map<String, dynamic>> items) {
    double total = 0;
    for (var item in items) {
      total += (item['price'] as num? ?? 0).toDouble() *
          (item['quantity'] as num? ?? 1).toDouble();
    }
    return total;
  }

  // ==========================================
  // GARÇONS
  // ==========================================

  Future<String> createWaiterQR({required String waiterId}) async {
    try {
      final qrCodeData =
          'waiter:$waiterId|created:${DateTime.now().toIso8601String()}';

      await _firestore.collection('users').doc(waiterId).update({
        'waiterQrCode': qrCodeData,
      });

      return qrCodeData;
    } catch (e) {
      throw Exception('Erro ao criar QR do garçom: $e');
    }
  }

  Future<void> addWaiter({
    required String establishmentId,
    required String waiterId,
  }) async {
    try {
      await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .collection('waiters')
          .doc(waiterId)
          .set({
        'id': waiterId,
        'isActive': true,
        'totalOrders': 0,
        'avgResponseTime': 0,
        'addedAt': FieldValue.serverTimestamp(),
      });

      // Atualizar usuário
      await _firestore.collection('users').doc(waiterId).update({
        'establishmentId': establishmentId,
        'role': 'garcom',
        'status': 'available',
      });
    } catch (e) {
      throw Exception('Erro ao adicionar garçom: $e');
    }
  }

  Future<void> removeWaiter({
    required String establishmentId,
    required String waiterId,
  }) async {
    try {
      await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .collection('waiters')
          .doc(waiterId)
          .delete();
    } catch (e) {
      throw Exception('Erro ao remover garçom: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getWaiters(String establishmentId) async {
    try {
      final snapshot = await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .collection('waiters')
          .get();

      return snapshot.docs
          .map((doc) => {...doc.data(), 'id': doc.id})
          .toList();
    } catch (e) {
      throw Exception('Erro ao obter garçons: $e');
    }
  }

  Stream<QuerySnapshot> getEstablishmentWaiters(String establishmentId) {
    return _firestore
        .collection('establishments')
        .doc(establishmentId)
        .collection('waiters')
        .snapshots();
  }

  // ==========================================
  // CLIENTES
  // ==========================================

  Future<void> addClient(
    String establishmentId,
    String clientId,
    Map<String, dynamic> clientData,
  ) async {
    try {
      await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .collection('clients')
          .doc(clientId)
          .set({
        ...clientData,
        'addedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Erro ao adicionar cliente: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getClients(String establishmentId) async {
    try {
      final snapshot = await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .collection('clients')
          .get();

      return snapshot.docs
          .map((doc) => {...doc.data(), 'id': doc.id})
          .toList();
    } catch (e) {
      throw Exception('Erro ao obter clientes: $e');
    }
  }

  Future<int> getTotalClients(String establishmentId) async {
    try {
      final snapshot = await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .collection('clients')
          .get();

      return snapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }

  // ==========================================
  // SESSÕES DE CLIENTE
  // ==========================================

  Future<String> createCustomerSession({
    required String establishmentId,
    required String tableId,
    required String customerId,
  }) async {
    try {
      final sessionId = _uuid.v4();

      await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .collection('sessions')
          .doc(sessionId)
          .set({
        'id': sessionId,
        'customerId': customerId,
        'tableId': tableId,
        'establishmentId': establishmentId,
        'startTime': FieldValue.serverTimestamp(),
        'endTime': null,
        'isActive': true,
        'totalBill': 0,
      });

      // Atualizar status da mesa
      await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .collection('tables')
          .doc(tableId)
          .update({
        'isOccupied': true,
        'currentCustomerId': customerId,
      });

      // Atualizar usuário
      await _firestore.collection('users').doc(customerId).update({
        'currentSessionId': sessionId,
        'currentEstablishmentId': establishmentId,
      });

      return sessionId;
    } catch (e) {
      throw Exception('Erro ao criar sessão: $e');
    }
  }

  // ==========================================
  // ALERTAS DE GARÇOM
  // ==========================================

  Future<void> callWaiter({
    required String establishmentId,
    required String customerId,
    required String tableId,
    required String reason,
  }) async {
    try {
      final alertId = _uuid.v4();

      await _firestore.collection('waiter_alerts').doc(alertId).set({
        'id': alertId,
        'establishmentId': establishmentId,
        'customerId': customerId,
        'tableId': tableId,
        'reason': reason,
        'message': 'Cliente na mesa $tableId chamando: $reason',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'acknowledgedAt': null,
      });
    } catch (e) {
      throw Exception('Erro ao chamar garçom: $e');
    }
  }

  Future<void> createClientAlert(
    String establishmentId,
    String tableId,
    String clientId,
    String message,
  ) async {
    try {
      await _firestore.collection('waiter_alerts').add({
        'establishmentId': establishmentId,
        'tableId': tableId,
        'clientId': clientId,
        'message': message,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'resolvedAt': null,
      });
    } catch (e) {
      throw Exception('Erro ao criar alerta: $e');
    }
  }

  Future<void> resolveAlert(String alertId) async {
    try {
      await _firestore.collection('waiter_alerts').doc(alertId).update({
        'status': 'resolved',
        'resolvedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Erro ao resolver alerta: $e');
    }
  }

  Stream<QuerySnapshot> getAlertsStream(String establishmentId) {
    return _firestore
        .collection('waiter_alerts')
        .where('establishmentId', isEqualTo: establishmentId)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ==========================================
  // ESTATÍSTICAS
  // ==========================================

  Future<Map<String, dynamic>> getEstablishmentStatistics(
    String establishmentId,
  ) async {
    try {
      // Total de clientes
      final clientsSnap = await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .collection('clients')
          .get();

      // Total de garçons
      final waitersSnap = await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .collection('waiters')
          .get();

      // Pedidos últimos 7 dias
      final ordersSnap = await _firestore
          .collection('orders')
          .where('establishmentId', isEqualTo: establishmentId)
          .where('createdAt',
              isGreaterThan: Timestamp.fromDate(
                  DateTime.now().subtract(const Duration(days: 7))))
          .get();

      // Pedidos últimos 30 dias
      final ordersMonthSnap = await _firestore
          .collection('orders')
          .where('establishmentId', isEqualTo: establishmentId)
          .where('createdAt',
              isGreaterThan: Timestamp.fromDate(
                  DateTime.now().subtract(const Duration(days: 30))))
          .get();

      // Receita total (últimos 7 dias)
      double revenue = 0;
      for (var doc in ordersSnap.docs) {
        final data = doc.data();
        revenue += (data['totalPrice'] as num?)?.toDouble() ?? 0;
      }

      return {
        'totalClients': clientsSnap.docs.length,
        'totalWaiters': waitersSnap.docs.length,
        'ordersLast7Days': ordersSnap.docs.length,
        'ordersLast30Days': ordersMonthSnap.docs.length,
        'revenueLast7Days': revenue,
        'averageOrderValue':
            ordersSnap.docs.isEmpty ? 0 : revenue / ordersSnap.docs.length,
      };
    } catch (e) {
      throw Exception('Erro ao obter estatísticas: $e');
    }
  }

  Future<Map<String, dynamic>> getEstablishmentStats(
    String establishmentId,
  ) async {
    try {
      final establishment = await getEstablishmentData(establishmentId);
      final ordersSnapshot = await _firestore
          .collection('orders')
          .where('establishmentId', isEqualTo: establishmentId)
          .where('status', isEqualTo: 'completed')
          .get();

      final waitersSnapshot = await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .collection('waiters')
          .get();

      return {
        'establishment': establishment,
        'totalOrders': ordersSnapshot.docs.length,
        'totalWaiters': waitersSnapshot.docs.length,
        'avgServiceTime': _calculateAvgServiceTime(ordersSnapshot.docs),
      };
    } catch (e) {
      throw Exception('Erro ao obter estatísticas: $e');
    }
  }

  double _calculateAvgServiceTime(List<DocumentSnapshot> orders) {
    if (orders.isEmpty) return 0;
    double total = 0;

    for (var order in orders) {
      final createdAt =
          (order['createdAt'] as Timestamp?)?.toDate();
      final completedAt =
          (order['completedAt'] as Timestamp?)?.toDate();

      if (createdAt != null && completedAt != null) {
        total += completedAt.difference(createdAt).inSeconds.toDouble();
      }
    }

    return total / orders.length;
  }

  // ==========================================
  // PAGAMENTOS
  // ==========================================

  Future<void> recordSubscriptionPayment({
    required String userId,
    required String establishmentId,
    required double amount,
    required String transactionId,
    required String platform,
  }) async {
    try {
      await _firestore.collection('payments').add({
        'userId': userId,
        'establishmentId': establishmentId,
        'amount': amount,
        'transactionId': transactionId,
        'platform': platform,
        'type': 'subscription',
        'status': 'completed',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Atualizar status de subscrição
      await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .update({
        'subscriptionStatus': 'active',
        'subscriptionEndDate':
            DateTime.now().add(const Duration(days: 30)),
        'lastPaymentDate': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Erro ao registrar pagamento: $e');
    }
  }

  // ==========================================
  // NOTIFICAÇÕES
  // ==========================================

  Future<void> sendNotificationToWaiters({
    required String establishmentId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'establishmentId': establishmentId,
        'title': title,
        'body': body,
        'data': data,
        'createdAt': FieldValue.serverTimestamp(),
        'type': 'waiter_alert',
      });
    } catch (e) {
      throw Exception('Erro ao enviar notificação: $e');
    }
  }

  // ==========================================
  // STORAGE (Imagens)
  // ==========================================

  Future<String> uploadEstablishmentImage({
    required String establishmentId,
    required String fileName,
    required List<int> fileBytes,
  }) async {
    try {
      final ref = _storage.ref().child(
          'establishments/$establishmentId/images/$fileName');

      final Uint8List fixedBytes = Uint8List.fromList(fileBytes);
      
      await ref.putData(
        Uint8List.fromList(fileBytes),
        SettableMetadata(contentType: 'image/jpeg'),
      );

      return await ref.getDownloadURL();
    } catch (e) {
      throw Exception('Erro ao fazer upload: $e');
    }
  }

  Future<void> deleteFile(String filePath) async {
    try {
      await _storage.ref(filePath).delete();
    } catch (e) {
      throw Exception('Erro ao deletar arquivo: $e');
    }
  }
}
