// lib/screens/customers/add_edit_customer_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AddEditCustomerScreen extends StatefulWidget {
  final DocumentSnapshot? customerToEdit;

  const AddEditCustomerScreen({super.key, this.customerToEdit});

  @override
  State<AddEditCustomerScreen> createState() => _AddEditCustomerScreenState();
}

class _AddEditCustomerScreenState extends State<AddEditCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.customerToEdit != null) {
      final data = widget.customerToEdit!.data() as Map<String, dynamic>;
      _nameController.text = data['name'] ?? '';
      _emailController.text = data['email'] ?? '';
      _phoneController.text = data['phone'] ?? '';
    }
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final customerData = {
      'name': _nameController.text,
      'searchKeywords': _nameController.text.toLowerCase().split(' '), // <-- AÑADE ESTO
      'email': _emailController.text,
      'phone': _phoneController.text,
    };

    try {
      if (widget.customerToEdit == null) {
        await FirebaseFirestore.instance.collection('customers').add(customerData);
      } else {
        await FirebaseFirestore.instance
            .collection('customers')
            .doc(widget.customerToEdit!.id)
            .update(customerData);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.customerToEdit != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Cliente' : 'Añadir Cliente'),
        backgroundColor: Colors.blueGrey,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nombre Completo'),
              validator: (v) => v!.isEmpty ? 'Por favor, ingresa un nombre.' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Correo Electrónico'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Teléfono'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _saveCustomer,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
              child: _isLoading ? const CircularProgressIndicator() : const Text('Guardar Cliente'),
            )
          ],
        ),
      ),
    );
  }
}
