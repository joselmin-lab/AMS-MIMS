import 'dart:async';

import 'package:ams_mims/screens/auth/auth_gate.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Capture Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    // TODO: send to crash reporter if configured
  };

  await runZonedGuarded<Future<void>>(
    () async {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } catch (e, st) {
        // Log initialization failure (useful on Windows)
        debugPrint('ERROR: Firebase.initializeApp failed: $e\n$st');
        // Continue execution so UI can be shown; optionally show a dialog later
      }

      runApp(const MyApp());
    },
    (error, stack) {
      debugPrint('UNCAUGHT ERROR: $error\n$stack');
      // TODO: send to crash reporter if configured
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AMS MIMS',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blueGrey,
      ),
      home: const AuthGate(),
    );
  }
}