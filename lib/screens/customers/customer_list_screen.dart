// lib/screens/customers/customer_list_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ams_mims/screens/customers/add_edit_customer_screen.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final Stream<QuerySnapshot> _customersStream =
      FirebaseFirestore.instance.collection('customers').orderBy('name').snapshots();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Clientes'),
        backgroundColor: Colors.blueGrey, // Un color diferente para distinguirlo
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _customersStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Error al cargar los clientes.'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text('No hay clientes registrados.'),
            );
          }

          return ListView(
            children: snapshot.data!.docs.map((DocumentSnapshot document) {
              Map<String, dynamic> data =
                  document.data()! as Map<String, dynamic>;
              
              return Dismissible(
                key: Key(document.id),
                direction: DismissDirection.endToStart,
                onDismissed: (direction) {
                  FirebaseFirestore.instance
                      .collection('customers')
                      .doc(document.id)
                      .delete();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${data['name']} eliminado')),
                  );
                },
                background: Container(
                  color: Colors.red.shade700,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Icon(Icons.delete_forever, color: Colors.white),
                ),
                child: ListTile(
                  leading: const Icon(Icons.person, color: Colors.blueGrey),
                  title: Text(data['name'] ?? 'Sin Nombre'),
                  subtitle: Text('Email: ${data['email'] ?? 'N/A'} | Tel: ${data['phone'] ?? 'N/A'}'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            AddEditCustomerScreen(customerToEdit: document),
                      ),
                    );
                  },
                ),
              );
            }).toList(),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const AddEditCustomerScreen(),
            ),
          );
        },
        backgroundColor: Colors.blueGrey,
        child: const Icon(Icons.add),
      ),
    );
  }
}
