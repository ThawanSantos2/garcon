// ignore_for_file: use_super_parameters, unused_import, unused_field, unused_local_variable, unnecessary_cast

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
import '../config/theme_config.dart';

class WaiterHomePage extends StatefulWidget {
  const WaiterHomePage({Key? key}) : super(key: key);

  @override
  State<WaiterHomePage> createState() => _WaiterHomePageState();
}

class _WaiterHomePageState extends State<WaiterHomePage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late StreamSubscription<DocumentSnapshot> _userListener;// ✅ NOVO: Filtro de status na aba Aceitos  // Novo: Listener para Firestore
  final FirebaseService _firebaseService = FirebaseService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  // Estado
  String? _establishmentId;
  String? selectedStatusFilter; // ✅ NOVO: Filtro de status na aba Aceitos
  Map<String, dynamic>? _waiterData;
  Map<String, dynamic>? _establishmentData;
  bool _isLoading = true;
  String? _waiterQRCode;

  // Status disponíveis
  final List<String> _orderStatuses = [
    'pending',
    'accepting',
    'preparing',
    'ready',
    'on_the_way',
    'delivered',
    'completed',
    'cancelled',
    'rejected',
  ];

  final Map<String, String> _statusLabels = {
    'pending': 'Pendente',
    'accepting': 'Aceito',
    'preparing': 'Em Preparação',
    'ready': 'Pedido Pronto',
    'on_the_way': 'A Caminho',
    'delivered': 'Entregue',
    'completed': 'Completado',
    'cancelled': 'Cancelado',
    'rejected': 'Recusado',
  };

  final Map<String, Color> _statusColors = {
    'pending': Colors.orange,
    'accepting': Colors.deepOrange,
    'preparing': Colors.blue,
    'ready': Colors.green,
    'on_the_way': Colors.purple,
    'delivered': Colors.teal,
    'completed': Colors.cyan,
    'cancelled': Colors.red,
    'rejected': Colors.red.shade900,
  };

  final Map<String, IconData> _statusIcons = {
    'pending': Icons.hourglass_bottom,
    'preparing': Icons.restaurant,
    'ready': Icons.check_circle,
    'on_the_way': Icons.directions_run,
    'delivered': Icons.celebration,
    'completed': Icons.celebration,
    'cancelled': Icons.cancel,
    'rejected': Icons.block,
  };

@override
void initState() {
  super.initState();
  _tabController = TabController(length: 6, vsync: this);
  _initializeWaiterData();
  setupNotifications();

  // ✅ CORRIGIDO: Listener agora é debounced
  final user = _auth.currentUser;
  if (user != null) {
    _userListener = _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && mounted) {  // ← Adicione 'mounted'
            final data = snapshot.data() as Map?;
            final newEstId = data?['establishmentId'] as String?;
            
            if (newEstId != null && 
                newEstId.isNotEmpty && 
                newEstId != _establishmentId) {
              
              // ✅ Limpar variáveis para force rebuild
              if (mounted) {
                setState(() {
                  _establishmentId = null;  // Reset antes de recarregar
                  _isLoading = true;
                });
                
                // Aguarde um frame para evitar problemas
                Future.delayed(const Duration(milliseconds: 100), () {
                  if (mounted) {
                    _initializeWaiterData();
                  }
                });
              }
            }
          }
        });
  }
}


