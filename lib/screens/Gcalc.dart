import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class GcalcScreen extends StatefulWidget {
  @override
  _GcalcScreenState createState() => _GcalcScreenState();
}

class _GcalcScreenState extends State<GcalcScreen> {
  bool isDarkMode = false;
  List<Map<String, dynamic>> universityData = [];
  DateTime currentDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
    _fetchUniversityData(); // Fetch the university data from the CSV file
  }

  // Load the theme preference from SharedPreferences
  void _loadThemePreference() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  // Fetch university data from the CSV file
  void _fetchUniversityData() async {
    final response = await http.get(Uri.parse('https://raw.githubusercontent.com/rahman-ziad/appdata/refs/heads/main/university%20exam%20date%20-%20Sheet1.csv'));
    if (response.statusCode == 200) {
      // Parse the CSV data
      List<String> lines = const LineSplitter().convert(response.body);
      // Extract headers (you can skip the first header if it's a CSV format with headers)
      for (var i = 1; i < lines.length; i++) {
        List<String> values = lines[i].split(',');
        Map<String, dynamic> entry = {
          'Image URL': values[0],        // Image URL
          'University Name': values[1],  // University Name
          'Exam Date': values[2],        // Exam Date
        };
        universityData.add(entry);
      }
      setState(() {});
    } else {
      throw Exception('Failed to load university data');
    }
  }

  // Calculate time remaining until the exam date
  String _calculateTimeRemaining(String examDate) {
    DateTime dateTime = DateTime.parse(examDate);
    Duration difference = dateTime.difference(currentDate);
    if (difference.isNegative) {
      return "Exam Passed";
    } else {
      return "${difference.inDays} days";
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get screen height
    double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("Exam Calender"),
        backgroundColor: Colors.transparent,
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
              isDarkMode
                  ? 'Asset/images/bg_dark.png' // Dark mode background
                  : 'Asset/images/bg_light.png', // Light mode background
            ),
            fit: BoxFit.cover,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(top: screenHeight * 0.05), // 5% padding from top
          child: universityData.isNotEmpty
              ? ListView.builder(
            itemCount: universityData.length,
            itemBuilder: (context, index) {
              final university = universityData[index];
              return Card(
                margin: EdgeInsets.all(8.0),
                child: ListTile(
                  contentPadding: EdgeInsets.all(10),
                  leading: university['Image URL'] != null
                      ? Image.network(
                    university['Image URL'],
                    width: 50, // Adjust size as needed
                    height: 50,
                    fit: BoxFit.cover,
                  )
                      : null, // Handle case where no image URL is provided
                  title: Text(university['University Name']),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Exam Date: ${university['Exam Date']}'),
                      Text('Time Remaining: ${_calculateTimeRemaining(university['Exam Date'])}'),
                    ],
                  ),
                ),
              );
            },
          )
              : Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}
