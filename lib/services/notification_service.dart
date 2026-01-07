// ignore_for_file: avoid_print

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:io';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  // ==========================================
  // INICIALIZAR NOTIFICAÇÕES
  // ==========================================

  Future<void> initializeNotifications() async {
    try {
      // Solicitar permissão
      NotificationSettings settings =
          await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
        providesAppNotificationSettings: false,
      );

      debugPrint('Permissão de notificação: ${settings.authorizationStatus}');

      // Obter token FCM
      final token = await _firebaseMessaging.getToken();
      debugPrint('Token FCM: $token');

      // Ouvir mensagens em foreground
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Ouvir quando o app é aberto clicando na notificação
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // Configurar notificações em background (para iOS)
      if (Platform.isIOS) {
        await _firebaseMessaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      debugPrint('Notificações inicializadas com sucesso');
    } catch (e) {
      debugPrint('Erro ao inicializar notificações: $e');
    }
  }

  // ==========================================
  // OBTER TOKEN FCM DO USUÁRIO
  // ==========================================

  Future<String?> getUserFCMToken() async {
    try {
      final token = await _firebaseMessaging.getToken();
      return token;
    } catch (e) {
      debugPrint('Erro ao obter token FCM: $e');
      return null;
    }
  }

  // ==========================================
  // SALVAR TOKEN FCM NO FIRESTORE
  // ==========================================

  Future<void> saveFCMTokenToFirestore(String userId, String token) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('Token FCM salvo para usuário: $userId');
    } catch (e) {
      debugPrint('Erro ao salvar token FCM: $e');
    }
  }

  // ==========================================
  // ENVIAR NOTIFICAÇÃO DE NOVO PEDIDO (GARÇOM)
  // ==========================================

  Future<void> sendNewOrderNotificationToWaiter({
    required String waiterId,
    required String orderNumber,
    required String tableNumber,
    required int itemCount,
  }) async {
    try {
      // 1. Obter token FCM do garçom
      final waiterDoc = await _firestore.collection('users').doc(waiterId).get();
      final fcmToken = waiterDoc['fcmToken'] as String?;

      if (fcmToken == null) {
        debugPrint('Token FCM não encontrado para garçom: $waiterId');
        return;
      }

      // 2. Salvar notificação no Firestore
      await _firestore.collection('notifications').add({
        'userId': waiterId,
        'type': 'new_order',
        'title': 'Novo Pedido!',
        'body': 'Mesa $tableNumber - $itemCount itens',
        'orderNumber': orderNumber,
        'tableNumber': tableNumber,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint(
          'Notificação de novo pedido enviada para garçom: $waiterId');
    } catch (e) {
      debugPrint('Erro ao enviar notificação de novo pedido: $e');
    }
  }

  // ==========================================
  // ENVIAR NOTIFICAÇÃO DE MUDANÇA DE STATUS (CLIENTE)
  // ==========================================

  Future<void> sendOrderStatusNotificationToClient({
    required String clientId,
    required String orderNumber,
    required String newStatus,
    required String tableNumber,
  }) async {
    try {
      // 1. Obter token FCM do cliente
      final clientDoc = await _firestore.collection('users').doc(clientId).get();
      final fcmToken = clientDoc['fcmToken'] as String?;

      if (fcmToken == null) {
        debugPrint('Token FCM não encontrado para cliente: $clientId');
        return;
      }

      // 2. Definir mensagem baseada no status
      final statusMessages = {
        'preparing': 'Seu pedido está sendo preparado!',
        'ready': 'Seu pedido está pronto! 🎉',
        'on_the_way': 'Seu pedido está a caminho!',
        'delivered': 'Seu pedido foi entregue! Bom apetite! 🍽️',
        'completed': 'Seu pedido foi completado!',
        'cancelled': 'Seu pedido foi cancelado.',
        'rejected': 'Seu pedido foi recusado.',
      };

      final statusEmojis = {
        'preparing': '👨‍🍳',
        'ready': '✅',
        'on_the_way': '🚴',
        'delivered': '🎉',
        'completed': '✅',
        'cancelled': '❌',
        'rejected': '⛔',
      };

      final message = statusMessages[newStatus] ?? 'Status do pedido atualizado';
      final emoji = statusEmojis[newStatus] ?? '';

      // 3. Salvar notificação no Firestore
      await _firestore.collection('notifications').add({
        'userId': clientId,
        'type': 'order_status',
        'title': '$emoji Atualização do Pedido',
        'body': message,
        'orderNumber': orderNumber,
        'tableNumber': tableNumber,
        'status': newStatus,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint(
          'Notificação de status enviada para cliente: $clientId - Status: $newStatus');
    } catch (e) {
      debugPrint('Erro ao enviar notificação de status: $e');
    }
  }

  // ==========================================
// ENVIAR NOTIFICAÇÃO DE CANCELAMENTO PARA GARÇOM(ÕES)
// ==========================================
Future<void> sendOrderCancelledNotification({
  required String establishmentId,
  required String orderId,
  required String? assignedWaiterId,  // Se null, notificar todos
  required String tableNumber,
}) async {
  try {
    if (assignedWaiterId != null) {
      // Notificar apenas o assignedWaiter
      final waiterDoc = await _firestore.collection('users').doc(assignedWaiterId).get();
      final fcmToken = waiterDoc['fcmToken'] as String?;
      if (fcmToken == null) return;

      await _firestore.collection('notifications').add({
        'userId': assignedWaiterId,
        'type': 'order_cancelled',
        'title': '❌ Pedido Cancelado',
        'body': 'O cliente cancelou o pedido da Mesa $tableNumber',
        'orderId': orderId,
        'tableNumber': tableNumber,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Notificar todos os garçons (para 'pending')
      final waitersSnapshot = await _firestore
          .collection('establishments')
          .doc(establishmentId)
          .collection('waiters')
          .get();
      for (var waiterDoc in waitersSnapshot.docs) {
        final waiterId = waiterDoc.id;
        final waiterUserDoc = await _firestore.collection('users').doc(waiterId).get();
        final fcmToken = waiterUserDoc['fcmToken'] as String?;
        if (fcmToken != null) {
          await _firestore.collection('notifications').add({
            'userId': waiterId,
            'type': 'order_cancelled',
            'title': '❌ Pedido Cancelado',
            'body': 'O cliente cancelou um pedido pendente da Mesa $tableNumber',
            'orderId': orderId,
            'tableNumber': tableNumber,
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
    }
    debugPrint('Notificação de cancelamento enviada');
  } catch (e) {
    debugPrint('Erro ao enviar notificação de cancelamento: $e');
  }
}

  // ==========================================
  // OUVIR MENSAGENS EM FOREGROUND
  // ==========================================

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Mensagem recebida em foreground:');
    debugPrint('Título: ${message.notification?.title}');
    debugPrint('Corpo: ${message.notification?.body}');

    // Aqui você pode mostrar uma dialog ou snackbar customizado
    if (message.data.isNotEmpty) {
      debugPrint('Dados da mensagem: ${message.data}');
    }
  }

  // ==========================================
  // OUVIR QUANDO APP É ABERTO PELA NOTIFICAÇÃO
  // ==========================================

  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('App aberto pela notificação:');
    debugPrint('Tipo: ${message.data['type']}');

    // Aqui você pode navegar para a tela correta baseado no tipo de notificação
    if (message.data['type'] == 'new_order') {
      // Navegar para aba de pedidos
    } else if (message.data['type'] == 'order_status') {
      // Navegar para aba de pedidos do cliente
    }
  }

  // ==========================================
  // OBTER NOTIFICAÇÕES DO USUÁRIO
  // ==========================================

  Stream<List<Map<String, dynamic>>> getUserNotificationsStream(
      String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => {...doc.data(), 'id': doc.id})
          .toList();
    });
  }

  // ==========================================
  // MARCAR NOTIFICAÇÃO COMO LIDA
  // ==========================================

  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _firestore
          .collection('notifications')
          .doc(notificationId)
          .update({
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Erro ao marcar notificação como lida: $e');
    }
  }

  // ==========================================
  // DELETAR NOTIFICAÇÃO
  // ==========================================

  Future<void> deleteNotification(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).delete();
    } catch (e) {
      debugPrint('Erro ao deletar notificação: $e');
    }
  }

  // ==========================================
  // LIMPAR TODAS AS NOTIFICAÇÕES DO USUÁRIO
  // ==========================================

  Future<void> clearAllNotifications(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .get();

      for (var doc in snapshot.docs) {
        await doc.reference.delete();
      }

      debugPrint('Todas as notificações limpas para: $userId');
    } catch (e) {
      debugPrint('Erro ao limpar notificações: $e');
    }
  }

  void setupWaiterAlertListener(String establishmentId, String waiterId) {
  debugPrint('🔔 Configurando listener para alertas de garçom...');
  
  _firestore
      .collection('waiter_alerts')
      .where('establishmentId', isEqualTo: establishmentId)
      .where('status', isEqualTo: 'pending')
      .orderBy('createdAt', descending: true)
      .limit(10)
      .snapshots()
      .listen(
    (snapshot) {
      debugPrint('📊 Alertas recebidos: ${snapshot.docs.length}');
      
      for (var doc in snapshot.docs) {
        final alert = doc.data();
        debugPrint('🎯 NOVO ALERTA DETECTADO:');
        debugPrint('   ID: ${doc.id}');
        debugPrint('   Mesa: ${alert['tableId']}');
        debugPrint('   Razão: ${alert['reason']}');
        debugPrint('   Mensagem: ${alert['message']}');
        
        // Mostrar notificação local
        _showWaiterAlertNotification(alert, doc.id);
      }
    },
    onError: (error) {
      debugPrint('❌ Erro ao escutar alertas: $error');
    },
  );
}

// ✅ NOVO: Mostrar notificação local do alerta
void _showWaiterAlertNotification(Map<String, dynamic> alert, String alertId) {
  final reasonMap = {
    'callwaiter': '📞 Cliente chamou',
    'helpneeded': '🆘 Cliente precisa de ajuda',
    'payment': '💳 Cliente quer pagar',
    'complaint': '😤 Reclamação do cliente'
  };

  final reason = reasonMap[alert['reason'] ?? 'unknown'] ?? '❓ Alerta';
  final tableId = alert['tableId'] ?? 'N/A';
  final message = alert['message'] ?? reason;

  debugPrint('═══════════════════════════════════════════');
  debugPrint('🔴 ALERTA RECEBIDO!');
  debugPrint('═══════════════════════════════════════════');
  debugPrint('$reason - Mesa: $tableId');
  debugPrint('Mensagem: $message');
  debugPrint('ID Alerta: $alertId');
  debugPrint('═══════════════════════════════════════════');

  // ✅ Aqui você pode adicionar:
  // - Toque do celular
  // - Vibração
  // - Som customizado
  // - Notificação visual local
}

// ✅ NOVO: Fallback - Se FCM falhar, verifica via Firestore
void setupWaiterAlertPolling(String establishmentId, String waiterId) {
  debugPrint('⏱️ Iniciando polling de alertas (fallback)...');
  
  // Verificar a cada 5 segundos se há alertas novos
  Future.doWhile(() async {
    try {
      final snapshot = await _firestore
          .collection('waiter_alerts')
          .where('establishmentId', isEqualTo: establishmentId)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final alert = snapshot.docs.first.data();
        debugPrint('📱 Alerta detectado via polling (fallback)');
        _showWaiterAlertNotification(alert, snapshot.docs.first.id);
      }

      // Aguardar 5 segundos antes de verificar novamente
      await Future.delayed(const Duration(seconds: 5));
      return true; // Continua o loop
    } catch (e) {
      debugPrint('❌ Erro no polling: $e');
      return false; // Para o loop em caso de erro
    }
  });
}

// ✅ NOVO: Marcar alerta como respondido
Future<void> acknowledgeWaiterAlert(String alertId) async {
  try {
    await _firestore.collection('waiter_alerts').doc(alertId).update({
      'status': 'acknowledged',
      'acknowledgedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('✅ Alerta marcado como respondido: $alertId');
  } catch (e) {
    debugPrint('❌ Erro ao marcar alerta: $e');
  }
}
}
