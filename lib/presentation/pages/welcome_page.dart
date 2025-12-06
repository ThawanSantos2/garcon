// ignore_for_file: unused_field, use_super_parameters, unused_import

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:garcon/presentation/pages/login_page_improved.dart';
import '../../services/auth_service.dart';
import '../config/theme_config.dart';


class WelcomePage extends StatefulWidget {
  const WelcomePage({Key? key}) : super(key: key);

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final _authService = AuthService();
  bool _isChecking = true;
  bool _isFirstTime = true;

  @override
  void initState() {
    super.initState();
    _checkIfFirstTime();
  }

  Future<void> _checkIfFirstTime() async {
    try {
      // Verificar se já tem usuário logado
      final currentUser = FirebaseAuth.instance.currentUser;
      
      if (currentUser != null) {
        // Usuário já tem sessão ativa, vai para home
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        // Verificar no SharedPreferences se foi primeira vez
        final prefs = await _getSharedPrefs();
        final hasVisited = prefs?.getBool('has_visited') ?? false;
        
        setState(() {
          _isFirstTime = !hasVisited;
          _isChecking = false;
        });
      }
    } catch (e) {
      setState(() => _isChecking = false);
    }
  }

  Future<dynamic> _getSharedPrefs() async {
    // Retorna shared_preferences instance
    // Implementado no app principal
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(gradient: GarconTheme.primaryGradient),
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );
    }

    if (_isFirstTime) {
      return _buildFirstTimeScreen();
    } else {
      return _buildLoginScreen();
    }
  }

  Widget _buildFirstTimeScreen() {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: GarconTheme.primaryGradient),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo grande
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.15),
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: const Icon(
                    Icons.restaurant,
                    size: 70,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 32),
                
                const Text(
                  'Bem-vindo ao Garçon!',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                
                const Text(
                  'Que bom te ter conosco!\nRevolucione seu restaurante',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Botão Login
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(context, '/login');
                    },
                    icon: const Icon(Icons.login),
                    label: const Text('Já Tenho Conta'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0047AB),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Botão Registrar
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(context, '/register');
                    },
                    icon: const Icon(Icons.person_add),
                    label: const Text('Primeira Vez Aqui'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginScreen() {
    return const LoginPageImproved();
  }
}
