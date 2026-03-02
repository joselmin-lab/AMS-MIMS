import 'package:ams_mims/services/production_issue_to_process_service.dart';
import 'package:ams_mims/services/production_parent_materials_gate_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AssignOperatorsToStagesScreen extends StatefulWidget {
  final DocumentSnapshot parentOrderDoc;

  const AssignOperatorsToStagesScreen({
    super.key,
    required this.parentOrderDoc,
  });

  @override
  State<AssignOperatorsToStagesScreen> createState() => _AssignOperatorsToStagesScreenState();
}

class _AssignOperatorsToStagesScreenState extends State<AssignOperatorsToStagesScreen> {
  static const stages = <String>[
    'Mecanizado',
    'Soldadura',
    'Pintura',
    'Ensamblaje',
    'Control de Calidad',
  ];

  bool _saving = false;
  final Map<String, Set<String>> _assigned = {for (final s in stages) s: <String>{}};
  final Map<String, bool> _notRequired = {for (final s in stages) s: false};

  @override
  void initState() {
    super.initState();
    final data = widget.parentOrderDoc.data() as Map<String, dynamic>?;
    final processStages = data?['processStages'] as List<dynamic>?;

    if (processStages != null) {
      for (var stageData in processStages) {
        final stageName = (stageData['name'] ?? '').toString();
        if (stages.contains(stageName)) {
          final assignedUsers = (stageData['assignedUsers'] as List<dynamic>? ?? []);
          final isSkipped = (stageData['state'] ?? '') == 'skipped';

          if (isSkipped) {
            _notRequired[stageName] = true;
          } else if (assignedUsers.isNotEmpty) {
            final userIds = assignedUsers
                .map((u) => (u['id'] ?? '').toString())
                .where((id) => id.isNotEmpty)
                .toSet();
            _assigned[stageName] = userIds;
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.parentOrderDoc.data() as Map<String, dynamic>;
    final displayOrderNumber = (data['displayOrderNumber'] ?? data['orderNumber'] ?? '').toString();
    final isEditing = (data['status'] ?? '') == 'En Proceso';

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Asignaciones OP #$displayOrderNumber' : 'Pasar OP #$displayOrderNumber a Proceso'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('operators')
            .where('active', isEqualTo: true)
            .orderBy('displayName')
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final operators = snap.data!.docs;

          if (operators.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No hay operarios activos en /operators.', textAlign: TextAlign.center),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(
                isEditing
                    ? 'Modifica las asignaciones de operarios para cada etapa.'
                    : 'Asigna operarios por etapa. Luego se validan materiales, se emiten a producción y la OP pasa a "En Proceso".',
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              ...stages.map((stage) {
                final isNotRequired = _notRequired[stage] ?? false;
                return Card(
                  color: isNotRequired ? Colors.grey[200] : null,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              stage,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isNotRequired ? Colors.grey[600] : null,
                              ),
                            ),
                            Row(
                              children: [
                                Text('No Requerida', style: TextStyle(color: isNotRequired ? Colors.grey[800] : Colors.grey[600])),
                                Checkbox(
                                  value: isNotRequired,
                                  onChanged: (val) {
                                    setState(() {
                                      _notRequired[stage] = val ?? false;
                                      if (val == true) _assigned[stage]!.clear();
                                    });
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (!isNotRequired) const SizedBox(height: 8),
                        if (!isNotRequired)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: operators.map((doc) {
                              final o = doc.data() as Map<String, dynamic>;
                              final name = (o['displayName'] ?? doc.id).toString();
                              final selected = _assigned[stage]!.contains(doc.id);
                              return FilterChip(
                                label: Text(name),
                                selected: selected,
                                onSelected: (v) {
                                  setState(() {
                                    if (v) {
                                      _assigned[stage]!.add(doc.id);
                                    } else {
                                      _assigned[stage]!.remove(doc.id);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving
                    ? null
                    : () {
                        if (isEditing) {
                          _updateAssignments(context, operators);
                        } else {
                          _confirmAndAdvance(context, operators);
                        }
                      },
                icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                label: Text(_saving ? 'Guardando...' : (isEditing ? 'Guardar Cambios' : 'Confirmar y pasar a Proceso')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _updateAssignments(BuildContext context, List<QueryDocumentSnapshot> operators) async {
    setState(() => _saving = true);
    try {
      final stagesPayload = _buildStagesPayload(operators);

      await widget.parentOrderDoc.reference.update({
        'processStages': stagesPayload,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (context.mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al actualizar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmAndAdvance(BuildContext context, List<QueryDocumentSnapshot> operators) async {
    setState(() => _saving = true);
    try {
      final parentData = widget.parentOrderDoc.data() as Map<String, dynamic>;
      final parentOrderNumber = parentData['orderNumber'];
      final children = await FirebaseFirestore.instance
          .collection('production_orders')
          .where('parentOrderNumber', isEqualTo: parentOrderNumber)
          .get();

      final pendingChildren = children.docs.where((d) => (d.data()['status'] ?? '').toString() != 'Finalizadas').toList();
      if (pendingChildren.isNotEmpty && context.mounted) {
        return;
      }

      final gate = ProductionParentMaterialsGateService();
      final res = await gate.checkParentMaterialsReady(parentOrderDoc: widget.parentOrderDoc);
      if (!(res['ok'] as bool) && context.mounted) {
        return;
      }

      final issueSvc = ProductionIssueToProcessService();
      await issueSvc.issueAllRequiredPartsToProduction(parentOrderDoc: widget.parentOrderDoc);

      final stagesPayload = _buildStagesPayload(operators);

            // Buscamos la primera etapa que no haya sido marcada como "No requerida" (skipped)
      String nextStage = 'Finalizadas';
      for (var stage in stagesPayload) {
        if (stage['state'] != 'skipped') {
          nextStage = stage['name'] as String;
          break;
        }
      }

      await widget.parentOrderDoc.reference.update({
        'status': 'En Proceso',
        'processStage': nextStage,
        'processStages': stagesPayload,
        'inProcessAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Map<String, dynamic>> _buildStagesPayload(List<QueryDocumentSnapshot> operators) {
    final Map<String, Map<String, dynamic>> byId = {
      for (final o in operators)
        o.id: {
          'id': o.id,
          'name': ((o.data() as Map<String, dynamic>)['displayName'] ?? o.id).toString(),
        }
    };

    return stages.map((stageName) {
      if (_notRequired[stageName] == true) {
        return {
          'name': stageName,
          'assignedUsers': [],
          'state': 'skipped',
        };
      } else {
        final ids = _assigned[stageName]!.toList();
        final assignedUsers = ids.where(byId.containsKey).map((id) => byId[id]!).toList();
        return {
          'name': stageName,
          'assignedUsers': assignedUsers,
          'state': 'pending',
        };
      }
    }).toList();
  }
}