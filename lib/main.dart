// ignore_for_file: use_super_parameters

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import './presentation/config/theme_config.dart';
import 'presentation/pages/splash_page.dart';
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
        home: const SplashPage(),
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
    // Check if user is logged in
    final authService = AuthService();
    _isAuthenticated = authService.isUserLoggedIn();
    notifyListeners();
  }

  Future<void> logout() async {
    _isAuthenticated = false;
    _userId = null;
    _userRole = null;
    notifyListeners();
  }
}
