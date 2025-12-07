// welcome_page.dart  ← VERSÃO CORRIGIDA (mantém tudo, só conserta o bug)

// ignore_for_file: unused_import, use_super_parameters

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:garcon/presentation/pages/login_page_improved.dart';
import 'package:garcon/services/auth_service.dart';
import '../config/theme_config.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({Key? key}) : super(key: key);

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkUser();
  }

  Future<void> _checkUser() async {
    // Pequena pausa pra garantir que o Firebase Auth terminou de restaurar a sessão
    await Future.delayed(const Duration(milliseconds: 500));

    final user = FirebaseAuth.instance.currentUser;

  if (user != null && mounted) {
      // Pega o role do Firestore
      final authService = AuthService();
      final data = await authService.getUserData(user.uid);
      final role = data?['role'] as String? ?? 'cliente';

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/home/$role',
        (route) => false,
      );
      return;
    }

    // Se chegou aqui = não está logado ou sessão expirou
    if (mounted) {
      setState(() => _isChecking = false);
    }
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

    // Tela normal de boas-vindas (igual você já tinha)
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: GarconTheme.primaryGradient),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.15),
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: const Icon(Icons.restaurant, size: 70, color: Colors.white),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Bem-vindo ao Garçon!',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Que bom te ter conosco!\nRevolucione seu restaurante',
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/login'),
                    icon: const Icon(Icons.login),
                    label: const Text('Já Tenho Conta'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0047AB),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/register'),
                    icon: const Icon(Icons.person_add),
                    label: const Text('Primeira Vez Aqui'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
}