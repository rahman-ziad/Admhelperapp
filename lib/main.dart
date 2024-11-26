import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import './screens/homescreen.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool isDarkMode = false; // Default to light theme

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  // Load the saved theme from shared preferences
  void _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    bool? savedTheme = prefs.getBool('isDarkMode');
    setState(() {
      isDarkMode = savedTheme ?? false; // Default to light theme if not set
    });
  }

  // Save the current theme in shared preferences
  void _saveTheme(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('isDarkMode', value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: isDarkMode ? ThemeData.dark() : ThemeData.light(),
      home: HomeScreen(
        isDarkMode: isDarkMode,
        onThemeChange: (bool value) {
          setState(() {
            isDarkMode = value;
            _saveTheme(value);
          });
        },
      ),
    );
  }
}