Future<void> setupNotifications() async {
  debugPrint('🔧 Inicializando notificações...');
  
  await _notificationService.initializeNotifications();
  
  final user = _auth.currentUser;
  if (user != null) {
    debugPrint('👤 Usuário: ${user.uid}');
    
    // Obter token FCM
    final token = await _notificationService.getUserFCMToken();
    debugPrint('🔑 Token FCM: ${token?.substring(0, 20)}...');
    
    if (token != null) {
      await _notificationService.saveFCMTokenToFirestore(user.uid, token);
      debugPrint('✅ Token salvo em Firestore');
    } else {
      debugPrint('⚠️ Token FCM não obtido! Possível problema com FCM.');
    }
    
    // ✅ NOVO: Configurar listener para alertas
    if (_establishmentId != null && _establishmentId!.isNotEmpty) {
      debugPrint('🎧 Escutando alertas do estabelecimento: $_establishmentId');
      _notificationService.setupWaiterAlertListener(_establishmentId!, user.uid);
            // Listener para cancelamentos de pedidos
      _notificationService.getUserNotificationsStream(_auth.currentUser!.uid).listen((notifications) {
        for (var notif in notifications) {
          if (notif['type'] == 'order_cancelled' && notif['read'] == false) {
            // Mostrar snackbar ou dialog
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(notif['body'] as String),
                backgroundColor: Colors.red,
              ),
            );
            _notificationService.markNotificationAsRead(notif['id'] as String);
          }
        }
      });
      
      // ✅ NOVO: Fallback via polling (caso FCM falhe)
      debugPrint('⏲️ Ativando fallback de polling...');
      _notificationService.setupWaiterAlertPolling(_establishmentId!, user.uid);
                  // Listener para cancelamentos de pedidos
      _notificationService.getUserNotificationsStream(_auth.currentUser!.uid).listen((notifications) {
        for (var notif in notifications) {
          if (notif['type'] == 'order_cancelled' && notif['read'] == false) {
            // Mostrar snackbar ou dialog
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(notif['body'] as String),
                backgroundColor: Colors.red,
              ),
            );
            _notificationService.markNotificationAsRead(notif['id'] as String);
          }
        }
      });
    } else {
      debugPrint('⚠️ Estabelecimento não conectado ainda');
    }
  } else {
    debugPrint('❌ Usuário não autenticado');
  }
}

