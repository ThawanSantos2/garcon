// ignore_for_file: unused_field

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Uuid _uuid = const Uuid();

  // ======================== ESTABELECIMENTO ========================
  
  Future<void> createEstablishment({
    required String userId,
    required String name,
    required String address,
    required String phone,
    required String email,
  }) async {
    final establishmentId = _uuid.v4();
    
    await _firestore.collection('establishments').doc(establishmentId).set({
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
      'subscriptionStatus': 'trial', // trial, active, cancelled
      'subscriptionEndDate': DateTime.now().add(const Duration(days: 7)),
      'stats': {
        'totalOrders': 0,
        'totalRevenue': 0,
        'avgServiceTime': 0,
      },
    });

    // Update user with establishment
    await _firestore.collection('users').doc(userId).update({
      'establishmentId': establishmentId,
      'role': 'estabelecimento',
    });
  }

  Future<String> createTable({
    required String establishmentId,
    required String tableNumber,
  }) async {
    final tableId = _uuid.v4();
    final qrCodeData = 'est:$establishmentId|table:$tableNumber|id:$tableId';

    await _firestore
        .collection('establishments')
        .doc(establishmentId)
        .collection('tables')
        .doc(tableId)
        .set({
      'id': tableId,
      'tableNumber': tableNumber,
      'qrCode': qrCodeData,
      'isOccupied': false,
      'currentCustomerId': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return qrCodeData;
  }

  Future<void> addWaiter({
    required String establishmentId,
    required String waiterId,
  }) async {
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

    // Update user
    await _firestore.collection('users').doc(waiterId).update({
      'establishmentId': establishmentId,
      'role': 'garcom',
      'status': 'available',
    });
  }

  Future<void> removeWaiter({
    required String establishmentId,
    required String waiterId,
  }) async {
    await _firestore
        .collection('establishments')
        .doc(establishmentId)
        .collection('waiters')
        .doc(waiterId)
        .delete();
  }

  Future<Map<String, dynamic>?> getEstablishmentById(
      String establishmentId) async {
    final doc =
        await _firestore.collection('establishments').doc(establishmentId).get();
    return doc.data();
  }

  Stream<QuerySnapshot> getEstablishmentWaiters(String establishmentId) {
    return _firestore
        .collection('establishments')
        .doc(establishmentId)
        .collection('waiters')
        .snapshots();
  }

  Stream<QuerySnapshot> getEstablishmentTables(String establishmentId) {
    return _firestore
        .collection('establishments')
        .doc(establishmentId)
        .collection('tables')
        .snapshots();
  }

  // ======================== GARÇOM ========================

  Future<String> createWaiterQR({required String waiterId}) async {
    final qrCodeData = 'waiter:$waiterId|created:${DateTime.now()}';
    
    await _firestore.collection('users').doc(waiterId).update({
      'waiterQrCode': qrCodeData,
    });

    return qrCodeData;
  }

  Stream<QuerySnapshot> getWaiterOrders(String waiterId) {
    return _firestore
        .collection('orders')
        .where('assignedWaiter', isEqualTo: waiterId)
        .where('status', isNotEqualTo: 'completed')
        .snapshots();
  }

  // ======================== CLIENTE ========================

  Future<void> createCustomerSession({
    required String establishmentId,
    required String tableId,
    required String customerId,
  }) async {
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

    // Update table status
    await _firestore
        .collection('establishments')
        .doc(establishmentId)
        .collection('tables')
        .doc(tableId)
        .update({
      'isOccupied': true,
      'currentCustomerId': customerId,
    });

    // Update user
    await _firestore.collection('users').doc(customerId).update({
      'currentSessionId': sessionId,
      'currentEstablishmentId': establishmentId,
    });
  }

  Future<void> createOrder({
    required String establishmentId,
    required String customerId,
    required String tableId,
    required String sessionId,
    required List<Map<String, dynamic>> items,
    required String notes,
  }) async {
    final orderId = _uuid.v4();

    await _firestore.collection('orders').doc(orderId).set({
      'id': orderId,
      'establishmentId': establishmentId,
      'customerId': customerId,
      'tableId': tableId,
      'sessionId': sessionId,
      'items': items,
      'notes': notes,
      'status': 'pending', // pending, accepted, preparing, ready, completed
      'createdAt': FieldValue.serverTimestamp(),
      'assignedWaiter': null,
      'acceptedAt': null,
      'completedAt': null,
    });
  }

  Future<void> callWaiter({
    required String establishmentId,
    required String customerId,
    required String tableId,
    required String reason,
  }) async {
    final alertId = _uuid.v4();

    await _firestore.collection('waiter_alerts').doc(alertId).set({
      'id': alertId,
      'establishmentId': establishmentId,
      'customerId': customerId,
      'tableId': tableId,
      'reason': reason,
      'status': 'pending', // pending, acknowledged, completed
      'createdAt': FieldValue.serverTimestamp(),
      'acknowledgedAt': null,
    });
  }

  // ======================== PAGAMENTOS ========================

  Future<void> recordSubscriptionPayment({
    required String userId,
    required String establishmentId,
    required double amount,
    required String transactionId,
    required String platform, // android ou ios
  }) async {
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

    // Update subscription status
    await _firestore.collection('establishments').doc(establishmentId).update({
      'subscriptionStatus': 'active',
      'subscriptionEndDate':
          DateTime.now().add(const Duration(days: 30)), // 1 month subscription
      'lastPaymentDate': FieldValue.serverTimestamp(),
    });
  }

  // ======================== NOTIFICAÇÕES ========================

  Future<void> sendNotificationToWaiters({
    required String establishmentId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    // This will be handled by Cloud Functions
    await _firestore.collection('notifications').add({
      'establishmentId': establishmentId,
      'title': title,
      'body': body,
      'data': data,
      'createdAt': FieldValue.serverTimestamp(),
      'type': 'waiter_alert',
    });
  }

  // ======================== ESTATÍSTICAS ========================

  Future<Map<String, dynamic>> getEstablishmentStats(
      String establishmentId) async {
    final establishment = await getEstablishmentById(establishmentId);

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
  }

  double _calculateAvgServiceTime(List<QueryDocumentSnapshot> orders) {
    if (orders.isEmpty) return 0;

    double total = 0;
    for (var order in orders) {
      final createdAt = (order['createdAt'] as Timestamp?)?.toDate();
      final completedAt = (order['completedAt'] as Timestamp?)?.toDate();

      if (createdAt != null && completedAt != null) {
        total += completedAt.difference(createdAt).inSeconds.toDouble();
      }
    }

    return total / orders.length;
  }

  Future<void> deleteEstablishment(String establishmentId) async {
    await _firestore.collection('establishments').doc(establishmentId).delete();
  }
}
