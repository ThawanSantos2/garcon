// ignore_for_file: unused_import, use_super_parameters, unused_field, unused_local_variable, unused_element, prefer_final_fields, file_names, unnecessary_null_comparison, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:garcon/presentation/config/theme_config.dart';
import 'package:garcon/services/firebase_service.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/payment_service.dart';
import '../../data/models/order_model.dart';
import 'dart:io'; // Para detectar plataforma (iOS/Android)
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../services/notification_service.dart';

class ClientHomePage extends StatefulWidget {
  const ClientHomePage({Key? key}) : super(key: key);

  @override
  State<ClientHomePage> createState() => _ClientHomePageState();
}

class _ClientHomePageState extends State<ClientHomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseService _firebaseService = FirebaseService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PaymentService _paymentService = PaymentService();
  final NotificationService _notificationService = NotificationService();
  final _firestore = FirebaseFirestore.instance;

  // Estado da página
  int _currentTabIndex = 0;
  String? _currentSessionId;
  String? _currentEstablishmentId;
  String? _currentTableName;  // <--- NOVA VARIÁVEL
  String? _currentTableId;
  Map<String, dynamic>? _currentEstablishment;
  Map<String, List<String>> _userSubscriptions = {}; // {establishmentId: [listOfSubscriptions]}
  bool _showQRScanner = true;
  final bool _isLoadingPayment = false;
  bool _isLoading = false;


    // Status labels e cores
  final Map<String, String> _statusLabels = {
    'pending': 'Pendente',
    'accepting': 'Aceitando',
    'preparing': 'Em Preparação',
    'ready': 'Pronto',
    'on_the_way': 'A Caminho',
    'delivered': 'Entregue',
    'completed': 'Completado',
    'cancelled': 'Cancelado',
    'rejected': 'Recusado',
  };

  final Map<String, Color> _statusColors = {
    'pending': Colors.orange,
    'accepting': Colors.blue,
    'preparing': Colors.blue,
    'ready': Colors.green,
    'on_the_way': Colors.purple,
    'delivered': Colors.teal,
    'completed': Colors.green,
    'cancelled': Colors.red,
    'rejected': Colors.red.shade900,
  };

  final Map<String, IconData> _statusIcons = {
    'pending': Icons.hourglass_bottom,
    'accepting': Icons.check_circle,
    'preparing': Icons.restaurant,
    'ready': Icons.check_circle,
    'on_the_way': Icons.directions_run,
    'delivered': Icons.celebration,
    'completed': Icons.celebration,
    'cancelled': Icons.cancel,
    'rejected': Icons.block,
  };

