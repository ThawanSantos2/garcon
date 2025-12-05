// notification_service.dart
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/rendering.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  late FirebaseMessaging _messaging;
  final StreamController<Map<String, dynamic>> _notificationStream =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get notificationStream => _notificationStream.stream;

  Future<void> initialize() async {
    _messaging = FirebaseMessaging.instance;

    // Solicitar permissão (parâmetros atualizados para a versão atual do firebase_messaging)
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,        // carryForward foi removido → agora é carPlay
      criticalAlert: false,  // critical foi removido → agora é criticalAlert
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('Permissão de notificação concedida');
    } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
      debugPrint('Permissão provisória de notificação');
    } else {
      debugPrint('Permissão de notificação negada'); // corrigido: debugdebugPrint → debugPrint
    }

    // Obter token
    String? token = await _messaging.getToken();
    debugPrint('FCM Token: $token');

    // Listener para mensagens em foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Mensagem recebida em foreground: ${message.notification?.title}');
      _notificationStream.add({
        'title': message.notification?.title,
        'body': message.notification?.body,
        'data': message.data,
      });
    });

    // Listener para quando o app é aberto pela notificação (background/terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Notification causou abertura do app');
      _notificationStream.add({
        'title': message.notification?.title,
        'body': message.notification?.body,
        'data': message.data,
        'fromNotification': true,
      });
    });
  }

  Future<String?> getToken() async {
    return await _messaging.getToken();
  }

  void dispose() {
    _notificationStream.close();
  }
}