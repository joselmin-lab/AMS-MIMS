import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UserEditScreen extends StatefulWidget {
  final DocumentSnapshot? userDoc;

  const UserEditScreen({super.key, this.userDoc});

  @override
  State<UserEditScreen> createState() => _UserEditScreenState();
}

class _UserEditScreenState extends State<UserEditScreen> {
  final _formKey = GlobalKey<FormState>();

  final _uidCtrl = TextEditingController(); // NUEVO
  final _displayNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  bool _active = true;
  bool _roleAdmin = false;
  bool _roleOperator = true;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final doc = widget.userDoc;
    if (doc != null) {
      _uidCtrl.text = doc.id; // NUEVO: el docId es el UID
      final data = doc.data() as Map<String, dynamic>;
      _displayNameCtrl.text = (data['displayName'] ?? '').toString();
      _emailCtrl.text = (data['email'] ?? '').toString();
      _active = data['active'] as bool? ?? true;

      final roles = (data['roles'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toSet();
      _roleAdmin = roles.contains('admin');
      _roleOperator = roles.contains('operator');
    }
  }

  @override
  void dispose() {
    _uidCtrl.dispose(); // NUEVO
    _displayNameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  List<String> _buildRoles() {
    final roles = <String>[];
    if (_roleAdmin) roles.add('admin');
    if (_roleOperator) roles.add('operator');
    return roles;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.userDoc != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Editar usuario' : 'Crear perfil de usuario'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!isEdit) ...[
              TextFormField(
                controller: _uidCtrl,
                decoration: const InputDecoration(
                  labelText: 'UID (Firebase Auth)',
                  border: OutlineInputBorder(),
                  helperText: 'Pega el uid del usuario creado en Firebase Auth.',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Ingresa el UID.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
            ] else ...[
              // En edición solo mostramos el UID (readonly)
              TextFormField(
                initialValue: _uidCtrl.text,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'UID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _displayNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre para mostrar',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Ingresa un nombre.';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Activo'),
            ),
            const Divider(height: 24),
            const Text('Roles', style: TextStyle(fontWeight: FontWeight.bold)),
            CheckboxListTile(
              value: _roleOperator,
              onChanged: (v) => setState(() => _roleOperator = v ?? false),
              title: const Text('operator'),
            ),
            CheckboxListTile(
              value: _roleAdmin,
              onChanged: (v) => setState(() => _roleAdmin = v ?? false),
              title: const Text('admin'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_saving ? 'Guardando...' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final roles = _buildRoles();
    if (roles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos un rol (operator o admin).')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'displayName': _displayNameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'active': _active,
        'roles': roles,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.userDoc == null) {
        final uid = _uidCtrl.text.trim();
        payload['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set(payload, SetOptions(merge: true));
      } else {
        await widget.userDoc!.reference.update(payload);
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error guardando usuario: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}