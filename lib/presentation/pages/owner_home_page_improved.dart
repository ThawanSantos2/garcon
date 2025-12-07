// ignore_for_file: use_super_parameters, unnecessary_to_list_in_spreads, unused_import, deprecated_member_use, unnecessary_nullable_for_final_variable_declarations

import 'dart:io';
import 'package:photo_manager/photo_manager.dart';  //
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';  // ← Adicione isso
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../config/theme_config.dart';
import '../../services/firebase_service.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; // Novo import// Novo import
import 'package:path_provider/path_provider.dart'; // Novo import
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
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
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
              tabs: const [
                Tab(icon: Icon(Icons.table_restaurant), text: 'Mesas'),
                Tab(icon: Icon(Icons.receipt), text: 'Pedidos'),
                Tab(icon: Icon(Icons.people), text: 'Garçons'),
                Tab(icon: Icon(Icons.bar_chart), text: 'Estatísticas'),
                Tab(icon: Icon(Icons.person), text: 'Perfil'),
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

  Widget _buildTableCard(String tableId, Map<String, dynamic> tableData) {
    return GestureDetector(
      onLongPress: () => _showTableOptionsMenu(tableId),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white30),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () => _showQRCodeDialog(
                tableData['qrCode'] ?? '',
                tableData['name'] ?? 'Mesa',
              ),
              icon: const Icon(Icons.qr_code_2, size: 40, color: Colors.white),
            ),
            Text(
              tableData['name'] ?? 'Mesa',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${tableData['capacity'] ?? 0} lugares',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
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
    // 1. Pede permissão para salvar na galeria
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (ps != PermissionState.authorized && ps != PermissionState.limited) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permissão para salvar imagens negada. Vá em Configurações > Apps > Garçon > Permissões.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 2. Gera a imagem do QR Code como Uint8List
    final qrValidationResult = QrValidator.validate(qrData);
    final qrCode = qrValidationResult.qrCode!;
    final painter = QrPainter.withQr(
      qr: qrCode,
      // Nota: 'color' e 'emptyColor' são depreciados - use eyeStyle/dataModuleStyle se precisar customizar
      color: const Color(0xFF000000),
      emptyColor: Colors.white,
      gapless: true,
    );

    final picData = await painter.toImageData(500);  // 500x500 pixels
    final buffer = picData!.buffer.asUint8List();  // Uint8List pronto

    // 3. Salva na galeria com nome bonito
    final AssetEntity? entity = await PhotoManager.editor.saveImage(
      data: buffer,                // ← obrigatório
      filename: 'QR_$tableName.png', // ← obrigatório
      title: 'QR Code Mesa $tableName',
      desc: 'QR Code da mesa $tableName - Garçon App',
    );


    if (entity != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR Code salvo na galeria!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      throw Exception('Falha ao salvar - verifique as permissões');
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erro ao salvar: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
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
        .limit(50) // Limite para performance
        .snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 60),
              const SizedBox(height: 16),
              const Text(
                'Erro ao carregar pedidos',
                style: TextStyle(color: Colors.white70),
              ),
              Text(
                snapshot.error.toString(),
                style: const TextStyle(color: Colors.red, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }

      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator(color: Colors.white));
      }

      final orders = snapshot.data!.docs;

      if (orders.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long_outlined, size: 80, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(height: 24),
              const Text(
                'Nenhum pedido ainda',
                style: TextStyle(fontSize: 20, color: Colors.white70, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Quando clientes fizerem pedidos,\neles aparecerão aqui em tempo real',
                style: TextStyle(color: Colors.white60, fontSize: 14),
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
          return _buildOrderCard(order, orders[index].id);
        },
      );
    },
  );
}

  Widget _buildOrderCard(Map<String, dynamic> order, String orderId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                order['customerName'] ?? 'Cliente',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(order['status']).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _getStatusColor(order['status']),
                  ),
                ),
                child: Text(
                  order['status'] ?? 'Pendente',
                  style: TextStyle(
                    color: _getStatusColor(order['status']),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Mesa: ${order['tableNumber'] ?? 'N/A'}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            'Itens: ${(order['items'] as List?)?.join(', ') ?? 'Nenhum'}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (order['status'] != 'completed')
                ElevatedButton(
                  onPressed: () => _updateOrderStatus(orderId, 'preparing'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.withValues(alpha: 0.3),
                    foregroundColor: Colors.orange,
                  ),
                  child: const Text('Em Preparo'),
                ),
              if (order['status'] == 'preparing')
                ElevatedButton(
                  onPressed: () => _updateOrderStatus(orderId, 'ready'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.withValues(alpha: 0.3),
                    foregroundColor: Colors.green,
                  ),
                  child: const Text('Pronto'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _updateOrderStatus(String orderId, String status) async {
    await _firestore.collection('orders').doc(orderId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'pending':
        return Colors.blue;
      case 'preparing':
        return Colors.orange;
      case 'ready':
        return Colors.green;
      case 'completed':
        return Colors.grey;
      default:
        return Colors.white;
    }
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

  Widget _buildWaiterCard(String waiterId, Map<String, dynamic> waiterData) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
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
                waiterData['name'] ?? 'Garçom',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                waiterData['phone'] ?? 'Sem telefone',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          IconButton(
            onPressed: () => _removeWaiter(waiterId),
            icon: const Icon(Icons.delete, color: Colors.red),
          ),
        ],
      ),
    );
  }

  void _showScanWaiterQRDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Escanear QR Garçom')),
          body: MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  _addWaiterFromQR(barcode.rawValue!);
                  Navigator.pop(context);
                  break;
                }
              }
            },
          ),
        ),
      ),
    );
  }

  // Função auxiliar para adicionar garçom do QR (assumindo que QR tem ID do garçom)
