// ignore_for_file: use_super_parameters, unnecessary_to_list_in_spreads, unused_import, deprecated_member_use, unnecessary_nullable_for_final_variable_declarations, unnecessary_null_comparison, unused_field

import 'dart:io';
import 'dart:typed_data';
import 'package:photo_manager/photo_manager.dart';  //
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/auth_service.dart';  // ← Adicione isso
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../config/theme_config.dart';
import '../../services/firebase_service.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; // Novo import// Novo import
import 'package:path_provider/path_provider.dart'; // Novo import
import 'package:csv/csv.dart';  // Para converter listas em CSV
import 'package:image/image.dart' as img_lib; // Novo import (from image package)

class OwnerHomePageImproved extends StatefulWidget {
  const OwnerHomePageImproved({Key? key}) : super(key: key);

  @override
  State<OwnerHomePageImproved> createState() => _OwnerHomePageImprovedState();
}

class _OwnerHomePageImprovedState extends State<OwnerHomePageImproved>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final _firebaseService = FirebaseService();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  late String _establishmentId;
  bool _isLoading = true;
  Map<String, dynamic>? _establishmentData;

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
    'accepting': 'Aceitando',
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
    'accepting': Colors.lightBlue,
    'preparing': Colors.blue,
    'ready': Colors.green,
    'on_the_way': Colors.purple,
    'delivered': Colors.teal,
    'completed': Colors.greenAccent,
    'cancelled': Colors.red,
    'rejected': Colors.red.shade900,
  };

  final Map<String, IconData> _statusIcons = {
    'pending': Icons.hourglass_bottom,
    'accepting': Icons.restaurant,
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
    _tabController = TabController(length: 5, vsync: this);
    _initializeData();
  }

Future<void> _initializeData() async {
  if (!mounted) return;

  setState(() => _isLoading = true);

  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _goToWelcome();
      return;
    }

    // Pega os dados do usuário dono
    final userData = await _firebaseService.getUserData(user.uid);

    // Verifica se tem establishmentId
    final String? estId = userData?['establishmentId'] as String?;

    if (estId == null || estId.isEmpty) {
      debugPrint('ERRO: establishmentId não encontrado no usuário ${user.uid}');
      debugPrint('Dados do usuário: $userData');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro: estabelecimento não configurado. Contate o suporte.'),
          backgroundColor: Colors.red,
        ),
      );
      _goToWelcome();
      return;
    }

    // Tudo certo → busca os dados do estabelecimento
    final estData = await _firebaseService.getEstablishmentData(estId);

    if (!mounted) return;

    setState(() {
      _establishmentId = estId;
      _establishmentData = estData;
      _isLoading = false;
    });
  } catch (e) {
    debugPrint('Erro ao carregar dados do estabelecimento: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
      _goToWelcome();
    }
  }
}

void _goToWelcome() {
  if (mounted) {
    Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);
  }
}

final _authService = AuthService();

  @override
  void dispose() {
    _tabController.dispose();
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _establishmentData?['name'] ?? 'Meu Restaurante',
          style: const TextStyle(color: Colors.black, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black),
            onPressed: () async {
              await _auth.signOut();

              if (!context.mounted) return;  
                Navigator.pushReplacementNamed(context, '/welcome');
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
              labelColor: Colors.black,  // ← Texto das abas preto
              unselectedLabelColor: Colors.black.withOpacity(0.6),
              indicatorColor: Colors.black,
              tabs: const [
                Tab(icon: Icon(Icons.table_restaurant, color: Colors.black), text: 'Mesas'),
                Tab(icon: Icon(Icons.receipt, color: Colors.black), text: 'Pedidos'),
                Tab(icon: Icon(Icons.people, color: Colors.black), text: 'Garçons'),
                Tab(icon: Icon(Icons.bar_chart, color: Colors.black), text: 'Estatísticas'),
                Tab(icon: Icon(Icons.person, color: Colors.black), text: 'Perfil'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTablesTab(),
                  _buildOrdersTab(),
                  _buildWaitersTab(),
                  _buildStatisticsTab(),
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
  // TAB: MESAS
  // ==========================================

  Widget _buildTablesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('establishments')
          .doc(_establishmentId)
          .collection('tables')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        final tables = snapshot.data!.docs;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              ElevatedButton.icon(
                onPressed: () => _showAddTableDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Nova Mesa'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0047AB),
                ),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: tables.length,
                itemBuilder: (context, index) {
                  final table = tables[index];
                  final tableData = table.data() as Map<String, dynamic>;

                  return _buildTableCard(table.id, tableData);
                },
              ),
            ],
          ),
        );
      },
    );
  }

//  Widget _buildTableCard(String tableId, Map<String, dynamic> tableData) {
 //   return GestureDetector(