String _getTableDisplayName() {
  // Primeiro tenta pegar o nome que veio no QR Code (tableName)
  if (_currentTableId != null) {
    // Vamos tentar buscar os dados reais da mesa no Firestore (opcional, mas mais preciso)
    // Mas se quiser algo rápido, use o que já tem:

    // Opção 1: Se você passou o nome da mesa no QR Code (recomendado!)
    // No seu QR atual: est:abc|table:Mesa VIP|id:table_123|capacity:6
    // Então você pode armazenar o nome ao escanear

    // Mas como você não está salvando ainda, vamos fazer um fallback esperto:
    final possibleName = _currentEstablishment?['tables']?[ _currentTableId ]?['name'];
    if (possibleName != null && possibleName.toString().trim().isNotEmpty) {
      return possibleName.toString();
    }
  }

  // Fallback bonito: tenta extrair número do ID
  final match = RegExp(r'(?:table_)?(\d+)').firstMatch(_currentTableId ?? '');
  if (match != null) {
    return 'Mesa ${match.group(1)}';
  }

  // Último caso: mostra só os últimos caracteres bonitinhos
  final shortId = _currentTableId?.length == 20 
      ? _currentTableId!.substring(15).toUpperCase() 
      : _currentTableId ?? 'N/A';

  return 'Mesa #$shortId';
}

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadUserSubscriptions();
    _checkForActiveSession();  // ← ESSA É A MÁGICA!
    _initializePaymentService();
    _setupNotifications();
  }

  // ==========================================
  // VERIFICAR SESSÃO ATIVA AO ABRIR O APP
  // ==========================================
  Future<void> _checkForActiveSession() async {
    if (!mounted) return;

    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final activeSession = await _firebaseService.getActiveSession(user.uid);

      if (activeSession != null) {
        // Tem sessão ativa → restaura tudo automaticamente!
        final estId = activeSession['establishmentId'] as String;
        final tableId = activeSession['tableId'] as String;

        final establishment = await _firebaseService.getEstablishmentData(estId);

        if (!mounted) return;

        setState(() {
          _currentSessionId = activeSession['id'] ?? activeSession['sessionDocId'];
          _currentEstablishmentId = estId;
          _currentTableId = tableId;
          _currentEstablishment = establishment;
          _showQRScanner = false; // mostra tela principal direto
        });

        debugPrint('Sessão ativa restaurada! Mesa: $tableId');
        return;
      }
    } catch (e) {
      debugPrint('Erro ao restaurar sessão: $e');
    }

    // Se chegou aqui → não tem sessão ativa → mostra QR code
    if (mounted) {
      setState(() => _showQRScanner = true);
    }
  }

  Future<void> _setupNotifications() async {
  await _notificationService.initializeNotifications();
  final user = _auth.currentUser;
  if (user != null) {
    final token = await _notificationService.getUserFCMToken();
    if (token != null) {
      await _notificationService.saveFCMTokenToFirestore(user.uid, token);
    }
  }
}

  Future<void> _initializePaymentService() async {
  try {
    final paymentManager = _PaymentManager();
    await paymentManager.initializePayments();
  } catch (e) {
    debugPrint('Erro ao inicializar payments: $e');
  }
}

  void _onTabChanged() {
    setState(() {
      _currentTabIndex = _tabController.index;
    });
  }

  // ==========================================
  // CARREGAR ASSINATURAS DO CLIENTE
  // ==========================================
  Future<void> _loadUserSubscriptions() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      final userDoc = await _firebaseService.getUserData(userId);
      if (userDoc != null && userDoc['subscriptions'] != null) {
        setState(() {
          _userSubscriptions =
              Map<String, List<String>>.from(userDoc['subscriptions']);
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar assinaturas: $e');
    }
  }

  // ==========================================
  // VERIFICAR ASSINATURA NO ESTABELECIMENTO
  // ==========================================
  // ✅ CORRIGIDO: Bypass de pagamento para teste
Future<bool> _hasActiveSubscription(String establishmentId) async {
  try {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return false;

    // ✅ TESTE/DESENVOLVIMENTO: Permitir acesso a TODOS
    // Comentar a linha abaixo após testes para ativar pagamento real
    return true; // ← BYPASS: Todos têm acesso
    
    // ===== CÓDIGO ORIGINAL (descomente quando quiser ativar pagamento) =====
    /*
    if (_userSubscriptions.containsKey(establishmentId)) {
      final subscriptions = _userSubscriptions[establishmentId]!;
      return subscriptions.isNotEmpty;
    }

    return false;
    */
    // ===================================================================
    
  } catch (e) {
    debugPrint('Erro ao verificar assinatura: $e');
    return true; // ← Se erro, permitir para não bloquear usuário
  }
}


  // ==========================================
  // PROCESSAR SCAN DO QR CODE
  // ==========================================
  void _processMobileScanned(BarcodeCapture barcode) {
    try {
      if (barcode.barcodes.isEmpty) return;

      final value = barcode.barcodes.first.rawValue;
      if (value == null || !value.contains('est:')) return;

      // Parse: est:establishmentId|table:tableName|id:tableId|capacity:capacity
      final parts = value.split('|');
      String? establishmentId, tableName, tableId;
      int capacity = 0;

      for (var part in parts) {
        if (part.startsWith('est:')) {
          establishmentId = part.replaceFirst('est:', '');
        } else if (part.startsWith('table:')) {
          tableName = part.replaceFirst('table:', '');
        } else if (part.startsWith('id:')) {
          tableId = part.replaceFirst('id:', '');
        } else if (part.startsWith('capacity:')) {
          capacity = int.tryParse(part.replaceFirst('capacity:', '')) ?? 0;
        }
      }

      if (establishmentId != null && tableId != null) {
        _handleQRScanned(establishmentId, tableId, tableName ?? 'Mesa');
      }
    } catch (e) {
      _showSnackBar('Erro ao ler QR Code: $e', isError: true);
    }
  }

  // ==========================================
  // LIDAR COM SCAN DO QR CODE
  // ==========================================
// ✅ CORRIGIDO: Sem tela de pagamento
Future<void> _handleQRScanned(
  String establishmentId,
  String tableId,
  String tableName,
) async {
  try {
    setState(() => _showQRScanner = false);
    final establishment =
        await _firebaseService.getEstablishmentData(establishmentId);

    if (establishment == null) {
      throw Exception('Estabelecimento não encontrado');
    }

    setState(() {
      _currentEstablishmentId = establishmentId;
      _currentTableId = tableId;
      _currentEstablishment = establishment;
      _currentTableName = tableName;
    });

    // ✅ SEM VERIFICAÇÃO DE PAGAMENTO
    // Todos os clientes têm acesso direto
    
    debugPrint('DEBUG: Cliente acessando restaurante: $establishmentId');
    
    await _startClientSession(establishmentId, tableId);
    _showClientMainScreen();

  } catch (e) {
    debugPrint('Erro ao processar QR: $e');
    _showSnackBar('Erro: ${e.toString()}', isError: true);
    setState(() => _showQRScanner = true);
  }
}

// ==========================================
// DIALOG - QR NÃO ESCANEADO
// ==========================================

void _showQRNotScannedDialog() {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ✅ ÍCONE DE ALERTA
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.amber,
                size: 48,
              ),
            ),
            const SizedBox(height: 20),

            // ✅ TÍTULO
            const Text(
              'QR Code Não Escaneado',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // ✅ MENSAGEM
            Text(
              'Para prosseguir, você precisa escanear o QR Code de uma mesa do estabelecimento.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // ✅ BOTÃO VOLTAR AO SCANNER
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  // Reabrir o scanner
                  if (mounted) {
                    setState(() {
                      _showQRScanner = true;
                    });
                  }
                },
                icon: const Icon(Icons.qr_code_2),
                label: const Text(
                  'Tentar Novamente',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ✅ BOTÃO DESLOGAR
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _logoutFromQRScreen();
                },
                icon: const Icon(Icons.logout),
                label: const Text(
                  'Deslogar',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red, width: 1.5),
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
  );
}

// ==========================================
// LOGOUT DO SCREEN QR
// ==========================================

Future<void> _logoutFromQRScreen() async {
  try {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
    }
  } catch (e) {
    _showSnackBar('Erro ao deslogar: $e', isError: true);
  }
}


  // ==========================================
  // INICIAR SESSÃO DO CLIENTE
  // ==========================================
