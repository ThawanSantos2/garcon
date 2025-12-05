import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  // AUTENTICAÇÃO COM SMS (FIREBASE NATIVO)
  // ==========================================

  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(String verificationId, int? resendToken) onCodeSent,
    required Function(FirebaseAuthException) onVerificationFailed,
    required Function(PhoneAuthCredential) onVerificationCompleted,
  }) async {
    try {
      // Formata o número para E.164 (+55 DDD número)
      String formattedPhone = _formatPhoneNumber(phoneNumber);

      await _auth.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        verificationCompleted: onVerificationCompleted,
        verificationFailed: onVerificationFailed,
        codeSent: onCodeSent,
        codeAutoRetrievalTimeout: (String verificationId) {
          // Timeout automático
        },
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
    required String role, // cliente, garcom, estabelecimento
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
  // LOGOUT
  // ==========================================

  Future<void> signOut() async {
    try {
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
    // Remove caracteres especiais
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    
    // Se não começar com 55, adiciona
    if (!digits.startsWith('55')) {
      digits = '55$digits';
    }
    
    // Adiciona o +
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
}
