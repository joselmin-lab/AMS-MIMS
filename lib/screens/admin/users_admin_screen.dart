import 'package:ams_mims/screens/admin/user_edit_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UsersAdminScreen extends StatelessWidget {
  const UsersAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('users')
        .orderBy('active', descending: true)
        .orderBy('displayName')
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración · Usuarios'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const UserEditScreen()),
          );
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuevo'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No hay usuarios en /users.\nCrea uno con el botón "Nuevo".',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;

              final displayName = (data['displayName'] ?? '').toString();
              final email = (data['email'] ?? '').toString();
              final active = data['active'] as bool? ?? false;
              final roles = (data['roles'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList();

              return Card(
                child: ListTile(
                  title: Text(displayName.isNotEmpty ? displayName : '(Sin nombre)'),
                  subtitle: Text([
                    if (email.isNotEmpty) email,
                    if (roles.isNotEmpty) 'Roles: ${roles.join(', ')}',
                    'ID: ${doc.id}',
                  ].join(' · ')),
                  leading: Icon(active ? Icons.verified_user : Icons.person_off_outlined),
                  trailing: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Switch(
                        value: active,
                        onChanged: (v) async {
                          await doc.reference.update({
                            'active': v,
                            'updatedAt': FieldValue.serverTimestamp(),
                          });
                        },
                      ),
                      IconButton(
                        tooltip: 'Editar',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => UserEditScreen(userDoc: doc)),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}