Future<void> _startClientSession(
    String establishmentId, String tableId) async {
  try {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw Exception('Usuário não autenticado');
    }

    // PASSO 1: Verificar se mesa está ocupada
    final tableDoc = await _firestore
        .collection('establishments')
        .doc(establishmentId)
        .collection('tables')
        .doc(tableId)
        .get();

    if (tableDoc.exists) {
      final tableData = tableDoc.data() as Map<String, dynamic>;
      if (tableData['isOccupied'] == true && 
          tableData['currentCustomerId'] != userId) {
        throw Exception('Mesa já está ocupada por outro cliente');
      }
    }

    // PASSO 2: Criar nova sessão
    final sessionId = await _firebaseService.createCustomerSession(
      establishmentId: establishmentId,
      tableId: tableId,
      customerId: userId,
    );

    setState(() {
      _currentSessionId = sessionId;
    });

    debugPrint('Sessão criada: $sessionId');

  } catch (e) {
    debugPrint('Erro ao criar sessão: $e');
    _showSnackBar('Erro ao criar sessão: $e', isError: true);
    
    // Voltar para QR Scanner
    setState(() => _showQRScanner = true);
  }
}

Future<bool> _isSessionValid() async {
  if (_currentSessionId == null || _currentEstablishmentId == null) {
    return false;
  }

  try {
    final sessionDoc = await _firestore
        .collection('establishments')
        .doc(_currentEstablishmentId!)
        .collection('sessions')
        .doc(_currentSessionId!)
        .get();

    if (!sessionDoc.exists) {
      debugPrint('Sessão não existe mais');
      setState(() {
        _currentSessionId = null;
        _showQRScanner = true;
      });
      return false;
    }

    final sessionData = sessionDoc.data() as Map<String, dynamic>;
    if (sessionData['isActive'] != true) {
      debugPrint('Sessão não está ativa');
      setState(() {
        _currentSessionId = null;
        _showQRScanner = true;
      });
      return false;
    }

    return true;
  } catch (e) {
    debugPrint('Erro ao validar sessão: $e');
    return false;
  }
}

  // ==========================================
  // TELA DE PAGAMENTO
  // ==========================================
  void _showEstablishmentPaymentScreen(Map<String, dynamic> establishment) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => _PaymentBottomSheet(
        establishment: establishment,
        onPaymentSuccess: () {
          Navigator.pop(context);
          _addSubscriptionAndProceed(establishment['id']);
        },
        onCancel: () {
          Navigator.pop(context);
          setState(() => _showQRScanner = true);
        },
      ),
    );
  }

// ==========================================
// ADICIONAR ASSINATURA E PROSSEGUIR
// ==========================================
Future<void> _addSubscriptionAndProceed(String establishmentId) async {
  try {
if (establishmentId == null) {
      throw Exception('Establishment ID não definido');
    }
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    if (_currentTableId == null) {
      throw Exception('Table ID não definido');
    }

    // Atualizar assinaturas do cliente
    _userSubscriptions.putIfAbsent(establishmentId, () => []);
    _userSubscriptions[establishmentId]!
        .add(DateTime.now().toString());

    await _firebaseService.updateUserData(
      userId,
      {'subscriptions': _userSubscriptions},
    );
    await _loadUserSubscriptions();  // Recarrega imediatamente

    // Criar sessão
    await _startClientSession(establishmentId, _currentTableId!);
    _showClientMainScreen();

    // Novo: Recarregar subscriptions para atualizar UI
    await _loadUserSubscriptions();
    setState(() {});  // Força rebuild das abas
  } catch (e) {
    _showSnackBar('Erro ao processar assinatura: $e', isError: true);
  }
}

  // ==========================================
  // MOSTRAR TELA PRINCIPAL DO CLIENTE
  // ==========================================
  void _showClientMainScreen() {
    setState(() {
      _currentTabIndex = 0;
      _showQRScanner = false;
    });
  }

  // ==========================================
  // CHAMAR GARÇOM
  // ==========================================
  Future<void> _callWaiter() async {
    try {
      if (_currentEstablishmentId == null || _currentTableId == null) return;

      await _firebaseService.callWaiter(
        establishmentId: _currentEstablishmentId!,
        customerId: _auth.currentUser!.uid,
        tableId: _currentTableId!,
        reason: 'Cliente solicitando garçom',
      );

      _showSnackBar('Garçom chamado! Aguarde a resposta...', isError: false);
    } catch (e) {
      _showSnackBar('Erro ao chamar garçom: $e', isError: true);
    }
  }

  // ==========================================
  // FAZER PEDIDO
  // ==========================================
  void _showMakeOrderScreen() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _MakeOrderBottomSheet(
        establishmentId: _currentEstablishmentId!,
        tableId: _currentTableId!,
        sessionId: _currentSessionId!,
        notificationService: _notificationService,
        onOrderPlaced: () {
          Navigator.pop(context);
          _showSnackBar('Pedido enviado!', isError: false);
        },
      ),
    );
  }

  // ==========================================
  // SAIR DO RESTAURANTE
  // ==========================================
