import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/auth_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FlutterError.onError = (FlutterErrorDetails details) {
    print('Flutter Error: ${details.exceptionAsString()}');
    print(details.stack);
  };
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isFirebaseInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeFirebase();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initializeFirebase();
    }
  }

  Future<void> _initializeFirebase() async {
    try {
      if (!_isFirebaseInitialized) {
        await Firebase.initializeApp();
        setState(() {
          _isFirebaseInitialized = true;
        });
      }
    } catch (e) {
      print('Firebase initialization failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SportsStation',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        cardTheme: const CardTheme(elevation: 2),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          bodyMedium: TextStyle(fontSize: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          ),
        ),
      ),
      home: _isFirebaseInitialized
          ? const AuthWrapper()
          : const Center(child: CircularProgressIndicator()),
    );
  }
}