// ignore_for_file: use_super_parameters

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import './presentation/config/theme_config.dart';
import 'presentation/pages/splash_page.dart';
import 'presentation/pages/login_page.dart'; // Importe as páginas
import 'presentation/pages/client_home_page.dart';
import 'presentation/pages/owner_home_page.dart';
import 'presentation/pages/waiter_home_page.dart';
import 'services/auth_service.dart';
import 'services/firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<FirebaseService>(create: (_) => FirebaseService()),
        Provider<AuthService>(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(
        title: 'Garçon',
        debugShowCheckedModeBanner: false,
        theme: GarconTheme.lightTheme,
        darkTheme: GarconTheme.darkTheme,
        themeMode: ThemeMode.system,
        initialRoute: '/',  // Inicia na splash
        routes: {
          '/': (context) => const SplashPage(),
          '/login': (context) => const LoginPage(),
          '/home/client': (context) => const ClientHomePage(),
          '/home/garcom': (context) => const WaiterHomePage(),  // 'garcom' no código é 'garcom'
          '/home/estabelecimento': (context) => const OwnerHomePage(),
        },
        onUnknownRoute: (settings) => MaterialPageRoute(
          builder: (context) => const Scaffold(
            body: Center(child: Text('Página não encontrada')),
          ),
        ),
      ),
    );
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