Future<void> _exitEstablishment() async {
  try {
    if (_currentSessionId == null) {
      _showSnackBar('Nenhuma sessão ativa', isError: true);
      return;
    }

    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      _showSnackBar('Usuário não autenticado', isError: true);
      return;
    }

    // PASSO 1: Verificar se existem pedidos não finalizados
    if (_currentEstablishmentId != null) {
      final orders = await _firebaseService.getRecentOrders(_currentEstablishmentId!);
      final activeOrders = orders
          .where((o) =>
              o['customerId'] == userId &&
              o['status'] != 'completed' &&
              o['status'] != 'delivered' &&
              o['status'] != 'cancelled' &&
              o['status'] != 'rejected')
          .toList();

      if (activeOrders.isNotEmpty) {
        _showSnackBar(
          'Você tem ${activeOrders.length} pedido(s) em andamento. Finalize-os antes de sair.',
          isError: true,
        );
        return;
      }
    }

    // PASSO 2: Deletar a sessão do cliente
    if (_currentSessionId != null && _currentEstablishmentId != null) {
      try {
        await _firestore
            .collection('establishments')
            .doc(_currentEstablishmentId!)
            .collection('sessions')
            .doc(_currentSessionId!)
            .delete();
        debugPrint('Sessão deletada: $_currentSessionId');
      } catch (e) {
        debugPrint('Erro ao deletar sessão: $e');
        // Continuar mesmo se falhar
      }
    }

    // PASSO 3: Liberar a mesa (desocupar)
    if (_currentSessionId != null && 
        _currentEstablishmentId != null && 
        _currentTableId != null) {
      try {
        await _firestore
            .collection('establishments')
            .doc(_currentEstablishmentId!)
            .collection('tables')
            .doc(_currentTableId!)
            .update({
              'isOccupied': false,
              'currentCustomerId': null,
              'updatedAt': FieldValue.serverTimestamp(),
            });
        debugPrint('Mesa liberada: ${_currentTableName ?? 'Carregando...'}');
      } catch (e) {
        debugPrint('Erro ao liberar mesa: $e');
        // Continuar mesmo se falhar
      }
    }

    // PASSO 4: Limpar estado local
    setState(() {
      _currentSessionId = null;
      _currentEstablishmentId = null;
      _currentTableId = null;
      _currentEstablishment = null;
      _showQRScanner = true;
    });

    _showSnackBar('Você saiu do restaurante com sucesso!', isError: false);

  } catch (e) {
    debugPrint('Erro ao sair: $e');
    _showSnackBar('Erro ao sair: $e', isError: true);
  }
}


  // ==========================================
  // INTERFACE PRINCIPAL
  // ==========================================
@override
Widget build(BuildContext context) {
  if (_isLoading) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: GarconTheme.primaryGradient),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
    );
  }

  if (_showQRScanner) {
    return _buildQRScannerScreen();
  }

  return WillPopScope(
    onWillPop: () async {
      // Perguntar ao usuário se deseja sair
      final shouldExit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sair do Restaurante?'),
          content: const Text(
              'Você tem certeza que deseja sair? Seus pedidos não finalizados serão mantidos.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Voltar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Sair'),
            ),
          ],
        ),
      );

      if (shouldExit == true) {
        await _exitEstablishment();
      }

      return false;
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          _currentEstablishment?['name'] ?? 'Garçon',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.shopping_cart), text: 'Pedido'),
            Tab(icon: Icon(Icons.business), text: 'Estabelecimentos'),
            Tab(icon: Icon(Icons.person), text: 'Perfil'),
          ],
        ),
        actions: [
          PopupMenuButton(
            itemBuilder: (context) => [
              PopupMenuItem(
                onTap: () {
                  Future.delayed(Duration.zero, () => _exitEstablishment());
                },
                child: const Text('Sair do restaurante'),
              ),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOrderTab(),
          _buildEstablishmentsTab(),
          _buildProfileTab(),
        ],
      ),
    ),
  );
}

  // ==========================================
  // TELA DE SCANNER QR
  // ==========================================