//      onLongPress: () => _showTableOptionsMenu(tableId),
 //     child: Container(
 //       decoration: BoxDecoration(
  //        color: Colors.white.withValues(alpha: 0.1),
  //        borderRadius: BorderRadius.circular(12),
  //        border: Border.all(color: Colors.white30),
  //      ),
  //      child: Column(
  //        mainAxisAlignment: MainAxisAlignment.center,
  //        children: [
  //          IconButton(
   //           onPressed: () => _showQRCodeDialog(
   //             tableData['qrCode'] ?? '',
   //             tableData['name'] ?? 'Mesa',
   //           ),
    //          icon: const Icon(Icons.qr_code_2, size: 40, color: Colors.white),
    //        ),
    //        Text(
    //          tableData['name'] ?? 'Mesa',
    //          style: const TextStyle(
    //            color: Colors.white,
    //            fontWeight: FontWeight.bold,
    //            fontSize: 16,
    //          ),
    //        ),
    //        const SizedBox(height: 8),
    //        Text(
    //          '${tableData['capacity'] ?? 0} lugares',
    //          style: const TextStyle(color: Colors.white70, fontSize: 12),
    //        ),
    //      ],
    //    ),
    //  ),
  //  );
 // }

Widget _buildTableCard(String tableId, Map<String, dynamic> tableData) {
  final isOccupied = tableData['isOccupied'] ?? false;
  final currentCustomerId = tableData['currentCustomerId'];
  final tableName = tableData['name'] ?? 'Mesa Sem Nome';
  final capacity = tableData['capacity'] ?? 0;

  return GestureDetector(
    onLongPress: () => _showTableOptionsMenu(tableId),
    onTap: isOccupied && currentCustomerId != null
        ? () => _showOccupiedTableModal(tableId, tableName, currentCustomerId, tableData['occupiedAt'])
        : null,
    child: Container(
      decoration: BoxDecoration(
        color: isOccupied 
            ? Colors.red.withValues(alpha: 0.15) 
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOccupied ? Colors.red : Colors.white30,
          width: isOccupied ? 2 : 1,
        ),
      ),
      child: Stack(
        children: [
          // CONTEÚDO PRINCIPAL CENTRALIZADO (não afetado pelo ícone de detalhes)
        Center (
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => _showQRCodeDialog(
                    tableData['qrCode'] ?? '',
                    tableData['name'] ?? 'Mesa',
                  ),
                  icon: const Icon(Icons.qr_code_2, size: 40, color: Colors.black),
                ),
                const SizedBox(height: 8),
                Text(
                  tableName,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '$capacity lugares',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),

          // BADGE DE OCUPAÇÃO (CANTO SUPERIOR DIREITO)
          if (isOccupied)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.5),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'OCUPADA',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 9,
                  ),
                ),
              ),
            ),

          // ÍCONE DE DETALHES (CANTO INFERIOR DIREITO) - AGORA SOBREPOSTO SEM AFETAR O CENTRO
          Positioned(
            bottom: 6,
            right: 6,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(3),
              child: const Icon(
                Icons.priority_high,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}



  void _showAddTableDialog() {
    final nameController = TextEditingController();
    final capacityController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adicionar Mesa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nome da Mesa'),
            ),
            TextField(
              controller: capacityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Capacidade'),
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
              if (nameController.text.isNotEmpty &&
                  capacityController.text.isNotEmpty) {
                await _firebaseService.createTable(
                    establishmentId: _establishmentId,
                    name: nameController.text,
                    capacity: int.parse(capacityController.text),
                );
                if (!context.mounted) return; Navigator.pop(context);
              }
            },
            child: const Text('Criar'),
          ),
        ],
      ),
    );
  }

  void _showTableOptionsMenu(String tableId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1a1a1a),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Ver Histórico'),
              leading: const Icon(Icons.history),
              onTap: () {
                Navigator.pop(context);
                _showTableHistoryDialog(tableId);
              },
            ),
            ListTile(
              title: const Text('Remover Mesa', style: TextStyle(color: Colors.red)),
              leading: const Icon(Icons.delete, color: Colors.red),
              onTap: () async {
                Navigator.pop(context);
                await _firebaseService.deleteTable(_establishmentId, tableId);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTableHistoryDialog(String tableId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Histórico - Últimas 24h'),
        content: SizedBox(
          width: double.maxFinite,
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('orders')
                .where('tableId', isEqualTo: tableId)
                .where('createdAt',
                    isGreaterThan:
                        Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1))))
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final orders = snapshot.data!.docs;
              if (orders.isEmpty) {
                return const Center(child: Text('Nenhum pedido'));
              }

              return ListView.builder(
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final order = orders[index].data() as Map<String, dynamic>;
                  return ListTile(
                    title: Text(order['customerName'] ?? 'Cliente'),
                    subtitle: Text(order['items']?.join(', ') ?? 'Sem itens'),
                    trailing: Text(order['status'] ?? 'Pendente'),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

void _showQRCodeDialog(String qrData, String tableName) {
  showDialog(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a1a),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white30),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'QR Code - $tableName',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 280,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fechar', style: TextStyle(color: Colors.white70)),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    await _saveQRCodeToGallery(qrData, tableName);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Baixar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0047AB),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _saveQRCodeToGallery(String qrData, String tableName) async {
  try {
    // 1. Pede permissão
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (ps != PermissionState.authorized && ps != PermissionState.limited) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permissão negada para salvar na galeria'),
          backgroundColor: Colors.red),
      );
      return;
    }

    // 2. GERA A IMAGEM DO QR CODE DIRETO (NOVA FORMA 2025)
    final qrPainter = QrPainter(
      data: qrData,                          // ← OBRIGATÓRIO agora
      version: QrVersions.auto,
      color: const Color(0xFF000000),
      emptyColor: Colors.white,
      gapless: true,
      errorCorrectionLevel: QrErrorCorrectLevel.H,
    );

    // Converte para imagem 500x500
    final picData = await qrPainter.toImageData(500);
    final Uint8List qrBytes = picData!.buffer.asUint8List();

    // 3. Salva na galeria (API correta do photo_manager)
    final result = await PhotoManager.editor.saveImage(
      qrBytes,  // Primeiro parâmetro posicional: o buffer
      filename: 'QR_Mesa_${tableName.replaceAll(' ', '_')}.png', // OBRIGATÓRIO
      title: 'QR Code da mesa $tableName',                       // opcional
      desc: 'App Garçon',
      relativePath: 'Garçon/QR Codes', // cria pasta
    );

    if (result != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR Code salvo na galeria!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      throw Exception('Falha ao salvar imagem');
    }
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
    );
  }
}