Future<void> _addWaiterFromQR(String qrData) async {
  try {
    // qrData deve ser o userId do garçom (ex: do QR Code gerado para ele)
    final userData = await _authService.getUserData(qrData);
    if (userData == null || userData['role'] != 'garcom') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR inválido ou não é um garçom')),
      );
      return;
    }

    // Adiciona o garçom ao estabelecimento
    await _firestore
        .collection('establishments')
        .doc(_establishmentId)
        .collection('waiters')
        .doc(qrData)  // Usa o userId como ID
        .set({
          'name': userData['name'],
          'phone': userData['phoneNumber'],
          'email': userData['email'],
          'addedAt': FieldValue.serverTimestamp(),
        });
      if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Garçom adicionado com sucesso!'), backgroundColor: Colors.green),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Erro ao adicionar garçom: $e'), backgroundColor: Colors.red),
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
    return FutureBuilder<Map<String, dynamic>>(
      future: _getStatistics(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        final stats = snapshot.data!;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildStatCard(
                'Clientes',
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
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _downloadReport('clients'),
                icon: const Icon(Icons.download),
                label: const Text('Baixar Relatório - Clientes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _downloadReport('waiters'),
                icon: const Icon(Icons.download),
                label: const Text('Baixar Relatório - Garçons'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _showDownloadReportDialog(),
                icon: const Icon(Icons.download),
                label: const Text('Baixar Relatório - Pedidos'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
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
        color: Colors.white.withValues(alpha: 0.1),
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
          Icon(icon, size: 40, color: Colors.white.withValues(alpha: 0.3)),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _getStatistics() async {
    try {
      // Total de clientes
      final clientsSnap = await _firestore
          .collection('establishments')
          .doc(_establishmentId)
          .collection('clients')
          .get();

      // Total de garçons
      final waitersSnap = await _firestore
          .collection('establishments')
          .doc(_establishmentId)
          .collection('waiters')
          .get();

      // Pedidos nos últimos 7 dias
      final ordersSnap = await _firestore
          .collection('orders')
          .where('establishmentId', isEqualTo: _establishmentId)
          .where('createdAt',
              isGreaterThan: Timestamp.fromDate(
                  DateTime.now().subtract(const Duration(days: 7))))
          .get();

      return {
        'totalClients': clientsSnap.docs.length,
        'totalWaiters': waitersSnap.docs.length,
        'ordersLast7Days': ordersSnap.docs.length,
      };
    } catch (e) {
      return {
        'totalClients': 0,
        'totalWaiters': 0,
        'ordersLast7Days': 0,
      };
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

  Future<void> _downloadReport(String reportType) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Baixando relatório: $reportType')),
    );
    //Implementar download de PDF
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
              color: Colors.white.withValues(alpha: 0.1),
            ),
            child: const Icon(Icons.store, size: 50, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(
            _establishmentData?['name'] ?? 'Meu Restaurante',
            style: const TextStyle(
              color: Colors.white,
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
        color: Colors.white.withValues(alpha: 0.1),
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
}
