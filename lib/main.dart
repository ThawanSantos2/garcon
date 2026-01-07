// ignore_for_file: use_super_parameters, unused_import

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'package:photo_manager/photo_manager.dart';
import './presentation/config/theme_config.dart';
import './presentation/pages/welcome_page.dart';
import './presentation/pages/register_page.dart';
import './presentation/pages/login_page_improved.dart';
import './presentation/pages/owner_home_page_improved.dart';
import 'presentation/pages/cliente-home-page.dart';
import './presentation/pages/waiter_home_page.dart';
import 'services/auth_service.dart';
import 'services/firebase_service.dart';
import './presentation/pages/splash_page.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:garcon/services/notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  runZonedGuarded(() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    NotificationService().initializeNotifications();
    await PhotoManager.requestPermissionExtend();

    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    runApp(const MyApp());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

class AuthProvider extends ChangeNotifier {
  bool _isAuthenticated = false;
  String? _userId;
  String? _userRole;

  bool get isAuthenticated => _isAuthenticated;
  String? get userId => _userId;
  String? get userRole => _userRole;

  Future<void> checkAuthStatus() async {
    final authService = AuthService();
    _isAuthenticated = authService.isUserLoggedIn();

    if (_isAuthenticated) {
      _userId = authService.getCurrentUserId();
      final userData = await authService.getUserData(_userId!);
      _userRole = userData?['role'];
    } else {
      _userId = null;
      _userRole = null;
    }

    notifyListeners();
  }

  Future<void> logout() async {
    await AuthService().signOut();
    _isAuthenticated = false;
    _userId = null;
    _userRole = null;
    notifyListeners();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Garçon',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      initialRoute: '/',  // Inicia na splash
      routes: {
        '/': (context) => const SplashPage(),
        '/welcome': (context) => const WelcomePage(),
        '/login': (context) => const LoginPageImproved(),
        '/register': (context) => const RegisterPage(),
        '/home/cliente': (context) => const ClientHomePage(),
        '/home/garcom': (context) => const WaiterHomePage(),
        '/home/estabelecimento': (context) => const OwnerHomePageImproved(),
        '/home': (context) => const WelcomePage(), // ou uma tela de erro
      },
      debugShowCheckedModeBanner: false,
    );
  }
}