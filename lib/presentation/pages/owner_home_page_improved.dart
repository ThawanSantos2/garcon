// ignore_for_file: use_super_parameters, unnecessary_to_list_in_spreads

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../config/theme_config.dart';
import '../../services/firebase_service.dart';

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
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      // Obter dados do estabelecimento
      final userData = await _firebaseService.getUserData(userId);
      if (userData != null && userData['establishmentId'] != null) {
        setState(() => _establishmentId = userData['establishmentId']);
        final estData =
            await _firebaseService.getEstablishmentData(_establishmentId);
        setState(() {
          _establishmentData = estData;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

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
      builder: (context) => AlertDialog(
        title: Text('QR Code - $tableName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 250,
              backgroundColor: Colors.white,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              // Download de imagem
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('QR Code salvo na galeria')),
              );
            },
            icon: const Icon(Icons.download),
            label: const Text('Baixar'),
          ),
        ],
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
          .where('createdAt',
              isGreaterThan: Timestamp.fromDate(
                  DateTime.now().subtract(const Duration(hours: 5))))
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

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
    //Implementar scanner de QR
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scanner de QR em desenvolvimento')),
    );
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