Widget _buildQRScannerScreen() {
  bool hasScanned = false; // ✅ Flag para evitar múltiplos scans
  final controller = MobileScannerController();
  
  return Scaffold(
    appBar: AppBar(
      title: const Text('Escanear QR Code da Mesa'),
      centerTitle: true,
      backgroundColor: const Color(0xFF0047AB).withOpacity(0.8),
      elevation: 0,
    ),
    body: Stack(
      children: [
        // ✅ CÂMERA - QR SCANNER
        MobileScanner(
          controller: controller,
          onDetect: (capture) async {
            // ✅ Evita múltiplos triggers
            if (hasScanned) return;
            hasScanned = true;
            
            try {
              if (capture.barcodes.isEmpty) {
                hasScanned = false;
                return;
              }
              
              final barcode = capture.barcodes.first;
              if (barcode.rawValue == null || barcode.rawValue!.isEmpty) {
                hasScanned = false;
                return;
              }
              
              debugPrint('DEBUG: QR code detectado: ${barcode.rawValue}');
              
              // ✅ PARAR câmera imediatamente
              await controller.stop();
              
              // ✅ Processar QR
              _processMobileScanned(capture);
              
              // ✅ Aguarde um pouco para garantir finalização
              await Future.delayed(const Duration(milliseconds: 500));
              
              if (!mounted) return;
              
              // ✅ Fechar dialog/tela
              controller.dispose();
              
            } catch (e) {
              debugPrint('Erro ao processar QR: $e');
              hasScanned = false;
              
              await controller.stop();
              
              if (!mounted) return;
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Erro: ${e.toString().split(':').first}'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                ),
              );
              
              // ✅ Reiniciar câmera após erro
              await Future.delayed(const Duration(milliseconds: 800));
              
              if (!mounted) return;
              
              try {
                await controller.start();
                hasScanned = false;
              } catch (e) {
                debugPrint('Erro ao reiniciar câmera: $e');
              }
            }
          },
          errorBuilder: (context, error) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.camera_alt_outlined,
                    size: 60,
                    color: Colors.white70,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Erro ao acessar câmera',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Verifique as permissões',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => controller.start(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0047AB),
                    ),
                  ),
                ],
              ),
            );
          },
          placeholderBuilder: (context) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          },
        ),
        
        // ✅ OVERLAY COM INSTRUÇÕES (PARTE INFERIOR)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.0),
                  Colors.black.withOpacity(0.8),
                  Colors.black.withOpacity(0.95),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ✅ ÍCONE ANIMADO
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.qr_code_2,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // ✅ TÍTULO
                const Text(
                  'Aponte para o QR Code',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 8),
                
                // ✅ INSTRUÇÕES
                Text(
                  'Posicione o QR code da mesa no centro da tela',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 16),
                
                // ✅ DICAS
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.blue.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'A câmera irá detectar\nautomaticamente o QR',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // ✅ OVERLAY COM BORDA (PARA MOSTRAR ONDE FOCAR)
        Positioned(
          top: 60,
          left: 40,
          right: 40,
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.white.withOpacity(0.6),
                width: 3,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 230,
                height: 230,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
        
          // ✅ BOTÃO VOLTAR (topo esquerdo) - CORRIGIDO
          Positioned(
            top: 16,
            left: 16,
            child: SafeArea(
              child: GestureDetector(
                onTap: () {
                  controller.dispose();
                  _showQRNotScannedDialog();
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}


  // ==========================================
  // ABA DE PEDIDO
  // ==========================================
  Widget _buildOrderTab() {
    if (_currentSessionId == null) {
      return const Center(
        child: Text('Nenhuma sessão ativa'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Informações da mesa
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Informações da Mesa',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Restaurante: ${_currentEstablishment?['name'] ?? 'N/A'}'),
                  Text('Mesa: ${_currentTableName ?? 'Carregando...'}'),
                  Text('Endereço: ${_currentEstablishment?['address'] ?? 'N/A'}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _callWaiter,
            icon: const Icon(Icons.person),
            label: const Text('Chamar Garçom'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: Colors.blue,
            ),
          ),
          const SizedBox(height: 12),

          ElevatedButton.icon(
            onPressed: _showMakeOrderScreen,
            icon: const Icon(Icons.restaurant_menu),
            label: const Text('Fazer Pedido'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: Colors.green,
            ),
          ),
          const SizedBox(height: 20),

          // Pedidos ativos
          const Text(
            'Seus Pedidos',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildActiveOrdersList(),
        ],
      ),
    );
  }

  // ==========================================
  // LISTA DE PEDIDOS ATIVOS
  // ==========================================
  Widget _buildActiveOrdersList() {
    if (_currentSessionId == null || _currentEstablishmentId == null) {
      return const Center(child: Text('Nenhum pedido'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _firebaseService.getOrdersStream(_currentEstablishmentId!),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text('Erro: ${snapshot.error}');
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final orders = snapshot.data!.docs
            .where((doc) => doc['customerId'] == _auth.currentUser?.uid)
            .toList();

        if (orders.isEmpty) {
          return const Center(
            child: Text('Você não tem pedidos no momento'),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index].data() as Map<String, dynamic>;
            return _buildOrderCard(order);
          },
        );
      },
    );
  }

  // ==========================================
  // CARD DE PEDIDO
  // ==========================================
  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = order['status'] as String? ?? 'unknown';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Pedido #${order['id']?.substring(0, 8) ?? 'N/A'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColors[status] ?? Colors.grey,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabels[status] ?? status,  // ← Mude para isso: usa o label em PT
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (status == 'pending' || status == 'accepting') // ← Condição para mostrar a lixeira
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteOrder(order['id'] ?? ''), // ← Chama a nova função
                    ),
              ],
            ),
            const SizedBox(height: 8),
            if (status == 'completed')
              ElevatedButton.icon(
                onPressed: () => _showRatingDialog(order),
                icon: const Icon(Icons.star),
                label: const Text('Avaliar'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 40),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // DIALOG DE AVALIAÇÃO
  // ==========================================
  void _showRatingDialog(Map<String, dynamic> order) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RatingDialog(
        order: order,
        establishment: _currentEstablishment,
        establishmentId: _currentEstablishmentId ?? '',
        userId: _auth.currentUser?.uid ?? '',
      ),
    );
  }

  // ==========================================
// EXCLUIR PEDIDO (ALTERA STATUS PARA CANCELADO)
// ==========================================
Future<void> _deleteOrder(String orderId) async {
  if (_currentEstablishmentId == null || orderId.isEmpty) {
    _showSnackBar('Erro: Não foi possível identificar o pedido', isError: true);
    return;
  }

  try {
    // Confirmação do usuário
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Pedido?'),
        content: const Text('Tem certeza que deseja cancelar este pedido? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Não'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sim, Cancelar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Atualiza o status no Firestore para 'cancelled'
    await _firestore
        .collection('establishments')
        .doc(_currentEstablishmentId!)
        .collection('orders')
        .doc(orderId)
        .update({
          'status': 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Após: await _firestore ... .update({'status': 'cancelled', ...});
      debugPrint('Pedido cancelado - Cloud Function será triggerada para notificar garçons');

    _showSnackBar('Pedido cancelado com sucesso!', isError: false);
  } catch (e) {
    debugPrint('Erro ao cancelar pedido: $e');
    _showSnackBar('Erro ao cancelar pedido: $e', isError: true);
  }
}

  Future<void> _loadOrderHistory() async {
  try {
    if (_currentEstablishmentId == null) return;

    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    final history = await _firebaseService.getClientOrderHistory(
      userId,
      _currentEstablishmentId!,
    );

    // Aqui você pode usar a história de pedidos
    // Exemplo: para mostrar em uma nova aba ou widget
  } catch (e) {
    debugPrint('Erro ao carregar histórico: $e');
  }
}

// NOVO: Tab para histórico de pedidos
Widget _buildOrderHistoryTab() {
  if (_currentEstablishmentId == null) {
    return const Center(
      child: Text('Selecione um estabelecimento'),
    );
  }

  final userId = _auth.currentUser?.uid;
  if (userId == null) {
    return const Center(
      child: Text('Erro ao carregar histórico'),
    );
  }

  return FutureBuilder<List<Map<String, dynamic>>>(
    future: _firebaseService.getClientOrderHistory(
      userId,
      _currentEstablishmentId!,
    ),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }

      if (snapshot.hasError) {
        return Center(child: Text('Erro: ${snapshot.error}'));
      }

      final orders = snapshot.data ?? [];

      if (orders.isEmpty) {
        return const Center(
          child: Text('Você não tem histórico de pedidos'),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          return _buildHistoryOrderCard(order);
        },
      );
    },
  );
}

Widget _buildHistoryOrderCard(Map<String, dynamic> order) {
  return Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      title: Text(
        'Pedido #${order['id']?.substring(0, 8) ?? 'N/A'}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Data: ${DateTime.parse(order['createdAt'].toDate().toString()).day}/${DateTime.parse(order['createdAt'].toDate().toString()).month}/${DateTime.parse(order['createdAt'].toDate().toString()).year}',
          ),
          Text('Total: R\$ ${order['totalPrice']?.toStringAsFixed(2) ?? '0.00'}'),
        ],
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Finalizado',
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    ),
  );
}

