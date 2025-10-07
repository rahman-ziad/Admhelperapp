import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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
  bool _isConnected = true;
  late Stream<List<ConnectivityResult>> _connectivityStream;
  bool _isDialogShowing = false; // Track if dialog is visible

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeFirebase();
    _initConnectivity();
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
      _checkConnectivity();
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

  Future<void> _initConnectivity() async {
    // Initialize connectivity stream
    _connectivityStream = Connectivity().onConnectivityChanged;
    _connectivityStream.listen((List<ConnectivityResult> results) {
      setState(() {
        _isConnected = results.any((result) => result != ConnectivityResult.none);
      });
      if (!_isConnected && !_isDialogShowing) {
        _showNoInternetWarning();
      } else if (_isConnected && _isDialogShowing) {
        Navigator.of(context, rootNavigator: true).pop(); // Close dialog when reconnected
        _isDialogShowing = false;
      }
    });
    // Initial connectivity check
    await _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    setState(() {
      _isConnected = results.any((result) => result != ConnectivityResult.none);
    });
    if (!_isConnected && !_isDialogShowing) {
      _showNoInternetWarning();
    } else if (_isConnected && _isDialogShowing) {
      Navigator.of(context, rootNavigator: true).pop(); // Close dialog when reconnected
      _isDialogShowing = false;
    }
  }

  void _showNoInternetWarning() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDialogShowing) {
        _isDialogShowing = true;
        showDialog(
          context: context,
          barrierDismissible: false, // Prevent dismissing dialog
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('No Internet Connection'),
              content: const Text('Please check your network and try again.'),
              actions: [
                TextButton(
                  onPressed: () async {
                    await _checkConnectivity();
                  },
                  child: const Text('Retry'),
                ),
              ],
            );
          },
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SportsStation',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        cardTheme: const CardThemeData(elevation: 2),
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
      builder: (context, child) {
        return Stack(
          children: [
            child!,
            if (!_isConnected)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.red,
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'No Internet Connection',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _checkConnectivity,
                        child: const Text(
                          'Retry',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}