// ==========================================
// CALCULAR TEMPO DE OCUPAÇÃO EM TEMPO REAL
// ==========================================

String _calculateOccupiedTime(dynamic occupiedAt) {
  if (occupiedAt == null) return '---';
  
  try {
    final occupiedDateTime = occupiedAt.toDate();
    final now = DateTime.now();
    final difference = now.difference(occupiedDateTime);

    final hours = difference.inHours;
    final minutes = difference.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  } catch (e) {
    return '---';
  }
}

// ==========================================
// DIALOG PARA DESOCUPAR MESA
// ==========================================

void _showDesoccupyTableDialog(String tableId, String tableName, String customerName) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Desocupar Mesa?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mesa: $tableName',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Cliente: $customerName',
            style: TextStyle(color: Colors.grey[700]),
          ),
          const SizedBox(height: 16),
          const Text(
            'Isso irá encerrar a sessão do cliente e liberar a mesa.',
            style: TextStyle(fontSize: 12, color: Colors.orange),
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
            Navigator.pop(context);
            await _desoccupyTable(tableId);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
          ),
          child: const Text('Desocupar'),
        ),
      ],
    ),
  );
}

// ==========================================
// DESOCUPAR MESA (Mesmo fluxo que cliente)
// ==========================================

Future<void> _desoccupyTable(String tableId) async {
  try {
    // 1️⃣ Encontrar a sessão ativa da mesa
    final sessionsQuery = await _firestore
        .collection('establishments')
        .doc(_establishmentId)
        .collection('sessions')
        .where('tableId', isEqualTo: tableId)
        .where('isActive', isEqualTo: true)
        .get();

    if (sessionsQuery.docs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma sessão ativa nesta mesa'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final sessionId = sessionsQuery.docs.first.id;

    // 2️⃣ Deletar a sessão
    await _firestore
        .collection('establishments')
        .doc(_establishmentId)
        .collection('sessions')
        .doc(sessionId)
        .delete();

    // 3️⃣ Liberar a mesa
    await _firestore
        .collection('establishments')
        .doc(_establishmentId)
        .collection('tables')
        .doc(tableId)
        .update({
          'isOccupied': false,
          'currentCustomerId': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mesa desocupada com sucesso! ✅'),
        backgroundColor: Colors.green,
      ),
    );
  } catch (e) {
    debugPrint('Erro ao desocupar mesa: $e');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erro ao desocupar mesa: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

void _showOccupiedTableModal(String tableId, String tableName, String customerId, dynamic occupiedAt) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => FutureBuilder<Map?>(
      future: _firebaseService.getUserData(customerId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final customerName = snapshot.data?['name'] ?? 'Cliente Desconhecido';
        final occupiedTime = _calculateOccupiedTime(occupiedAt);

        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tableName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red),
                        ),
                        child: const Text(
                          'OCUPADA',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // INFO: Cliente
              Row(
                children: [
                  const Icon(Icons.person, color: Colors.orange, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cliente',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          customerName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // INFO: Tempo de ocupação
              Row(
                children: [
                  const Icon(Icons.schedule, color: Colors.blue, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ocupada há',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          occupiedTime,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // BOTÃO DESOCUPAR
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showDesoccupyTableDialog(tableId, tableName, customerName);
                  },
                  icon: const Icon(Icons.check_circle, size: 20),
                  label: const Text('Desocupar Mesa'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}



  // ==========================================
  // TAB: PEDIDOS
  // ==========================================

Widget _buildOrdersTab() {
  return StreamBuilder<QuerySnapshot>(
    stream: _firestore
        .collection('orders')
        .where('establishmentId', isEqualTo: _establishmentId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots(),
    builder: (context, snapshot) {
      // 1. ERRO DE CONEXÃO OU COLEÇÃO INEXISTENTE
      if (snapshot.hasError) {
        // Verifica se é erro de coleção não encontrada (mais comum no início)
        final error = snapshot.error.toString();
        if (error.contains('not-found') || error.contains('Collection') || error.contains('orders')) {
          return _buildEmptyState(
            icon: Icons.receipt_long_outlined,
            title: "Nenhum pedido ainda",
            subtitle: "Quando os clientes fizerem pedidos,\nele aparecerão aqui em tempo real",
          );
        }

        // Qualquer outro erro (sem internet, permissão, etc)
        return _buildErrorState(error);
      }

      // 2. AINDA CARREGANDO (primeira vez)
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }

      // 3. DADOS CARREGADOS, MAS VAZIOS (coleção existe, mas sem documentos)
      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
        return _buildEmptyState(
          icon: Icons.receipt_long_outlined,
          title: "Nenhum pedido recente",
          subtitle: "Os pedidos dos clientes aparecerão aqui automaticamente",
        );
      }

      // 4. TEM PEDIDOS → LISTA NORMAL
      final orders = snapshot.data!.docs;

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

// ===============================================
// WIDGETS AUXILIARES (BONITOS E REUTILIZÁVEIS)
// ===============================================

Widget _buildEmptyState({
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 80, color: Colors.white.withOpacity(0.3)),
        const SizedBox(height: 24),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            color: Colors.white70,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white60, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

Widget _buildErrorState(String error) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.wifi_off, color: Colors.red, size: 60),
        const SizedBox(height: 16),
        const Text(
          "Falha ao carregar pedidos",
          style: TextStyle(color: Colors.white70, fontSize: 18),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            "Verifique sua conexão com a internet e tente novamente.",
            style: TextStyle(color: Colors.white60, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => setState(() {}), // Força rebuild do StreamBuilder
          icon: const Icon(Icons.refresh),
          label: const Text("Tentar novamente"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF0047AB),
          ),
        ),
      ],
    ),
  );
}

Widget _buildOrderCard(Map<String, dynamic> order, String orderId) {
  final status = order['status'] ?? 'pending';
  // ignore: unused_local_variable
  final String statusLabel = _statusLabels[status] ?? status.toUpperCase();
  // Cor do status (com fallback para cinza se desconhecido)
  final Color statusColor = _statusColors[status] ?? Colors.grey;

  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF001F3F),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              order['customerName'] ?? 'Cliente',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: statusColor),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildTableNameWidget(order['tableId'] ?? ''),
        const SizedBox(height: 8),
        Text('Itens: ${(order['items'] as List?)?.join(', ') ?? 'Nenhum'}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 12),
        DropdownButton<String>(
          value: status,
          isExpanded: true,
          dropdownColor: const Color(0xFF1a1a1a),
          underline: const SizedBox(), //
          style: const TextStyle(color: Colors.white),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
          items: _orderStatuses.map((String value) {
            return DropdownMenuItem<String>(
              value: value,  // ← CORRETO: mantém 'pending', 'preparing', etc. (em inglês, para o Firestore)
              child: Text(
                _statusLabels[value] ?? value.toUpperCase(),
                style: const TextStyle(color: Colors.white),
              ),
            );
          }).toList(),
          onChanged: (newStatus) {
            if (newStatus != null && newStatus != status) {
              _updateOrderStatus(orderId, newStatus);
            }
          },
        ),
      ],
    ),
  );
}

Future<void> _updateOrderStatus(String orderId, String newStatus) async {
  try {
    await _firestore.collection('orders').doc(orderId).update({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status alterado para: ${_statusLabels[newStatus]}'),
          backgroundColor: _statusColors[newStatus],
          duration: const Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Erro ao atualizar status'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/// Função que retorna o nome bonito da mesa a partir do tableId
Widget _buildTableNameWidget(String tableId) {
  if (tableId.isEmpty) {
    return const Text(
      'Mesa: Desconhecida',
      style: TextStyle(color: Colors.white70, fontSize: 12),
    );
  }

  return FutureBuilder(
    future: _firestore
        .collection('establishments')
        .doc(_establishmentId)
        .collection('tables')
        .doc(tableId)
        .get(),
    builder: (context, snapshot) {
      String displayName = 'Mesa';

      if (snapshot.hasData && snapshot.data!.exists) {
        final data = snapshot.data!.data() as Map;
        final name = data['name']?.toString().trim();

        if (name != null && name.isNotEmpty && name.toLowerCase() != 'null') {
          displayName = name;
        } else {
          // Extrai número do ID (ex: table_abc123 → 123)
          final match = RegExp(r'\d+').firstMatch(tableId);
          displayName = match != null ? 'Mesa ${match.group(0)}' : 'Mesa';
        }
      } else {
        // Fallback se a mesa foi deletada
        final match = RegExp(r'\d+').firstMatch(tableId);
        displayName = match != null ? 'Mesa ${match.group(0)}' : 'Mesa';
      }

      return Text(
        'Mesa: $displayName',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      );
    },
  );
}


  // ==========================================
  // TAB: GARÇONS
  // ==========================================

  Widget _buildWaitersTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('establishments')
          .doc(_establishmentId)
          .collection('waiters')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        final waiters = snapshot.data!.docs;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              ElevatedButton.icon(
                onPressed: () => _showScanWaiterQRDialog(),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Escanear QR Garçom'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0047AB),
                ),
              ),
              const SizedBox(height: 16),
              ...waiters.map((waiter) {
                final waiterData = waiter.data() as Map<String, dynamic>;
                return _buildWaiterCard(waiter.id, waiterData);
              }).toList(),
            ],
          ),
        );
      },
    );
  }