// ==========================================
// ABA DE ESTABELECIMENTOS
// ==========================================
Widget _buildEstablishmentsTab() {
  if (_userSubscriptions.isEmpty) {
    return const Center(
      child: Text('Nenhuma assinatura ativa'),
    );
  }

  return ListView.builder(
    padding: const EdgeInsets.all(16),
    itemCount: _userSubscriptions.length,
    itemBuilder: (context, index) {
      final estId = _userSubscriptions.keys.elementAt(index);
      final subs = _userSubscriptions[estId]!;

      return FutureBuilder<Map<String, dynamic>?>(
        future: _firebaseService.getEstablishmentData(estId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const ListTile(title: Text('Carregando...'));
          }
          final est = snapshot.data;
          return ListTile(
            title: Text(est?['name'] ?? 'Estabelecimento $estId'),
            subtitle: Text('${subs.length} assinaturas ativas'),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _loadUserSubscriptions(),  // Recarregar
            ),
          );
        },
      );
    },
  );
}

  // ==========================================
  // CARD DE ESTABELECIMENTO
  // ==========================================
  Widget _buildEstablishmentCard(String establishmentId) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _firebaseService.getEstablishmentData(establishmentId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData) {
          return const SizedBox();
        }

        final establishment = snapshot.data!;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const Icon(Icons.restaurant, size: 40),
            title: Text(
              establishment['name'] ?? 'Estabelecimento',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(establishment['address'] ?? ''),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () {
              _showSnackBar(
                'Você pode voltar para este estabelecimento a qualquer hora',
                isError: false,
              );
            },
          ),
        );
      },
    );
  }

  // ==========================================
  // ABA DE PERFIL
  // ==========================================
Widget _buildProfileTab() {
  return FutureBuilder<Map<String, dynamic>?>(
    future: _firebaseService.getUserData(_auth.currentUser?.uid ?? ''),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor));
      }

      final user = snapshot.data ?? {};

      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            elevation: 6,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                    child: const Icon(Icons.person, size: 50, color: Color(0xFF6EC1E4)),
                  ),
                  const SizedBox(height: 16),
                  Text(user['name'] ?? 'Usuário', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Text(user['email'] ?? '', style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  Text(user['phoneNumber'] ?? 'Sem telefone', style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(height: 24),

                  // Histórico dos últimos 5 pedidos
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Últimos 5 Pedidos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _firebaseService.getClientOrderHistory(_auth.currentUser!.uid, _currentEstablishmentId ?? ''),
                    builder: (context, historySnapshot) {
                      if (historySnapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final orders = historySnapshot.data ?? [];
                      if (orders.isEmpty) {
                        return const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('Nenhum pedido ainda', textAlign: TextAlign.center),
                          ),
                        );
                      }
                      return Column(
                        children: orders.take(5).map((order) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.receipt, color: Color(0xFF6EC1E4)),
                            title: Text('Pedido da mesa ${order['tableId']}'),
                            subtitle: Text(
                              DateTime.fromMillisecondsSinceEpoch(order['createdAt'].seconds * 1000)
                                  .toString().substring(0, 16),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text('Concluído', style: TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                          ),
                        )).toList(),
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  // Botão de logout (agora embaixo!)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout),
                      label: const Text('Sair da Conta'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

  // ==========================================
  // LOGOUT
  // ==========================================
  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/login',
          (route) => false,
        );
      }
    } catch (e) {
      _showSnackBar('Erro ao sair: $e', isError: true);
    }
  }

  // ==========================================
  // UTILITÁRIOS
  // ==========================================
  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    // Se o usuário sair do app sem clicar em "Sair da Mesa", marcamos como inativa (opcional)
    if (_currentSessionId != null) {
      // Fire-and-forget: não esperamos, só marca como inativa
      _firebaseService.updateSession(_currentSessionId!, {
        'status': 'inactive_by_close',
        'endedAt': FieldValue.serverTimestamp(),
      }).catchError((e) => debugPrint('Erro ao marcar sessão como inativa: $e'));
    }

    _tabController.dispose();
    super.dispose();
  }
}

