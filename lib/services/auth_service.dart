import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool isUserLoggedIn() {
    return _auth.currentUser != null;
  }

  String? getCurrentUserId() {
    return _auth.currentUser?.uid;
  }

  // ==========================================
  // LOGIN COM E-MAIL E SENHA
  // ==========================================

  Future<UserCredential> loginWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Salvar sessão por 7 dias
      await _saveLoginSession(userCredential.user!.uid);

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw Exception('Erro de login: ${e.message}');
    }
  }

  // ==========================================
  // CADASTRO COMPLETO DE ESTABELECIMENTO (COM TELEFONE + SMS)
  // ==========================================

  Future<void> registerEstablishmentWithPhone({
    required String name,
    required String phoneNumber,
    required String restaurantName,
    required String address,
    required String email,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Usuário não autenticado');

      final userId = user.uid;

      // 1. Criar o estabelecimento
      final establishmentRef = _firestore.collection('establishments').doc();
      final establishmentId = establishmentRef.id;

      await establishmentRef.set({
        'name': restaurantName,
        'address': address,
        'ownerId': userId,
        'ownerName': name,
        'ownerEmail': email.isEmpty ? null : email,
        'ownerPhone': phoneNumber,
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': true,
      });

      // 2. Atualizar o documento do usuário com establishmentId
      await _firestore.collection('users').doc(userId).set({
        'uid': userId,
        'name': name,
        'email': email.isEmpty ? null : email,
        'phoneNumber': phoneNumber,
        'role': 'estabelecimento',
        'restaurantName': restaurantName,
        'address': address,
        'establishmentId': establishmentId,  // AQUI ESTÁ O QUE IMPORTA!
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Salvar sessão de 7 dias
      await _saveLoginSession(userId);
    } catch (e) {
      debugPrint('Erro ao criar estabelecimento: $e');
      rethrow;
    }
  }

  // ==========================================
  // CADASTRO COM E-MAIL E SENHA
  // ==========================================

  Future<UserCredential> registerWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw Exception('Erro ao registrar: ${e.message}');
    }
  }

  // ==========================================
  // AUTENTICAÇÃO COM SMS (FIREBASE NATIVO)
  // ==========================================

  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(String verificationId, int? resendToken) onCodeSent,
    required Function(FirebaseAuthException) onVerificationFailed,
    required Function(PhoneAuthCredential) onVerificationCompleted,
  }) async {
    try {
      String formattedPhone = _formatPhoneNumber(phoneNumber);

      await _auth.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        verificationCompleted: onVerificationCompleted,
        verificationFailed: onVerificationFailed,
        codeSent: onCodeSent,
        codeAutoRetrievalTimeout: (String verificationId) {},
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      throw Exception('Erro ao verificar número: $e');
    }
  }

  // ==========================================
  // FAZER LOGIN COM CÓDIGO SMS
  // ==========================================

  Future<UserCredential> signInWithPhoneAuthCredential(
    PhoneAuthCredential credential,
  ) async {
    try {
      final userCredential = await _auth.signInWithCredential(credential);
      
      // Salvar sessão por 7 dias
      await _saveLoginSession(userCredential.user!.uid);
      
      return userCredential;
    } catch (e) {
      throw Exception('Erro ao fazer login: $e');
    }
  }

  // ==========================================
  // ATUALIZAR PERFIL DO USUÁRIO
  // ==========================================

  Future<void> updateUserProfile({
    required String userId,
    required String name,
    required String email,
    required String role,
    required String? establishmentId,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'uid': userId,
        'name': name,
        'email': email,
        'phoneNumber': _auth.currentUser?.phoneNumber ?? '',
        'role': role,
        'establishmentId': establishmentId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isActive': true,
      });
    } catch (e) {
      throw Exception('Erro ao atualizar perfil: $e');
    }
  }

  // ==========================================
  // RECUPERAR SENHA
  // ==========================================

  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw Exception('Erro ao enviar reset: ${e.message}');
    }
  }

  // ==========================================
  // SALVAR SESSÃO (7 DIAS)
  // ==========================================

  Future<void> _saveLoginSession(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expirationTime = DateTime.now().add(const Duration(days: 7));

      await prefs.setString('last_user_id', userId);
      await prefs.setString('session_expiration', expirationTime.toIso8601String());
    } catch (e) {
      // Falha silenciosa - login continua funcionando
    }
  }

  // ==========================================
  // VERIFICAR SESSÃO VÁLIDA
  // ==========================================

  Future<bool> isSessionValid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expirationString = prefs.getString('session_expiration');

      if (expirationString == null) {
        return false;
      }

      final expiration = DateTime.parse(expirationString);
      return DateTime.now().isBefore(expiration);
    } catch (e) {
      return false;
    }
  }

  // ==========================================
  // LOGOUT
  // ==========================================

  Future<void> signOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_user_id');
      await prefs.remove('session_expiration');
      await _auth.signOut();
    } catch (e) {
      throw Exception('Erro ao fazer logout: $e');
    }
  }

  // ==========================================
  // STREAMS
  // ==========================================

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ==========================================
  // UTILITÁRIOS
  // ==========================================

  String _formatPhoneNumber(String phone) {
    String digits = phone.replaceAll(RegExp(r'\D'), '');

    if (!digits.startsWith('55')) {
      digits = '55$digits';
    }

    return '+$digits';
  }

  // Obter dados do usuário
  Future<Map<String, dynamic>?> getUserData(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      return doc.data();
    } catch (e) {
      throw Exception('Erro ao obter dados do usuário: $e');
    }
  }

  // Verificar se email já existe
  Future<bool> emailExists(String email) async {
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

  // Encontrar usuário por email (para recuperação de senha)
  Future<String?> findUserByEmail(String email) async {
    try {
      final result = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .get();

      if (result.docs.isNotEmpty) {
        return result.docs.first.id;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Atualizar dados do usuário
  Future<void> updateUserData(
    String userId,
    Map<String, dynamic> data,
  ) async {
    try {
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _firestore.collection('users').doc(userId).update(data);
    } catch (e) {
      throw Exception('Erro ao atualizar dados: $e');
    }
  }
}
