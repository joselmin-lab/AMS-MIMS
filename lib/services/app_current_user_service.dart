import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppCurrentUserService {
  final FirebaseFirestore db;
  final FirebaseAuth auth;

  AppCurrentUserService({FirebaseFirestore? firestore, FirebaseAuth? firebaseAuth})
      : db = firestore ?? FirebaseFirestore.instance,
        auth = firebaseAuth ?? FirebaseAuth.instance;

  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final u = auth.currentUser;
    if (u == null) return null;

    final snap = await db.collection('users').doc(u.uid).get();
    if (!snap.exists) return null;
    return snap.data();
  }

  Future<bool> isAdmin() async {
    final profile = await getCurrentUserProfile();
    final roles = (profile?['roles'] as List<dynamic>? ?? const []);
    return roles.contains('admin');
  }
}