Widget _buildWaiterCard(String waiterId, Map waiterData) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF001F3F),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white30),
    ),
    child: StreamBuilder(
      // ✅ Busca pedidos do garçom em tempo real
      stream: _firestore
          .collection('orders')
          .where('establishmentId', isEqualTo: _establishmentId)
          .where('assignedWaiter', isEqualTo: waiterId)
          .snapshots(),
      builder: (context, snapshot) {
        final orders = snapshot.data?.docs ?? [];
        final totalOrders = orders.length;
        final deliveredOrders = orders
            .where((doc) => doc['status'] == 'delivered')
            .length;
        final inProgressOrders = orders
            .where((doc) => ['pending', 'preparing', 'ready', 'on_the_way'].contains(doc['status']))
            .length;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ Nome do garçom
                  Text(
                    waiterData['name'] ?? 'Garçom',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // ✅ Telefone
                  Text(
                    waiterData['phone'] ?? 'Sem telefone',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  // ✅ NOVO: Estatísticas em tempo real
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Linha 1: Total de pedidos
                        Row(
                          children: [
                            const Icon(Icons.shopping_bag, color: Colors.orange, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'Pedidos: $totalOrders',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Linha 2: Entregues + Em progresso
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle, color: Colors.green, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Entregues: $deliveredOrders',
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.schedule, color: Colors.blue, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Em andamento: $inProgressOrders',
                                    style: const TextStyle(
                                      color: Colors.lightBlue,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ✅ Botão de remover
            IconButton(
              onPressed: () => _removeWaiter(waiterId),
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: 'Remover garçom',
            ),
          ],
        );
      },
    ),
  );
}


void _showScanWaiterQRDialog() {
  final controller = MobileScannerController();
  bool hasScanned = false; // ✅ Flag para evitar múltiplos scans
  
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => WillPopScope(
      onWillPop: () async {
        controller.dispose();
        Navigator.pop(dialogContext);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Escanear QR do Garçom'),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              controller.dispose();
              Navigator.pop(dialogContext);
            },
          ),
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
                  
                  // ✅ PARAR câmera imediatamente
                  await controller.stop();
                  
                  debugPrint('DEBUG: QR code detectado: ${barcode.rawValue}');
                  
                  // ✅ Processar QR
                  await _addWaiterFromQR(barcode.rawValue!);
                  
                  // ✅ Aguarde um pouco para garantir finalização
                  await Future.delayed(const Duration(milliseconds: 500));
                  
                  if (!dialogContext.mounted) return;
                  
                  // ✅ Fechar diálogo
                  controller.dispose();
                  Navigator.pop(dialogContext);
                  
                } catch (e) {
                  debugPrint('Erro ao processar QR: $e');
                  hasScanned = false;
                  
                  await controller.stop();
                  
                  if (!dialogContext.mounted) return;

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
                      'Posicione o QR code do garçom no centro da tela',
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
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.amber.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.amber,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Certifique-se de que a câmera\nestá bem focada',
                              style: TextStyle(
                                color: Colors.amber,
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
              top: 50,
              left: 30,
              right: 30,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withOpacity(0.6),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ).then((_) {
    // ✅ Garantir disposal ao fechar
    try {
      if (controller.value.hasCameraPermission) {
        controller.dispose();
      }
    } catch (e) {
      debugPrint('Erro ao desposar controller: $e');
    }
  });
}

// Função auxiliar para adicionar garçom do QR
Future<void> _addWaiterFromQR(dynamic qrData) async {
  try {
    // ✅ CORRIGIDO 1: Converter qrData para String de forma segura
    String qrString;
    
    if (qrData is String) {
      qrString = qrData;
    } else if (qrData is List<int>) {
      qrString = String.fromCharCodes(qrData);
    } else {
      qrString = qrData.toString();
    }
    
    debugPrint('DEBUG: QR String bruta recebida: $qrString');
    
    // ✅ Agora trabalhamos diretamente com a string completa
    if (!qrString.startsWith('waiter:')) {
      debugPrint('DEBUG: QR não começa com "waiter:" → inválido');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR Code inválido: deve começar com "waiter:"'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Remove o prefixo "waiter:" e tudo depois do primeiro "|" (se existir)
    String tempId = qrString.substring('waiter:'.length); // Remove "waiter:"
    final pipeIndex = tempId.indexOf('|');
    final waiterId = pipeIndex != -1 
        ? tempId.substring(0, pipeIndex).trim() 
        : tempId.trim();

    debugPrint('DEBUG: waiterId extraído com sucesso: $waiterId');

    if (waiterId.isEmpty) {
      debugPrint('DEBUG: ID do garçom está vazio após parsing');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ID do garçom não encontrado no QR Code'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Busca os dados do usuário no Firestore
    debugPrint('DEBUG: Buscando dados do usuário com ID: $waiterId');
    final userData = await _authService.getUserData(waiterId);
    
    debugPrint('DEBUG: userData obtido: $userData');

    if (userData == null || userData['role'] != 'garcom') {
      debugPrint('DEBUG: Usuário não existe ou não é garçom');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR inválido ou usuário não é um garçom'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // ✅ Adiciona o garçom ao estabelecimento (usando função correta)
    debugPrint('DEBUG: Adicionando garçom $waiterId ao estabelecimento $_establishmentId');
    await _firebaseService.addWaiter(
      establishmentId: _establishmentId,
      waiterId: waiterId,
    );

    debugPrint('DEBUG: Garçom adicionado com sucesso!');


    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Garçom adicionado com sucesso!'),
        backgroundColor: Colors.green,
      ),
    );
    
  } catch (e, stackTrace) {
    debugPrint('DEBUG: Erro ao adicionar garçom: $e');
    debugPrint('StackTrace: $stackTrace');
    
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erro ao adicionar garçom: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}



  Future<void> _removeWaiter(String waiterId) async {
    await _firestore
        .collection('establishments')
        .doc(_establishmentId)
        .collection('waiters')
        .doc(waiterId)
        .delete();
  }

// ==========================================
// TAB: ESTATÍSTICAS
// ==========================================

Widget _buildStatisticsTab() {
  return FutureBuilder<Map<String, dynamic>>(  // ✅ Tipo correto
    future: _getStatistics(),
    builder: (context, snapshot) {
      // 1. CARREGANDO
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }

      // 2. ERRO
      if (snapshot.hasError) {
        debugPrint('Erro em estatísticas: ${snapshot.error}');
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 60),
              const SizedBox(height: 16),
              Text(
                'Erro ao carregar estatísticas',
                style: const TextStyle(color: Colors.black87, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                snapshot.error.toString(),
                style: const TextStyle(color: Colors.black54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }

      // 3. SEM DADOS
      if (!snapshot.hasData || snapshot.data == null || snapshot.data!.isEmpty) {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bar_chart, color: Colors.black38, size: 80),
              SizedBox(height: 16),
              Text(
                'Nenhuma estatística disponível',
                style: TextStyle(color: Colors.black87, fontSize: 16),
              ),
            ],
          ),
        );
      }

      // 4. TEM DADOS → MOSTRA
      final stats = snapshot.data!;

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildStatCard(
              'Clientes Únicos (30 dias)',
              '${stats['totalClients'] ?? 0}',
              Icons.people,
            ),
            _buildStatCard(
              'Garçons',
              '${stats['totalWaiters'] ?? 0}',
              Icons.person,
            ),
            _buildStatCard(
              'Pedidos (7 dias)',
              '${stats['ordersLast7Days'] ?? 0}',
              Icons.receipt,
            ),
            _buildStatCard(
              'Tempo Médio de Pedido',
              '${stats['averageOrderTime']?.toStringAsFixed(0) ?? '0'} min',
              Icons.timer,
            ),

            _buildStatCard(
              'Média por Pedido',
              'R\$ ${stats['averageOrderValue']?.toStringAsFixed(2) ?? '0.00'}',
              Icons.bar_chart,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _downloadReport('clients'),
              icon: const Icon(Icons.download),
              label: const Text('Baixar Relatório - Clientes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.2),
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _downloadReport('waiters'),
              icon: const Icon(Icons.download),
              label: const Text('Baixar Relatório - Garçons'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.2),
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _showDownloadReportDialog(),
              icon: const Icon(Icons.download),
              label: const Text('Baixar Relatório - Pedidos'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.2),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    },
  );
}


  Widget _buildStatCard(String title, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF001F3F),  // ← Azul marinho
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white30),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Icon(icon, size: 40, color: Colors.lightBlueAccent.withValues(alpha: 0.3)),
        ],
      ),
    );
  }

