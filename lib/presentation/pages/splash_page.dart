// splash_page.dart → versão corrigida (sempre vai para /welcome)

// ignore_for_file: unused_import, use_super_parameters

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({Key? key}) : super(key: key);

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..forward();

    // Sempre vai para /welcome depois de 3 segundos
    _navigateToWelcome();
  }

  void _navigateToWelcome() async {
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    // Força redirecionamento para /welcome, não importa o estado de autenticação
    Navigator.of(context).pushReplacementNamed('/welcome');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF00D4FF),
              Color(0xFF0047AB),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: Tween<double>(begin: 0.5, end: 1.0).animate(_controller),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.1),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.restaurant,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FadeTransition(
                opacity: Tween<double>(begin: 0.0, end: 1.0).animate(_controller),
                child: const Text(
                  'Garçon',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FadeTransition(
                opacity: Tween<double>(begin: 0.0, end: 1.0).animate(_controller),
                child: const Text(
                  'Gerenciamento Inteligente de Restaurantes',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}