// ==========================================
// BOTTOM SHEET - FAZER PEDIDO
// ==========================================
  class _MakeOrderBottomSheet extends StatefulWidget {
    final String establishmentId;
    final String tableId;
    final String sessionId;
    final Function onOrderPlaced;
    final NotificationService notificationService; // ← NOVO

    const _MakeOrderBottomSheet({
      required this.establishmentId,
      required this.tableId,
      required this.sessionId,
      required this.onOrderPlaced,
      required this.notificationService, // ← required
    });

    @override
    State<_MakeOrderBottomSheet> createState() => _MakeOrderBottomSheetState();
 }

class _MakeOrderBottomSheetState extends State<_MakeOrderBottomSheet> {
  final TextEditingController _orderController = TextEditingController();
  final FirebaseService _firebaseService = FirebaseService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Seu Pedido',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _orderController,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'Escreva seu pedido aqui...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitOrder,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Enviar Pedido'),
              ),
            ],
          ),
        ),
      ),
    );
  }

Future<void> _submitOrder() async {
  if (_orderController.text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Digite seu pedido')),
    );
    return;
  }

  setState(() => _isLoading = true);

  try {
    await _firebaseService.createOrder(
      establishmentId: widget.establishmentId,
      customerId: _auth.currentUser!.uid,
      tableId: widget.tableId,
      sessionId: widget.sessionId,
      items: [
        {
          'description': _orderController.text,
          'price': 0.0,
          'quantity': 1,
        }
      ],
      notes: _orderController.text,
    );

    // Envia notificação para os garçons (agora funciona!)
    await NotificationService().sendNewOrderNotificationToWaiter(
      waiterId: 'all_waiters', // ou o ID específico do garçom
      orderNumber: widget.tableId,
      tableNumber: widget.tableId,
      itemCount: 1, // só tem 1 item por enquanto
    );

    if (mounted) {
      widget.onOrderPlaced();
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}

  @override
  void dispose() {
    _orderController.dispose();
    super.dispose();
  }
}

// ==========================================
// DIALOG - AVALIAÇÃO
// ==========================================
class _RatingDialog extends StatefulWidget {
  final Map<String, dynamic> order;
  final Map<String, dynamic>? establishment;
  final String establishmentId;
  final String userId;

  const _RatingDialog({
    required this.order,
    required this.establishment,
    required this.establishmentId,
    required this.userId,
  });

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  int _waiterRating = 5;
  int _restaurantRating = 5;
  String _comment = '';
  bool _isSubmitting = false;
  final FirebaseService _firebaseService = FirebaseService();
  final TextEditingController _commentController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Avaliar Experiência'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avaliação do Restaurante
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12.0),
              child: Text(
                'Como foi o restaurante?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _buildRatingBar(
              rating: _restaurantRating,
              onChanged: (value) =>
                  setState(() => _restaurantRating = value),
            ),
            const SizedBox(height: 20),

            // Avaliação do Garçom (se houver)
            if (widget.order['assignedWaiter'] != null)
              Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(
                      'Como foi o atendimento?',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _buildRatingBar(
                    rating: _waiterRating,
                    onChanged: (value) =>
                        setState(() => _waiterRating = value),
                  ),
                  const SizedBox(height: 20),
                ],
              ),

            // Campo de comentário
            TextField(
              controller: _commentController,
              maxLines: 3,
              maxLength: 200,
              decoration: InputDecoration(
                hintText: 'Deixe um comentário (opcional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (value) => _comment = value,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitRating,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enviar'),
        ),
      ],
    );
  }

  Widget _buildRatingBar({required int rating, required Function(int) onChanged}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        5,
        (index) => IconButton(
          onPressed: () => onChanged(index + 1),
          icon: Icon(
            index < rating ? Icons.star : Icons.star_border,
            color: Colors.amber,
            size: 32,
          ),
        ),
      ),
    );
  }

  Future _submitRating() async {
  setState(() => _isSubmitting = true);
  try {
    // Salvar avaliação no Firebase
    await _firebaseService.createRating(
      establishmentId: widget.establishmentId,
      userId: widget.userId,
      orderId: widget.order['id'],
      restaurantRating: _restaurantRating,
      waiterRating: widget.order['assignedWaiter'] != null ? _waiterRating : null,
      waiterName: widget.order['assignedWaiter'],
      comment: _comment.isNotEmpty ? _comment : null,
    );

    // ✅ NOVO: Atualizar rating médio do garçom
    if (widget.order['assignedWaiter'] != null) {
      await _firebaseService.updateWaiterAverageRating(
        widget.order['assignedWaiter'],
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Obrigado pela avaliação! 🙏'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    if (mounted) {
      setState(() => _isSubmitting = false);
    }
  }
}

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }
}

// NOVO: Classe para gerenciar pagamentos
class _PaymentManager {
  final PaymentService _paymentService = PaymentService();
  final FirebaseService _firebaseService = FirebaseService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> initializePayments() async {
    try {
      await _paymentService.initialize();
      debugPrint('✅ Payment Service inicializado');
    } catch (e) {
      debugPrint('❌ Erro ao inicializar Payment: $e');
    }
  }

  /// Processar compra de assinatura
  Future<bool> processSubscriptionPayment({
    required String establishmentId,
    required String productId, // 'garcon_monthly_subscription' ou 'garcon_yearly_subscription'
  }) async {
    try {
      // 1. Iniciar compra
      await _paymentService.buySubscription(
        productId: productId,
        establishmentId: establishmentId,
      );

      // 2. Escutar resultado da compra (feito através do stream do PaymentService)
      // O resultado virá no callback _handlePurchaseUpdates

      return true;
    } catch (e) {
      debugPrint('Erro ao processar pagamento: $e');
      return false;
    }
  }

