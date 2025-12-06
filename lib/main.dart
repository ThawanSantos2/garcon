// ignore_for_file: use_super_parameters, unused_import

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import './presentation/config/theme_config.dart';
import './presentation/pages/welcome_page.dart';
import './presentation/pages/register_page.dart';
import './presentation/pages/login_page_improved.dart';
import './presentation/pages/owner_home_page_improved.dart';
import './presentation/pages/client_home_page.dart';
import './presentation/pages/waiter_home_page.dart';
import 'services/auth_service.dart';
import 'services/firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(const MyApp());
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
      home: const WelcomePage(),
      routes: {
        '/welcome': (context) => const WelcomePage(),
        '/login': (context) => const LoginPageImproved(),
        '/register': (context) => const RegisterPage(),
        '/home': (context) => _buildHomeScreen(context),
      },
    );
  }

  Widget _buildHomeScreen(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _getUserData(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final userData = snapshot.data;
        final role = userData?['role'] as String?;

        switch (role) {
          case 'estabelecimento':
            return const OwnerHomePageImproved();
          case 'garcom':
            return const WaiterHomePage(); // Você vai criar isso
          case 'cliente':
            return const ClientHomePage(); // Você vai criar isso
          default:
            return const LoginPageImproved();
        }
      },
    );
  }

  Future<Map<String, dynamic>?> _getUserData() async {
    final authService = AuthService();
    final userId = authService.getCurrentUserId();
    
    if (userId == null) return null;
    
    try {
      return await authService.getUserData(userId);
    } catch (e) {
      return null;
    }
  }
}

class AuthProvider extends ChangeNotifier {
  bool _isAuthenticated = false;
  String? _userId;
  String? _userRole; // cliente, garcom, estabelecimento

  bool get isAuthenticated => _isAuthenticated;
  String? get userId => _userId;
  String? get userRole => _userRole;

  Future<void> checkAuthStatus() async {
    final authService = AuthService();
    _isAuthenticated = authService.isUserLoggedIn();

    if (_isAuthenticated) {
      _userId = authService.getCurrentUserId();
      final userData = await authService.getUserData(_userId!);
      _userRole = userData?['role'];  // Carrega o role do Firestore
    }

    notifyListeners();
  }

  Future<void> logout() async {
    _isAuthenticated = false;
    _userId = null;
    _userRole = null;
    notifyListeners();
  }
}