// ignore_for_file: unused_field, use_super_parameters, prefer_final_fields

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/auth_service.dart';
import '../config/theme_config.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  
  bool _obscurePassword = true;
  String _selectedRole = 'cliente'; // cliente, garcom, estabelecimento
  bool _isLoading = false;
  String? _verificationId;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_phoneController.text.isEmpty) {
      _showErrorDialog('Por favor, digite um número de telefone');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService.verifyPhoneNumber(
        phoneNumber: _phoneController.text,
        onCodeSent: (String verificationId, int? resendToken) {
          setState(() => _verificationId = verificationId);
          _showVerificationDialog();
        },
        onVerificationFailed: (FirebaseAuthException e) {
          _showErrorDialog('Erro: ${e.message}');
        },
        onVerificationCompleted: (PhoneAuthCredential credential) {
          _signInWithCredential(credential);
        },
      );
    } catch (e) {
      _showErrorDialog('Erro ao verificar número: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      setState(() => _isLoading = true);
      
      final userCredential = 
          await _authService.signInWithPhoneAuthCredential(credential);
      
      // Atualizar perfil do usuário
      if (userCredential.user != null) {
        await _authService.updateUserProfile(
          userId: userCredential.user!.uid,
          name: 'Usuário ${userCredential.user!.phoneNumber}',
          email: '${userCredential.user!.uid}@garcon.app',
          role: _selectedRole,
          establishmentId: null,
        );

        // Navegar para home baseado no role
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/home/$_selectedRole');
        }
      }
    } on FirebaseAuthException catch (e) {
      _showErrorDialog('Erro de autenticação: ${e.message}');
    } catch (e) {
      _showErrorDialog('Erro: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erro'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showVerificationDialog() {
    final codeController = TextEditingController();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Verificação de Código'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Código enviado para ${_phoneController.text}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '000000',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                labelText: 'Código SMS',
              ),
              maxLength: 6,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (codeController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Digite o código')),
                );
                return;
              }

              try {
                final credential = PhoneAuthProvider.credential(
                  verificationId: _verificationId!,
                  smsCode: codeController.text,
                );
                
                if (mounted) {
                  Navigator.pop(context);
                }
                
                await _signInWithCredential(credential);
              } on FirebaseAuthException catch (e) {
                _showErrorDialog('Código inválido: ${e.message}');
              }
            },
            child: const Text('Verificar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Container(
          height: MediaQuery.of(context).size.height,
          decoration: BoxDecoration(
            gradient: GarconTheme.primaryGradient,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha:0.1),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.restaurant,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Bem-vindo ao Garçon',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Selecione seu tipo de conta',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 32),

                // Role Selection
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildRoleOption(
                        'Cliente',
                        'cliente',
                        Icons.person,
                        'Faça pedidos de forma fácil',
                      ),
                      const SizedBox(height: 12),
                      _buildRoleOption(
                        'Garçom',
                        'garcom',
                        Icons.kitchen,
                        'Gerencie pedidos dos clientes',
                      ),
                      const SizedBox(height: 12),
                      _buildRoleOption(
                        'Proprietário',
                        'estabelecimento',
                        Icons.store,
                        'Controle seu restaurante',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Phone Input
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  enabled: !_isLoading,
                  decoration: InputDecoration(
                    hintText: '(11) 99999-9999',
                    hintStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha:0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white30),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white30),
                    ),
                    prefixIcon: const Icon(Icons.phone, color: Colors.white70),
                    labelText: 'Telefone',
                    labelStyle: const TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 32),

                // Login Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0047AB),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Enviar Código SMS',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                // Info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'ℹ️ Você receberá um código SMS para confirmar seu número',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
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

  Widget _buildRoleOption(
    String title,
    String value,
    IconData icon,
    String subtitle,
  ) {
    final isSelected = _selectedRole == value;
    return GestureDetector(
      onTap: _isLoading ? null : () => setState(() => _selectedRole = value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withValues(alpha:0.2) : Colors.transparent,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white30,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
