// ignore_for_file: use_super_parameters, unused_import

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/theme_config.dart';
import '../../services/auth_service.dart';
import '../../core/utils/validators.dart';
import '../../core/utils/formatters.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({Key? key}) : super(key: key);

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  String _selectedRole = 'cliente'; // cliente, garcom, estabelecimento
  int _currentStep = 0; // 0: role selection, 1: form, 2: phone verify, 3: success
  
  final _authService = AuthService();
  final _firestore = FirebaseFirestore.instance;
  
  // Controllers para Cliente
  final _clientNameController = TextEditingController();
  final _clientEmailController = TextEditingController();
  final _clientPhoneController = TextEditingController();
  final _clientPasswordController = TextEditingController();
  final _clientConfirmPasswordController = TextEditingController();

  // Controllers para Garçom
  final _waiterNameController = TextEditingController();
  final _waiterEmailController = TextEditingController();
  final _waiterPhoneController = TextEditingController();
  final _waiterPasswordController = TextEditingController();
  final _waiterConfirmPasswordController = TextEditingController();

  // Controllers para Proprietário
  final _ownerNameController = TextEditingController();
  final _ownerRestaurantNameController = TextEditingController();
  final _ownerAddressController = TextEditingController();
  final _ownerPhoneController = TextEditingController();
  final _ownerEmailController = TextEditingController();
  final _ownerPasswordController = TextEditingController();
  final _ownerConfirmPasswordController = TextEditingController();

  // Phone verification
  String? _verificationId;
  final _phoneCodeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _clientNameController.dispose();
    _clientEmailController.dispose();
    _clientPhoneController.dispose();
    _clientPasswordController.dispose();
    _clientConfirmPasswordController.dispose();
    
    _waiterNameController.dispose();
    _waiterEmailController.dispose();
    _waiterPhoneController.dispose();
    _waiterPasswordController.dispose();
    _waiterConfirmPasswordController.dispose();
    
    _ownerNameController.dispose();
    _ownerRestaurantNameController.dispose();
    _ownerAddressController.dispose();
    _ownerPhoneController.dispose();
    _ownerEmailController.dispose();
    _ownerPasswordController.dispose();
    _ownerConfirmPasswordController.dispose();
    
    _phoneCodeController.dispose();
    super.dispose();
  }

  Future<void> _proceedToPhoneVerification() async {
    setState(() => _isLoading = true);
    
    try {
      String phoneNumber = '';
      String email = '';

      if (_selectedRole == 'cliente') {
        phoneNumber = _clientPhoneController.text;
        email = _clientEmailController.text;
      } else if (_selectedRole == 'garcom') {
        phoneNumber = _waiterPhoneController.text;
        email = _waiterEmailController.text;
      } else {
        phoneNumber = _ownerPhoneController.text;
        email = _ownerEmailController.text;
      }

      // Validar email único
      final emailExists = await _checkEmailExists(email);
      if (emailExists) {
        setState(() {
          _errorMessage = 'Este e-mail já está cadastrado';
          _isLoading = false;
        });
        return;
      }

      // Iniciar verificação de telefone
      final formattedPhone = _formatPhoneNumber(phoneNumber);

      await _authService.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        onCodeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _currentStep = 2; // Ir para step de verificação
            _isLoading = false;
          });
        },
        onVerificationFailed: (FirebaseAuthException e) {
          setState(() {
            _errorMessage = 'Erro na verificação: ${e.message}';
            _isLoading = false;
          });
        },
        onVerificationCompleted: (PhoneAuthCredential credential) {
          // Auto-complete se disponível
        },
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyPhoneCode() async {
    if (_phoneCodeController.text.isEmpty) {
      setState(() => _errorMessage = 'Digite o código');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _phoneCodeController.text,
      );

      final userCredential = await _authService.signInWithPhoneAuthCredential(credential);

      if (userCredential.user != null) {
        // Registrar dados adicionais no Firestore
        await _saveUserData(userCredential.user!.uid);
        
        setState(() {
          _currentStep = 3; // Success
          _isLoading = false;
        });

        // Ir para login após 2 segundos
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = 'Código inválido: ${e.message}';
        _isLoading = false;
      });
    }
  }

  Future<bool> _checkEmailExists(String email) async {
    try {
      final result = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .get();
      return result.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> _saveUserData(String userId) async {
    String name = '';
    String email = '';
    String phone = '';

    if (_selectedRole == 'cliente') {
      name = _clientNameController.text;
      email = _clientEmailController.text;
      phone = _clientPhoneController.text;
    } else if (_selectedRole == 'garcom') {
      name = _waiterNameController.text;
      email = _waiterEmailController.text;
      phone = _waiterPhoneController.text;
    } else {
      name = _ownerNameController.text;
      email = _ownerEmailController.text;
      phone = _ownerPhoneController.text;
    }

    await _firestore.collection('users').doc(userId).set({
      'uid': userId,
      'name': name,
      'email': email,
      'phoneNumber': phone,
      'role': _selectedRole,
      'restaurantName': _selectedRole == 'estabelecimento' ? _ownerRestaurantNameController.text : null,
      'address': _selectedRole == 'estabelecimento' ? _ownerAddressController.text : null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isActive': true,
      'establishmentId': null,
    });
  }

  String _formatPhoneNumber(String phone) {
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    if (!digits.startsWith('55')) {
      digits = '55$digits';
    }
    return '+$digits';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _currentStep == 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: GarconTheme.primaryGradient,
        ),
        child: SafeArea(
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_currentStep) {
      case 0:
        return _buildRoleSelection();
      case 1:
        return _buildRegistrationForm();
      case 2:
        return _buildPhoneVerification();
      case 3:
        return _buildSuccessScreen();
      default:
        return _buildRoleSelection();
    }
  }

  Widget _buildRoleSelection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          const Text(
            'Como você quer se cadastrar?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),

          // Cliente
          _buildRoleCard(
            title: 'Cliente',
            subtitle: 'Peça seus pratos sem sair da mesa',
            icon: Icons.person,
            value: 'cliente',
          ),
          const SizedBox(height: 16),

          // Garçom
          _buildRoleCard(
            title: 'Garçom',
            subtitle: 'Gerencie os pedidos dos clientes',
            icon: Icons.restaurant_menu,
            value: 'garcom',
          ),
          const SizedBox(height: 16),

          // Proprietário
          _buildRoleCard(
            title: 'Proprietário',
            subtitle: 'Controle seu restaurante',
            icon: Icons.store,
            value: 'estabelecimento',
          ),
          const SizedBox(height: 40),

          // Botão próximo
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                setState(() => _currentStep = 1);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0047AB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Próximo',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
  }) {
    final isSelected = _selectedRole == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white30,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.15),
              ),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                color: isSelected ? Colors.white.withValues(alpha: 0.3) : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegistrationForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE74C3C).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE74C3C)),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          const SizedBox(height: 24),

          if (_selectedRole == 'cliente') ...[
            _buildTextField(
              controller: _clientNameController,
              label: 'Nome Completo',
              icon: Icons.person,
            ),
            _buildTextField(
              controller: _clientEmailController,
              label: 'E-mail',
              icon: Icons.email,
              keyboardType: TextInputType.emailAddress,
            ),
            _buildTextField(
              controller: _clientPhoneController,
              label: 'Telefone',
              icon: Icons.phone,
              hintText: '(11) 99999-9999 ou +55 11 99999-9999',
            ),
            _buildTextField(
              controller: _clientPasswordController,
              label: 'Senha',
              icon: Icons.lock,
              obscureText: true,
            ),
            _buildTextField(
              controller: _clientConfirmPasswordController,
              label: 'Confirmar Senha',
              icon: Icons.lock,
              obscureText: true,
            ),
          ] else if (_selectedRole == 'garcom') ...[
            _buildTextField(
              controller: _waiterNameController,
              label: 'Nome Completo',
              icon: Icons.person,
            ),
            _buildTextField(
              controller: _waiterEmailController,
              label: 'E-mail',
              icon: Icons.email,
              keyboardType: TextInputType.emailAddress,
            ),
            _buildTextField(
              controller: _waiterPhoneController,
              label: 'Telefone',
              icon: Icons.phone,
              hintText: '(11) 99999-9999 ou +55 11 99999-9999',
            ),
            _buildTextField(
              controller: _waiterPasswordController,
              label: 'Senha',
              icon: Icons.lock,
              obscureText: true,
            ),
            _buildTextField(
              controller: _waiterConfirmPasswordController,
              label: 'Confirmar Senha',
              icon: Icons.lock,
              obscureText: true,
            ),
          ] else ...[
            _buildTextField(
              controller: _ownerNameController,
              label: 'Seu Nome',
              icon: Icons.person,
            ),
            _buildTextField(
              controller: _ownerRestaurantNameController,
              label: 'Nome do Restaurante',
              icon: Icons.store,
            ),
            _buildTextField(
              controller: _ownerAddressController,
              label: 'Endereço',
              icon: Icons.location_on,
            ),
            _buildTextField(
              controller: _ownerPhoneController,
              label: 'Telefone',
              icon: Icons.phone,
              hintText: '(11) 99999-9999 ou +55 11 99999-9999',
            ),
            _buildTextField(
              controller: _ownerEmailController,
              label: 'E-mail',
              icon: Icons.email,
              keyboardType: TextInputType.emailAddress,
            ),
            _buildTextField(
              controller: _ownerPasswordController,
              label: 'Senha',
              icon: Icons.lock,
              obscureText: true,
            ),
            _buildTextField(
              controller: _ownerConfirmPasswordController,
              label: 'Confirmar Senha',
              icon: Icons.lock,
              obscureText: true,
            ),
          ],

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _proceedToPhoneVerification,
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
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Continuar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    String? hintText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          hintStyle: const TextStyle(color: Colors.white60),
          labelStyle: const TextStyle(color: Colors.white70),
          prefixIcon: Icon(icon, color: Colors.white70),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white30),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white30),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneVerification() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
            ),
            child: const Icon(
              Icons.sms,
              size: 50,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Confirme seu Número',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Enviamos um código para seu celular',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white70,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),

          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE74C3C).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          const SizedBox(height: 24),

          TextField(
            controller: _phoneCodeController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
            ),
            decoration: InputDecoration(
              hintText: '000000',
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white30),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white30),
              ),
            ),
          ),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _verifyPhoneCode,
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
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Verificar Código',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessScreen() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withValues(alpha: 0.2),
              ),
              child: const Icon(
                Icons.check_circle_outline,
                size: 60,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Cadastro Realizado!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Você será redirecionado para o login em alguns segundos',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 50,
              height: 50,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