Future<void> _initializeWaiterData() async {
  if (!mounted) return;
  setState(() => _isLoading = true);

  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _navigateToLogin();
      return;
    }

    // ✅ 1. Pega dados do waiter
    final waiterData = await _firebaseService.getUserData(user.uid);
    if (waiterData == null) {
      throw Exception('Dados do garçom não encontrados');
    }

    final dynamic estIdRaw = waiterData['establishmentId'];

    final String? estId =
        estIdRaw is String && estIdRaw.trim().isNotEmpty ? estIdRaw : null;


    // ✅ 2. VERIFICAÇÃO ROBUSTA - Validar se garçom está realmente cadastrado
    if (estId != null && estId.isNotEmpty && estId.length > 5) {
      // ✅ NOVO: Verificar se garçom existe em /establishments/{id}/waiters
      final waiterInEstablishment = await _firestore
          .collection('establishments')
          .doc(estId)
          .collection('waiters')
          .doc(user.uid)
          .get();

      if (!waiterInEstablishment.exists) {
        debugPrint('ERRO: Garçom NÃO está cadastrado em /waiters');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Você não está cadastrado neste estabelecimento. Escaneie o QR do proprietário.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
        // Limpar e voltar para QR
        if (mounted) {
          setState(() {
            _establishmentId = null;
            _waiterData = null;
            _isLoading = false;
          });
          await _generateWaiterQRCode(user.uid);
        }
        return;
      }

      // ✅ Garçom está cadastrado, prosseguir normalmente
      final estData = await _firebaseService.getEstablishmentData(estId);
      if (!mounted) return;

      setState(() {
        _establishmentId = estId;
        _waiterData = waiterData;
        _establishmentData = estData;
        _isLoading = false;
      });
      debugPrint('DEBUG Garçom ${waiterData['name']} conectado ao estabelecimento');
      debugPrint('TIPO establishmentId: ${waiterData['establishmentId'].runtimeType}');
      debugPrint('VALOR establishmentId: ${waiterData['establishmentId']}');

    } else {
      // Sem establishmentId - mostrar QR para ser escaneado
      debugPrint('DEBUG EstablishmentId vazio ou inválido, mostrando QR');
      if (!mounted) return;

      setState(() {
        _waiterData = waiterData;
        _isLoading = false;
      });

      // Gerar QR code APENAS se não tiver establishmentId
      await _generateWaiterQRCode(user.uid);
    }
  } catch (e, stackTrace) {
    debugPrint('DEBUG Erro ao inicializar: $e');
    debugPrint(stackTrace.toString());
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erro: $e'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _navigateToLogin();
  }
}

  Future<void> _generateWaiterQRCode(String waiterId) async {
    try {
      final qrCode = await _firebaseService.createWaiterQR(waiterId: waiterId);
      if (mounted) {
        setState(() => _waiterQRCode = qrCode);
      }
    } catch (e) {
      debugPrint('Erro ao gerar QR Code: $e');
    }
  }

  void _navigateToLogin() {
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _userListener.cancel();
    super.dispose();
  }

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

  // ✅ CORRIGIDO: Verificação mais robusta
  if (_establishmentId == null || _establishmentId!.isEmpty) {
    debugPrint('DEBUG: Mostrando tela de conexão. EstId: $_establishmentId');
    return _buildConnectionScreen();
  }

  // ✅ Se chegou aqui, garçom está conectado
  debugPrint('DEBUG: Garçom conectado ao estabelecimento: $_establishmentId');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          '${_waiterData?['name'] ?? 'Garçom'}',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _auth.signOut();
              if (mounted) {
                if (!context.mounted) return;
                Navigator.pushReplacementNamed(context, '/welcome');
              }
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: GarconTheme.primaryGradient),
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              labelColor: Colors.white,  // ← Adicione: cor do texto das abas para preto
              unselectedLabelColor: Colors.black.withValues(alpha: 0.6),  // ← Cor para abas não selecionadas (preto suave)
              indicatorColor: Colors.white,
              tabs: const [
                Tab(icon: Icon(Icons.receipt, color: Colors.white), text: 'Pedidos'),
                Tab(icon: Icon(Icons.check_circle, color: Colors.white), text: 'Aceitos'), 
                Tab(icon: Icon(Icons.history, color: Colors.white), text: 'Histórico'),
                Tab(icon: Icon(Icons.person, color: Colors.white), text: 'Perfil'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOrdersTab(),
                  buildAcceptedOrdersTab(), 
                  _buildHistoryTab(),
                  _buildProfileTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TELA DE CONEXÃO AO ESTABELECIMENTO
  // ==========================================

  Widget _buildConnectionScreen() {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: GarconTheme.primaryGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.person_add,
                    size: 80,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Conectar ao Estabelecimento',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Mostre seu QR Code ao proprietário para se registrar',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // QR Code
                  if (_waiterQRCode != null)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data: _waiterQRCode!,
                        version: QrVersions.auto,
                        size: 280,
                        backgroundColor: Colors.white,
                      ),
                    )
                  else
                    Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white30),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),

                  const SizedBox(height: 40),

                  // Informações
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ID do Garçom:',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _auth.currentUser?.uid.substring(0, 8) ?? 'N/A',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  ElevatedButton.icon(
                    onPressed: () async {
                      await _auth.signOut();
                      if (mounted) {
                        Navigator.pushReplacementNamed(context, '/welcome');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                    ),
                    icon: const Icon(Icons.logout),
                    label: const Text('Desconectar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // ABA: PEDIDOS ATIVOS
  // ==========================================

  Widget _buildOrdersTab() {
    if (_establishmentId == null) {
      return const Center(
        child: Text('Estabelecimento não conectado',
            style: TextStyle(color: Colors.black87)),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('orders')
          .where('establishmentId', isEqualTo: _establishmentId)
          .where('status', whereIn: ['pending'])
          .where('assignedWaiter', isEqualTo: null) 
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Erro: ${snapshot.error}',
                style: const TextStyle(color: Colors.red)),
          );
        }

        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        final orders = snapshot.data!.docs;

        if (orders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.assignment_turned_in,
                  size: 80,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Nenhum pedido pendente',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index].data() as Map<String, dynamic>;
            return _buildOrderCard(order, orders[index].id);
          },
        );
      },
    );
  }

  Widget buildAcceptedOrdersTab() {
  if (_establishmentId == null) {
    return const Center(
      child: Text(
        'Estabelecimento não conectado',
        style: TextStyle(color: Colors.black87),
      ),
    );
  }

  final currentWaiterId = _auth.currentUser?.uid;

  return Column(
    children: [
      // ✅ Filtro de status
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.white.withValues(alpha: 0.05),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Botão "Todos"
              GestureDetector(
                onTap: () {
                  setState(() => selectedStatusFilter = null);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: selectedStatusFilter == null
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selectedStatusFilter == null
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'Todos',
                    style: TextStyle(
                      color: selectedStatusFilter == null
                          ? Colors.black
                          : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Botões para cada status
              ...[
                'accepting',
                'preparing',
                'ready',
                'on_the_way',
                'delivered'
              ].map((status) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => selectedStatusFilter = status);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selectedStatusFilter == status
                            ? _statusColors[status]
                            : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selectedStatusFilter == status
                              ? _statusColors[status] ?? Colors.white
                              : Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        _statusLabels[status] ?? status,
                        style: TextStyle(
                          color: selectedStatusFilter == status
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.7),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                );
              // ignore: unnecessary_to_list_in_spreads
              }).toList(),
            ],
          ),
        ),
      ),

      // Lista de pedidos
      Expanded(
        child: StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('orders')
              .where('establishmentId', isEqualTo: _establishmentId)
              .where('assignedWaiter', isEqualTo: currentWaiterId)
              .where('status',
                  whereNotIn: ['pending', 'rejected', 'cancelled', 'delivered'])
              .orderBy('acceptedAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Erro: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }

            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }

            var orders = snapshot.data!.docs;

            // ✅ Aplicar filtro de status
            if (selectedStatusFilter != null) {
              orders = orders
                  .where((doc) =>
                      (doc.data() as Map<String, dynamic>)['status'] ==
                      selectedStatusFilter)
                  .toList();
            }

            if (orders.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.done_all,
                      size: 80,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      selectedStatusFilter == null
                          ? 'Nenhum pedido aceito'
                          : 'Nenhum pedido com status "${_statusLabels[selectedStatusFilter]}"',
                      style: const TextStyle(
                          color: Colors.black87, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index].data() as Map<String, dynamic>;
                return buildAcceptedOrderCard(order, orders[index].id);
              },
            );
          },
        ),
      ),
    ],
  );
}

