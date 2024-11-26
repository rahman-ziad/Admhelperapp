
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TemplateScreen extends StatelessWidget {
  final bool isDarkMode;

  const TemplateScreen({super.key, required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
              isDarkMode ? 'Asset/images/bg_dark.png' : 'Asset/images/bg_light.png',
            ),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: isDarkMode ? Colors.white : Colors.black,
                    size: 35.0,
                  ),
                  onPressed: () {
                    Navigator.pop(context); // Go back to the previous screen
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 10, 0, 0),
                child: Text(
                  'Template Screen',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black,
                    fontSize: 25.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Container(), // Empty body to maintain the styling and alignment
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Static method to fetch the dark mode value from SharedPreferences
  static Future<bool> getDarkModePreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isDarkMode') ?? false; // Default to false if no value is found
  }
}
