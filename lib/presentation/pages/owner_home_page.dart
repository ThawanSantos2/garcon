// owner_home_page.dart
// ignore_for_file: use_super_parameters, prefer_const_constructors, prefer_const_literals_to_create_immutables, unused_element

import 'package:flutter/material.dart';

class OwnerHomePage extends StatefulWidget {
  const OwnerHomePage({Key? key}) : super(key: key);

  @override
  State<OwnerHomePage> createState() => _OwnerHomePageState();
}

class _OwnerHomePageState extends State<OwnerHomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Mesas', icon: Icon(Icons.table_restaurant)),
            Tab(text: 'Garçons', icon: Icon(Icons.people)),
            Tab(text: 'Estatísticas', icon: Icon(Icons.bar_chart)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTabMesas(),
          _buildTabWaiters(),
          _buildTabStats(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_tabController.index == 0) {
            _showAddTableDialog();
          } else if (_tabController.index == 1) {
            _showAddWaiterDialog();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildTabMesas() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 12,
      itemBuilder: (context, index) {
        final tableNumber = index + 1;
        return Card(
          child: ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withValues(alpha: 0.1),
              ),
              child: Center(
                child: Text('$tableNumber'),
              ),
            ),
            title: Text('Mesa $tableNumber'),
            subtitle: Text(
              index % 2 == 0 ? 'Disponível' : 'Ocupada',
              style: TextStyle(
                color: index % 2 == 0 ? Colors.green : Colors.orange,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.qr_code_2),
              onPressed: () {
                // Mostrar QR code para imprimir
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabWaiters() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Card(
          child: ListTile(
            leading: const CircleAvatar(
              child: Text('1'), // o valor muda, mas o widget em si pode ser const
            ),
            title: Text('Garçom ${index + 1}'),
            subtitle: Row(
              children: const [
                Icon(Icons.check_circle, size: 12, color: Colors.green),
                SizedBox(width: 4),
                Text('Disponível'),
                SizedBox(width: 12),
                Text('12 pedidos hoje'),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                // Remover garçom
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabStats() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Hoje',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 16),
                // _buildStatRow não pode ser const porque recebe parâmetros variáveis
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.grey)),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddTableDialog() {
    showDialog(
      context: context,
      builder: (context) => const AlertDialog(
        title: Text('Nova Mesa'),
        content: TextField(
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Número da mesa',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: null, // será substituído pelo Navigator.pop no onPressed real
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: null,
            child: Text('Criar'),
          ),
        ],
      ),
    );
  }

  void _showAddWaiterDialog() {
    showDialog(
      context: context,
      builder: (context) => const AlertDialog(
        title: Text('Novo Garçom'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'Telefone',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                hintText: 'Nome',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: null,
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: null,
            child: Text('Convidar'),
          ),
        ],
      ),
    );
  }
}