Widget buildAcceptedOrderCard(Map<String, dynamic> order, String orderId) {
  final status = order['status'] as String? ?? 'accepting';

  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF001F3F),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: _statusColors[status] ?? Colors.white.withValues(alpha: 0.5),
        width: 2,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: Mesa e status
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FutureBuilder(
                  future: _firestore
                      .collection('establishments')
                      .doc(_establishmentId)
                      .collection('tables')
                      .doc(order['tableId'] ?? '')
                      .get(),
                  builder: (context, snapshot) {
                    String displayName = 'Mesa';
                    if (snapshot.hasData && snapshot.data!.exists) {
                      final data =
                          snapshot.data!.data() as Map<String, dynamic>;
                      final name = data['name']?.toString().trim();
                      if (name != null && name.isNotEmpty) {
                        displayName = name;
                      }
                    }
                    return Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  'Pedido ${orderId.substring(0, 8)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _statusColors[status] ?? Colors.grey,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    color: Colors.white,
                    size: 8,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _statusLabels[status] ?? status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Itens
        const Text(
          'Itens',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 8),
        if (order['items'] is List)
          ...(order['items'] as List).map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${item['name']} x${item['quantity']}',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            );
          }).toList(),

        const SizedBox(height: 12),

        // Total
        Text(
          'Total: R\$ ${(order['totalPrice'] ?? 0).toStringAsFixed(2)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),

        // Observações
        if (order['notes'] != null &&
            (order['notes'] as String).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Obs: ${order['notes']}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),

        const SizedBox(height: 16),

        // Botões de mudança de status
        _buildStatusChangeButtons(orderId, status),
      ],
    ),
  );
}

  Widget _buildOrderCard(Map<String, dynamic> order, String orderId) {
    final status = order['status'] as String? ?? 'pending';
    final assignedWaiter = order['assignedWaiter'] as String?;
    final currentWaiterId = _auth.currentUser?.uid;
    final isMyOrder = assignedWaiter == currentWaiterId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF001F3F), //Azul escuro
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _statusColors[status] ?? Colors.white.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FutureBuilder(
                    future: _firestore
                        .collection('establishments')
                        .doc(_establishmentId)
                        .collection('tables')
                        .doc(order['tableId'] ?? '')
                        .get(),
                    builder: (context, snapshot) {
                      String displayName = 'Mesa';
                      
                      if (snapshot.hasData && snapshot.data!.exists) {
                        final data = snapshot.data!.data() as Map;
                        final name = data['name']?.toString().trim();
                        
                        if (name != null && name.isNotEmpty) {
                          displayName = name;
                        }
                      }
                      
                      return Text(
                        displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 4),
                  Text(
                    'Pedido #${orderId.substring(0, 8)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _statusColors[status] ?? Colors.grey,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_statusIcons[status], color: Colors.black, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      _statusLabels[status] ?? status,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Itens:',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          if (order['items'] is List)
            ...(order['items'] as List).map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${item['name']} (x${item['quantity']})',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              );
            }),
          const SizedBox(height: 12),
          Text(
            'Total: R\$ ${(order['totalPrice'] ?? 0).toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (order['notes'] != null && (order['notes'] as String).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Obs: ${order['notes']}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),

          // Botões de ação baseado no status
          if (status == 'pending' && !isMyOrder)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _rejectOrder(orderId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withValues(alpha: 0.3),
                      foregroundColor: Colors.red,
                    ),
                    child: const Text('RECUSAR'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _acceptOrder(orderId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.withValues(alpha: 0.3),
                      foregroundColor: Colors.green,
                    ),
                    child: const Text('ACEITAR'),
                  ),
                ),
              ],
            )
          else if (isMyOrder)
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.blue, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Você aceitou este pedido',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildStatusChangeButtons(orderId, status),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info, color: Colors.grey, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Outro garçom aceitou este pedido',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ==========================================
  // BOTÕES DE MUDANÇA DE STATUS
  // ==========================================

  Widget _buildStatusChangeButtons(String orderId, String currentStatus) {
    final nextStatuses = _getNextStatuses(currentStatus);

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.5,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: nextStatuses.map((nextStatus) {
        return ElevatedButton(
          onPressed: () => _updateOrderStatus(orderId, nextStatus),
          style: ElevatedButton.styleFrom(
            backgroundColor: _statusColors[nextStatus]?.withValues(alpha: 0.3),
            foregroundColor: _statusColors[nextStatus],
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_statusIcons[nextStatus], size: 16),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  _statusLabels[nextStatus] ?? nextStatus,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ==========================================
  // LÓGICA DE STATUS DISPONÍVEIS
  // ==========================================

  List<String> _getNextStatuses(String currentStatus) {
    switch (currentStatus) {
      case 'pending':
        return ['preparing', 'rejected'];
      case 'preparing':
        return ['ready', 'cancelled'];
      case 'ready':
        return ['on_the_way', 'cancelled'];
      case 'on_the_way':
        return ['delivered', 'cancelled'];
      case 'accepting':
        return ['preparing', 'rejected'];
      case 'delivered':
        return ['completed', 'cancelled'];
      default:
        return [];
    }
  }

  // ==========================================
  // AÇÕES DO PEDIDO
  // ==========================================

  // ✅ ACEITAR PEDIDO (2 ETAPAS: 1º adicionar garçom, 2º atualizar status)
Future<void> _acceptOrder(String orderId) async {
  try {
    final waiterId = _auth.currentUser?.uid;
    
    if (waiterId == null) {
      throw Exception('Garçom não autenticado');
    }

        // ✅ NOVO: Validar se garçom está realmente cadastrado no estabelecimento
    final waiterInDb = await _firestore
        .collection('establishments')
        .doc(_establishmentId)
        .collection('waiters')
        .doc(waiterId)
        .get();

    if (!waiterInDb.exists) {
      throw Exception('Você não está cadastrado neste estabelecimento');
    }

    final orderDoc = await _firestore.collection('orders').doc(orderId).get();
    final order = orderDoc.data() as Map<String, dynamic>;
    final customerId = order['customerId'] as String?;

    // ✅ ETAPA 1: Adicionar garçom ao pedido (assignedWaiter)
    // Isso permite que o garçom depois atualize o status
    await _firestore.collection('orders').doc(orderId).update({
      'assignedWaiter': waiterId,
      'status': 'accepting',
      'acceptedAt': FieldValue.serverTimestamp(),
    });

    // ✅ ETAPA 2: Enviar notificação ao cliente
    if (customerId != null) {
      await _notificationService.sendOrderStatusNotificationToClient(
        clientId: customerId,
        orderNumber: orderId.substring(0, 8),
        newStatus: 'preparing',
        tableNumber: order['tableId'] ?? 'NA',
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedido aceito! ✅'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    debugPrint('Erro ao aceitar pedido: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao aceitar: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}

// ✅ RECUSAR PEDIDO (2 ETAPAS: 1º adicionar garçom, 2º atualizar status para rejected)
Future<void> _rejectOrder(String orderId) async {
  try {
    final waiterId = _auth.currentUser?.uid;
    
    if (waiterId == null) {
      throw Exception('Garçom não autenticado');
    }

    final orderDoc = await _firestore.collection('orders').doc(orderId).get();
    final order = orderDoc.data() as Map<String, dynamic>;
    final customerId = order['customerId'] as String?;

    // ✅ ETAPA 1: Adicionar garçom ao pedido E mudar status para rejected
    // Isso permite que o garçom registre sua recusa
    await _firestore.collection('orders').doc(orderId).update({
      'assignedWaiter': waiterId,
      'status': 'rejected',
      'rejectedAt': FieldValue.serverTimestamp(),
      'rejectionReason': 'Garçom recusou',
    });

    // ✅ ETAPA 2: Enviar notificação ao cliente
    if (customerId != null) {
      await _notificationService.sendOrderStatusNotificationToClient(
        clientId: customerId,
        orderNumber: orderId.substring(0, 8),
        newStatus: 'rejected',
        tableNumber: order['tableId'] ?? 'NA',
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedido recusado ❌'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    debugPrint('Erro ao recusar pedido: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao recusar: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}

Future<void> _updateOrderStatus(String orderId, String newStatus) async {
  try {
    final waiterId = _auth.currentUser?.uid;
    
    if (waiterId == null) {
      throw Exception('Garçom não autenticado');
    }

    final orderDoc = await _firestore.collection('orders').doc(orderId).get();
    final order = orderDoc.data() as Map<String, dynamic>;
    final customerId = order['customerId'] as String?;
    final currentAssignedWaiter = order['assignedWaiter'] as String?;

    // ✅ VERIFICAÇÃO: Somente o garçom atribuído pode mudar status
    if (currentAssignedWaiter != waiterId) {
      throw Exception('Você não é o garçom responsável por este pedido');
    }

    // ✅ ATUALIZAR STATUS
    await _firestore.collection('orders').doc(orderId).update({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // ✅ ENVIAR NOTIFICAÇÃO AO CLIENTE
    if (customerId != null) {
      await _notificationService.sendOrderStatusNotificationToClient(
        clientId: customerId,
        orderNumber: orderId.substring(0, 8),
        newStatus: newStatus,
        tableNumber: order['tableId'] ?? 'NA',
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status atualizado: ${_statusLabels[newStatus]}'),
          backgroundColor: _statusColors[newStatus],
          duration: const Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    debugPrint('Erro ao atualizar status: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}

  // ==========================================
  // ABA: HISTÓRICO DE PEDIDOS
  // ==========================================

  Widget _buildHistoryTab() {
    if (_establishmentId == null) {
      return const Center(
        child: Text('Estabelecimento não conectado',
            style: TextStyle(color: Colors.white70)),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('orders')
          .where('establishmentId', isEqualTo: _establishmentId)
          .where('assignedWaiter', isEqualTo: _auth.currentUser?.uid)
          .where('status', whereIn: ['delivered', 'cancelled'])
          .orderBy('updatedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        final orders = snapshot.data!.docs;

        if (orders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history,
                  size: 80,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Nenhum pedido completo',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index].data() as Map<String, dynamic>;
            return _buildHistoryCard(order);
          },
        );
      },
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> order) {
    final status = order['status'] as String? ?? 'unknown';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
      color: const Color(0xFF001F3F),  // ← Azul marinho escuro
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white10.withValues(alpha: 0.5)),  // ← Opacidade baixa
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: _statusColors[status]?.withValues(alpha: 0.2) ??
                  Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _statusIcons[status] ?? Icons.check_circle,
              color: _statusColors[status] ?? Colors.green,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FutureBuilder(
                  future: _firestore
                      .collection('establishments')
                      .doc(_establishmentId)
                      .collection('tables')
                      .doc(order['tableId'] ?? '')
                      .get(),
                  builder: (context, snapshot) {
                    String displayName = 'Mesa';
                    
                    if (snapshot.hasData && snapshot.data!.exists) {
                      final data = snapshot.data!.data() as Map;
                      final name = data['name']?.toString().trim();
                      
                      if (name != null && name.isNotEmpty) {
                        displayName = name;
                      }
                    }
                    
                    return Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
                Text(
                  'R\$ ${(order['totalPrice'] ?? 0).toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColors[status]?.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _statusLabels[status] ?? status,
              style: TextStyle(
                color: _statusColors[status],
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // ABA: PERFIL
  // ==========================================

  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.1),
              border: Border.all(color: Colors.white30),
            ),
            child: const Icon(Icons.person, size: 50, color: Colors.black),
          ),
          const SizedBox(height: 16),
          Text(
            _waiterData?['name'] ?? 'Garçom',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _waiterData?['email'] ?? 'N/A',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black38),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Telefone',
                  style: TextStyle(color: Colors.black87, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  _waiterData?['phoneNumber'] ?? 'N/A',
                  style: const TextStyle(color: Colors.black),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () async {
              await _auth.signOut();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/welcome');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.withValues(alpha: 0.3),
              foregroundColor: Colors.red,
              minimumSize: const Size(double.infinity, 50),
            ),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
  }
}