// ✅ FUNÇÃO CORRIGIDA
Future<Map<String, dynamic>> _getStatistics() async {
  try {
    debugPrint('DEBUG: Carregando estatísticas para $_establishmentId');

    // Total de garçons (de waiters subcollection)
    final waitersSnap = await _firestore
        .collection('establishments')
        .doc(_establishmentId)
        .collection('waiters')
        .get();

    debugPrint('DEBUG: Garçons encontrados: ${waitersSnap.docs.length}');

    // Pedidos nos últimos 7 dias
    final ordersSnap = await _firestore
        .collection('orders')
        .where('establishmentId', isEqualTo: _establishmentId)
        .where(
          'createdAt',
          isGreaterThan: Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 7)),
          ),
        )
        .get();

    debugPrint('DEBUG: Pedidos (7 dias) encontrados: ${ordersSnap.docs.length}');

    // Clientes únicos (de sessions nos últimos 30 dias, unique customerIds)
    final sessionsSnap = await _firestore
        .collection('establishments')
        .doc(_establishmentId)
        .collection('sessions')
        .where(
          'startTime',
          isGreaterThan: Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 30)),
          ),
        )
        .get();

    final uniqueClientsSet = <String>{};
    for (var doc in sessionsSnap.docs) {
      final customerId = doc['customerId'] as String?;
      if (customerId != null && customerId.isNotEmpty) {
        uniqueClientsSet.add(customerId);
      }
    }

    debugPrint('DEBUG: Clientes únicos (30 dias): ${uniqueClientsSet.length}');

    // Calcular revenue, average e tempo médio
      double revenue = 0.0;
      double totalTime = 0.0;
      int completedOrders = 0;

      for (var doc in ordersSnap.docs) {
        // Revenue
        final totalPrice = doc['totalPrice'];
        if (totalPrice != null) {
          revenue += (totalPrice as num).toDouble();
        }

        // Tempo médio
        final createdAt = doc['createdAt'] as Timestamp?;
        final completedAt = doc['completedAt'] as Timestamp?;

        if (createdAt != null && completedAt != null) {
          final timeInSeconds = completedAt.toDate().difference(createdAt.toDate()).inSeconds;
          totalTime += timeInSeconds;
          completedOrders++;
        }
      }

      final avgOrderValue = ordersSnap.docs.isNotEmpty
          ? revenue / ordersSnap.docs.length
          : 0.0;

      final avgOrderTime = completedOrders > 0 ? totalTime / completedOrders / 60 : 0.0;

      debugPrint('DEBUG: Receita (7 dias): $revenue');
      debugPrint('DEBUG: Média por pedido: $avgOrderValue');
      debugPrint('DEBUG: Tempo médio: $avgOrderTime minutos');

      return {
        'totalClients': uniqueClientsSet.length,
        'totalWaiters': waitersSnap.docs.length,
        'ordersLast7Days': ordersSnap.docs.length,
        'revenueLast7Days': revenue,
        'averageOrderValue': avgOrderValue,
        'averageOrderTime': avgOrderTime,
      };
  } catch (e) {
    debugPrint('❌ ERRO em _getStatistics(): $e');
    rethrow; // ✅ Joga o erro para o FutureBuilder capturar e mostrar
  }
}


  void _showDownloadReportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selecione o período'),
        content: const Text('Escolha quantos dias deseja incluir no relatório'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _downloadReport('orders_7');
            },
            child: const Text('Últimos 7 dias'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _downloadReport('orders_15');
            },
            child: const Text('Últimos 15 dias'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _downloadReport('orders_30');
            },
            child: const Text('Últimos 30 dias'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB: PERFIL
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
              color: Colors.black.withValues(alpha: 0.1),
            ),
            child: const Icon(Icons.store, size: 50, color: Colors.black),
          ),
          const SizedBox(height: 16),
          Text(
            _establishmentData?['name'] ?? 'Meu Restaurante',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          _buildEditableField('Nome da Loja', 'name'),
          _buildEditableField('E-mail', 'email'),
          _buildEditableField('Endereço', 'address'),
          _buildEditableField('Telefone', 'phone'),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () async {
              await _auth.signOut();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/welcome');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE74C3C).withValues(alpha: 0.3),
              foregroundColor: const Color(0xFFE74C3C),
            ),
            child: const Text('Sair da Conta'),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField(String label, String key) {
    final controller = TextEditingController(
      text: _establishmentData?[key]?.toString() ?? '',
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF001F3F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.white60),
                  ),
                ),
              ),
              IconButton(
                onPressed: () async {
                  await _firebaseService.updateEstablishmentData(
                    _establishmentId,
                    {key: controller.text},
                  );
                  _initializeData();
                },
                icon: const Icon(Icons.check, color: Colors.green),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _downloadReport(String reportType) async {
  try {
    List<List<dynamic>> data;
    String filename;

    switch (reportType) {
      case 'clients':
        data = await _getClientsReportData();
        filename = 'relatorio_clientes';
        break;
      case 'waiters':
        data = await _getWaitersReportData();
        filename = 'relatorio_garcons';
        break;
      case 'orders_7':
        data = await _getOrdersReportData(7);
        filename = 'relatorio_pedidos_7dias';
        break;
      case 'orders_15':
        data = await _getOrdersReportData(15);
        filename = 'relatorio_pedidos_15dias';
        break;
      case 'orders_30':
        data = await _getOrdersReportData(30);
        filename = 'relatorio_pedidos_30dias';
        break;
      default:
        return;
    }

    await _saveCsvToDownloads(data, filename);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Relatório baixado com sucesso!')));
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao baixar: $e'), backgroundColor: Colors.red));
  }
}

Future<List<List<dynamic>>> _getClientsReportData() async {
  final sessions = await _firebaseService.getClientOrderHistory('', _establishmentId);  // Reusa para sessions ou ajusta para unique clients
  Set<String> uniqueClients = {};
  for (var session in sessions) {
    uniqueClients.add(session['customerId'] as String);
  }
  List<List<dynamic>> data = [['ID', 'Nome', 'Última Visita']];
  for (var clientId in uniqueClients) {
    final user = await _firebaseService.getUserData(clientId);
    data.add([clientId, user?['name'] ?? 'Anônimo', user?['lastVisit'] ?? 'N/A']);
  }
  return data;
}

Future<List<List<dynamic>>> _getWaitersReportData() async {
  final waiters = await _firebaseService.getWaiters(_establishmentId);
  List<List<dynamic>> data = [['ID', 'Nome', 'Telefone', 'Rating']];
  for (var waiter in waiters) {
    data.add([waiter['id'], waiter['name'], waiter['phone'], waiter['averageRating'] ?? 'N/A']);
  }
  return data;
}

Future<List<List<dynamic>>> _getOrdersReportData(int days) async {
  final orders = await _firestore
      .collection('orders')
      .where('establishmentId', isEqualTo: _establishmentId)
      .where('createdAt', isGreaterThan: Timestamp.fromDate(DateTime.now().subtract(Duration(days: days))))
      .get();
  List<List<dynamic>> data = [['ID', 'Mesa', 'Status', 'Data', 'Total']];
  for (var doc in orders.docs) {
    final order = doc.data();
    data.add([
      doc.id,
      order['tableId'],
      order['status'],
      (order['createdAt'] as Timestamp?)?.toDate().toString() ?? 'N/A',
      order['totalPrice'] ?? 0,
    ]);
  }
  return data;
}

Future _saveCsvToDownloads(List<List<dynamic>> data, String filename) async {
  try {
    const converter = ListToCsvConverter();
    final csvString = converter.convert(data);

    // ✅ OPÇÃO 1: Usar diretório de documentos do app (mais confiável)
    final directory = await getApplicationDocumentsDirectory();
    if (directory == null) {
      throw Exception('Não foi possível acessar o armazenamento do app');
    }

    // ✅ Cria pasta Garçon/Relatórios se não existir
    final relatoriosDir = Directory('${directory.path}/Garcon/Relatorios');
    await relatoriosDir.create(recursive: true);

    // ✅ Salva o arquivo com timestamp para evitar duplicatas
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${relatoriosDir.path}/${filename}_$timestamp.csv');
    await file.writeAsString(csvString);

    debugPrint('✅ Relatório salvo em: ${file.path}');

    if (!mounted) return;

    // ✅ Mostra snackbar com sucesso e caminho do arquivo
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '✅ Relatório salvo com sucesso!',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Pasta: Garcon/Relatorios',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            Text(
              'Arquivo: ${filename}_$timestamp.csv',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {},
        ),
      ),
    );
  } catch (e) {
    debugPrint('❌ Erro ao salvar relatório: $e');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erro ao salvar: ${e.toString().split(':').first}'),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

}


