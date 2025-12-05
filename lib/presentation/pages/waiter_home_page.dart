// ignore_for_file: use_super_parameters, unused_import

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme_config.dart';

class WaiterHomePage extends StatefulWidget {
  const WaiterHomePage({Key? key}) : super(key: key);

  @override
  State<WaiterHomePage> createState() => _WaiterHomePageState();
}

class _WaiterHomePageState extends State<WaiterHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus Pedidos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () {
              // Logout
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Cards de status
          Row(
            children: [
              Expanded(
                child: _buildStatusCard(
                  'Pendentes',
                  '3',
                  Colors.orange,
                  Icons.pending_actions,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatusCard(
                  'Preparando',
                  '2',
                  Colors.blue,
                  Icons.restaurant_menu,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatusCard(
                  'Prontos',
                  '1',
                  Colors.green,
                  Icons.done,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Lista de pedidos
          const Text(
            'Pedidos Recentes',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          
          // Exemplo de item de pedido
          _buildOrderItem(
            orderId: 'ORD001',
            tableNumber: '5',
            items: 3,
            status: 'pending',
            createdTime: '10:30',
          ),
          _buildOrderItem(
            orderId: 'ORD002',
            tableNumber: '8',
            items: 2,
            status: 'preparing',
            createdTime: '10:20',
          ),
          _buildOrderItem(
            orderId: 'ORD003',
            tableNumber: '3',
            items: 4,
            status: 'ready',
            createdTime: '10:10',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Mostrar QR code do garçom
          _showWaiterQRCode(context);
        },
        child: const Icon(Icons.qr_code_2),
      ),
    );
  }

  Widget _buildStatusCard(
    String title,
    String count,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            count,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem({
    required String orderId,
    required String tableNumber,
    required int items,
    required String status,
    required String createdTime,
  }) {
    final statusColors = {
      'pending': Colors.orange,
      'preparing': Colors.blue,
      'ready': Colors.green,
    };

    final statusText = {
      'pending': 'Pendente',
      'preparing': 'Preparando',
      'ready': 'Pronto',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: statusColors[status]?.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  tableNumber,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: statusColors[status],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mesa $tableNumber',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$items itens • $createdTime',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: statusColors[status]?.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                statusText[status] ?? status,
                style: TextStyle(
                  color: statusColors[status],
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWaiterQRCode(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seu QR Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // QR code será gerado aqui
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text('QR CODE'),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Mostre este código ao proprietário para se registrar',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
          ElevatedButton(
            onPressed: () {
              // Compartilhar QR code
            },
            child: const Text('Compartilhar'),
          ),
        ],
      ),
    );
  }
}