  /// Registrar pagamento no Firebase (após confirmação do Google Play/Apple)
  Future<void> recordPaymentInFirebase({
    required String establishmentId,
    required double amount,
    required String transactionId,
    required String platform, // 'android' ou 'ios'
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      await _firebaseService.recordSubscriptionPayment(
        userId: userId,
        establishmentId: establishmentId,
        amount: amount,
        transactionId: transactionId,
        platform: platform,
      );

      debugPrint('✅ Pagamento registrado no Firebase');
    } catch (e) {
      debugPrint('Erro ao registrar pagamento: $e');
    }
  }

  void dispose() {
    _paymentService.dispose();
  }
}

// ==========================================
// BOTTOM SHEET - PAGAMENTO
// ==========================================
class _PaymentBottomSheet extends StatefulWidget {
  final Map<String, dynamic> establishment;
  final Function onPaymentSuccess;
  final Function onCancel;

  const _PaymentBottomSheet({
    required this.establishment,
    required this.onPaymentSuccess,
    required this.onCancel,
  });

  @override
  State<_PaymentBottomSheet> createState() => _PaymentBottomSheetState();
}

class _PaymentBottomSheetState extends State<_PaymentBottomSheet> {
  bool _isProcessing = false;
  final _paymentManager = _PaymentManager();

  @override
  void initState() {
    super.initState();
    _paymentManager.initializePayments();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Assinatura Necessária',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Para usar ${widget.establishment['name']}, você precisa de uma assinatura',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Plano Mensal
          _buildPricingCard(
            title: 'Plano Mensal',
            price: 'R\$ 10,99',
            period: 'por mês',
            features: const [
              '✓ Acesso a este estabelecimento',
              '✓ Chamar garçom',
              '✓ Fazer pedidos',
              '✓ Acompanhamento em tempo real',
            ],
            onTap: () => _processMonthlPayment(),
          ),
          const SizedBox(height: 16),

          // Plano Anual (Económico)
          _buildPricingCard(
            title: 'Plano Anual',
            price: 'R\$ 99,90',
            period: 'por ano',
            subtitle: 'Economize R\$ 30,98',
            features: const [
              '✓ Acesso a este estabelecimento',
              '✓ Chamar garçom',
              '✓ Fazer pedidos',
              '✓ Acompanhamento em tempo real',
              '✓ Desconto especial',
            ],
            onTap: () => _processAnnualPayment(),
            isHighlighted: true,
          ),
          const SizedBox(height: 20),

          TextButton(
            onPressed: _isProcessing ? null : () => widget.onCancel(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingCard({
    required String title,
    required String price,
    required String period,
    required List<String> features,
    required VoidCallback onTap,
    String? subtitle,
    bool isHighlighted = false,
  }) {
    return Card(
      elevation: isHighlighted ? 8 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isHighlighted
            ? const BorderSide(color: Colors.green, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (isHighlighted)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'MELHOR',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: price,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(
                    text: ' $period',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ...features
                .map((feature) => Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        feature,
                        style: const TextStyle(fontSize: 13),
                      ),
                    )),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _isProcessing ? null : onTap,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 45),
                backgroundColor: isHighlighted ? Colors.green : null,
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Escolher'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processMonthlPayment() async {
    await _processPaymentFlow('garcon_monthly_subscription', 10.99);
  }

  Future<void> _processAnnualPayment() async {
    await _processPaymentFlow('garcon_yearly_subscription', 99.90);
  }

  // Future<void> _processPaymentFlow(
   // String productId,
  //  double amount,
 // ) async {
 //   setState(() => _isProcessing = true);

 //   try {
      // 1. Iniciar fluxo de pagamento
 //     final success = await _paymentManager.processSubscriptionPayment(
   //     establishmentId: widget.establishment['id'],
   //     productId: productId,
   //   );

   //   if (!success) {
   //     throw Exception('Falha ao processar pagamento');
   //   }

      // 2. Registrar no Firebase (feito através do callback do PaymentService)
      // O PaymentService notifica quando o pagamento é bem-sucedido

  //    if (mounted) {
   //     ScaffoldMessenger.of(context).showSnackBar(
   //       const SnackBar(
   //         content: Text('Pagamento processado com sucesso! 🎉'),
    //        backgroundColor: Colors.green,
    //      ),
    //    );
    //    widget.onPaymentSuccess();
   //   }
   // } catch (e) {
   //   if (mounted) {
    //    ScaffoldMessenger.of(context).showSnackBar(
    //      SnackBar(
    //        content: Text('Erro: $e'),
    //        backgroundColor: Colors.red,
    //      ),
    //    );
    //  }
   // } finally {
   //   if (mounted) {
   //     setState(() => _isProcessing = false);
   //   }
   // }
  //}

  Future<void> _processPaymentFlow(String productId, double amount) async {
  setState(() => _isProcessing = true);

  try {
    // COMENTE O PAGAMENTO REAL
    // final success = await _paymentManager.processSubscriptionPayment(
    //   establishmentId: widget.establishment['id'],
    //   productId: productId,
    // );

    // if (!success) throw Exception('Falha ao processar pagamento');

    // SIMULAÇÃO PARA TESTES: Aprovação automática em 2 segundos
    await Future.delayed(const Duration(seconds: 2));  // Simula processamento
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pagamento simulado com sucesso! 🎉'),
          backgroundColor: Colors.green,
        ),
      );
      widget.onPaymentSuccess();
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro simulado: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    if (mounted) {
      setState(() => _isProcessing = false);
    }
  }
}

  @override
  void dispose() {
    _paymentManager.dispose();
    super.dispose();
  }
}
