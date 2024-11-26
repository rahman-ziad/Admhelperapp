import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';

class HistoryScreen extends StatefulWidget {
  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  bool isDarkMode = false;
  late TabController _tabController;

  // Colors for AppBar and TopBar
  Color appBarColor = Colors.transparent;  // Transparent to allow background image to show
  Color textColor = Colors.black;
  Color subTextColor = Colors.black.withOpacity(0.7);

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _tabController = TabController(length: 2, vsync: this);  // Two tabs: MCQ History and Written History
  }

  void _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool('isDarkMode') ?? false;
      // Adjusting the colors based on the theme mode
      appBarColor = isDarkMode ? const Color(0xFF0A7075) : const Color(0xFF9BC7D0);
      textColor = isDarkMode ? Colors.white : Colors.black;
      subTextColor = isDarkMode ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.6);
    });
  }

  Future<List<Map<String, dynamic>>> _getMcqHistory() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('exam_history') ?? [];

    // Cast each decoded item to a Map<String, dynamic>
    return history.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  Future<List<Map<String, dynamic>>> _getWrittenHistory() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('written_exam_history') ?? [];

    // Cast each decoded item to a Map<String, dynamic>
    return history.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  // MCQ Tab Chart
  Widget _buildMcqChart(List<Map<String, dynamic>> data) {
    // Calculate average time per MCQ
    double avgTimePerMcq = data.isNotEmpty
        ? data.map((e) => e['timePerMcq'] ?? 0.0).reduce((a, b) => a + b) / data.length
        : 0.0;

    return Card(
      color: isDarkMode ? Colors.grey[850] : Colors.white,
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
        Padding(
        padding: const EdgeInsets.only(bottom: 30.0), // Add padding below the text
        child: Card( // Wrap in Card for better visual styling
          margin: EdgeInsets.zero, // Optional: Remove default margin around the Card
          child: Padding(
            padding: const EdgeInsets.all(8.0), // Add padding inside the Card
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween, // Space out the text
              children: [
                Text(
                  '∑ Exams: ${data.length}', // Left-aligned text
                  style: TextStyle(
                    fontSize: 16,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                Text(
                  'x̄ Time/MCQ: ${avgTimePerMcq.toStringAsFixed(2)}s', // Right-aligned text
                  style: TextStyle(
                    fontSize: 16,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

        SizedBox(height: 220, child: LineChart(_buildMcqChartData(data, avgTimePerMcq))),
          ],
        ),
      ),
    );
  }

  LineChartData _buildMcqChartData(List<Map<String, dynamic>> data, double avgTimePerMcq) {
    // Calculate the min and max values for timePerMcq
    double minValue = data.fold<double>(double.infinity, (prev, entry) {
      double time = entry['timePerMcq'] ?? 0.0;
      return time < prev ? time : prev;
    });

    double maxValue = data.fold<double>(double.negativeInfinity, (prev, entry) {
      double time = entry['timePerMcq'] ?? 0.0;
      return time > prev ? time : prev;
    });

    // Add a small padding to the max value to avoid label overlap
    maxValue = maxValue + 0.1;  // Add some space above the max value for better label positioning

    // Calculate the interval based on the range of values (divide by 6 for 6 labels)
    double range = maxValue - minValue;
    double interval = range / 6;

    // If the interval is too small, increase it to avoid overcrowding
    if (interval < 0.1) {
      interval = 0.1;
    }

    return LineChartData(
      lineBarsData: [
        // Line chart for MCQ times
        LineChartBarData(
          spots: data.asMap().entries.map((entry) {
            int index = entry.key;
            double timePerMcq = entry.value['timePerMcq'] ?? 0.0;
            return FlSpot(index.toDouble(), timePerMcq);
          }).toList(),
          isCurved: true,
          color: isDarkMode ? Colors.blue : Colors.green,
          dotData: FlDotData(show: true),
        ),
        // Average line (horizontal)
        LineChartBarData(
          spots: [
            FlSpot(0, avgTimePerMcq),
            FlSpot(data.length.toDouble(), avgTimePerMcq),
          ],
          isCurved: false,
          color: isDarkMode ? Colors.red : Colors.orange,
          barWidth: 2,
          belowBarData: BarAreaData(show: false), // No fill under the average line
        ),
      ],
      gridData: FlGridData(show: true, drawVerticalLine: false, drawHorizontalLine: true),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: (data.length / 8).ceil().toDouble(), // Show 8 titles on the X axis
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: interval,  // Use the calculated interval
            getTitlesWidget: (value, meta) {
              // Format Y-axis labels as float (2 decimal places)
              return Text(
                value.toStringAsFixed(2), // Show 2 decimal places
                style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(
          left: BorderSide(
            color: isDarkMode ? Colors.white : Colors.black,
            width: 1,
          ),
          bottom: BorderSide(
            color: isDarkMode ? Colors.white : Colors.black,
            width: 1,
          ),
          right: BorderSide(
            color: Colors.transparent, // Hide right border
            width: 0,
          ),
          top: BorderSide(
            color: Colors.transparent, // Hide top border
            width: 0,
          ),
        ),
      ),
    );
  }



  // MCQ History List
  Widget _buildMcqHistoryList(List<Map<String, dynamic>> data) {
    // Invert the list by reversing it
    List<Map<String, dynamic>> invertedData = data.reversed.toList();

    return Expanded(
      child: ListView.builder(
        itemCount: invertedData.length, // Use the inverted list's length
        itemBuilder: (context, index) {
          var session = invertedData[index]; // Access the inverted list
          DateTime dateTime = DateTime.parse(session['date']);

          String formattedDate = DateFormat('hh:mm a d MMMM yyyy')
              .format(dateTime); // Adjusted for Bangladesh Standard Time

          return Card(
            color: isDarkMode ? Colors.grey[800] : Colors.white,
            margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formattedDate, style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text("Total Time: ${_convertToMinSec(session['totalTime'].toDouble())} m   Time Taken: ${session['timeTaken']}s"),
                  Text("Total MCQs: ${session['mcqCount']}   Avg Time/MCQ: ${session['timePerMcq']?.toStringAsFixed(2) ?? '0.00'}s"),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Written Tab Chart
  Widget _buildWrittenChart(List<Map<String, dynamic>> data) {
    // Calculate average time per written (in seconds) and convert to minutes
    double avgTimePerWrittenins = data.isNotEmpty
        ? data.map((e) => e['timePerWritten'] ?? 0.0).reduce((a, b) => a + b) / data.length
        : 0.0;

    // Convert avgTimePerWritten to minutes
    double avgTimePerWritten = avgTimePerWrittenins / 60;

    return Card(
      color: isDarkMode ? Colors.grey[850] : Colors.white,
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Padding for the text (total exams and average time per written)
        Padding(
        padding: const EdgeInsets.only(bottom: 15.0), // Add space below the text
        child: Card( // Add card container for better visuals
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(8.0), // Padding inside the card
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween, // Distribute space between text elements
              children: [
                Text(
                  '∑ Exams: ${data.length}', // Left-aligned text
                  style: TextStyle(
                    fontSize: 16,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                Text(
                  'x̄ Time/Written: ${_convertToMinSec(avgTimePerWritten * 60)} m', // Right-aligned text
                  style: TextStyle(
                    fontSize: 16,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

        // Padding for the chart
            Padding(
              padding: const EdgeInsets.only(top: 15.0), // Add space above the chart
              child: SizedBox(
                height: 220,
                child: LineChart(_buildWrittenChartData(data, avgTimePerWritten)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  LineChartData _buildWrittenChartData(List<Map<String, dynamic>> data, double avgTimePerWritten) {
    // Convert timePerWritten to minutes and calculate the min and max values
    double minValue = data.fold<double>(double.infinity, (prev, entry) {
      double time = (entry['timePerWritten'] ?? 0.0) / 60; // Convert to minutes
      return time < prev ? time : prev;
    });

    double maxValue = data.fold<double>(double.negativeInfinity, (prev, entry) {
      double time = (entry['timePerWritten'] ?? 0.0) / 60; // Convert to minutes
      return time > prev ? time : prev;
    });

    // Add a small padding to the max value to avoid label overlap
    maxValue = maxValue + 0.1;  // Add some space above the max value for better label positioning

    // Calculate the interval based on the range of values (divide by 6 for 6 labels)
    double range = maxValue - minValue;
    double interval = range / 6;

    // If the interval is too small, increase it to avoid overcrowding
    if (interval < 0.1) {
      interval = 0.1;
    }

    return LineChartData(
      lineBarsData: [
        // Line chart for Written times in minutes
        LineChartBarData(
          spots: data.asMap().entries.map((entry) {
            int index = entry.key;
            double timePerWritten = (entry.value['timePerWritten'] ?? 0.0) / 60; // Convert to minutes
            return FlSpot(index.toDouble(), timePerWritten);
          }).toList(),
          isCurved: true,
          color: isDarkMode ? Colors.purple : Color(0x80dd00ff),
          dotData: FlDotData(show: true),
        ),
        // Average line (horizontal) for written in minutes
        LineChartBarData(
          spots: [
            FlSpot(0, avgTimePerWritten),
            FlSpot(data.length.toDouble(), avgTimePerWritten),
          ],
          isCurved: false,
          color: isDarkMode ? Colors.red : Colors.orange,
          barWidth: 2,
          belowBarData: BarAreaData(show: false), // No fill under the average line
        ),
      ],
      gridData: FlGridData(show: true, drawVerticalLine: false, drawHorizontalLine: true),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: (data.length / 8).ceil().toDouble(), // Show 8 titles on the X axis
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: interval,  // Use the calculated interval
            getTitlesWidget: (value, meta) {
              // Format Y-axis labels as float (2 decimal places) for minutes
              return Text(
                value.toStringAsFixed(2), // Show 2 decimal places
                style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(
          left: BorderSide(
            color: isDarkMode ? Colors.white : Colors.black,
            width: 1,
          ),
          bottom: BorderSide(
            color: isDarkMode ? Colors.white : Colors.black,
            width: 1,
          ),
          right: BorderSide(
            color: Colors.transparent, // Hide right border
            width: 0,
          ),
          top: BorderSide(
            color: Colors.transparent, // Hide top border
            width: 0,
          ),
        ),
      ),
    );
  }

// Written History List
  Widget _buildWrittenHistoryList(List<Map<String, dynamic>> data) {
    // Invert the list by reversing it
    List<Map<String, dynamic>> invertedData = data.reversed.toList();

    return Expanded(
      child: ListView.builder(
        itemCount: invertedData.length, // Use the inverted list's length
        itemBuilder: (context, index) {
          var session = invertedData[index]; // Access the inverted list
          DateTime dateTime = DateTime.parse(session['date']);
          String formattedDate = DateFormat('hh:mm a d MMMM yyyy')
              .format(dateTime); // Adjusted for Bangladesh Standard Time

          return Card(
            color: isDarkMode ? Colors.grey[800] : Colors.white,
            margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formattedDate, style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text("Total Time: ${_convertToMinSec(session['totalTime'].toDouble())} m   Time Taken: ${_convertToMinSec(session['timeTaken'].toDouble())} m"),
                  Text("Total Written: ${session['writtenCount']}   Avg Time/Written: ${_convertToMinSec(session['timePerWritten'])} m"),
                ],
              ),
            ),
          );
        },
      ),
    );
  }


  String _convertToMinSec(double timeInSeconds) {
    int minutes = (timeInSeconds ~/ 60);  // Integer division to get full minutes
    int seconds = (timeInSeconds % 60).toInt();  // Get remaining seconds

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _deleteHistory(String historyType) async {
    final prefs = await SharedPreferences.getInstance();
    if (historyType == 'mcq_history') {
      await prefs.remove('exam_history'); // Delete MCQ history
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('MCQ History Deleted')),
      );
    } else if (historyType == 'written_exam_history') {
      await prefs.remove('written_exam_history'); // Delete Written history
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Written Exam History Deleted')),
      );
    }
    setState(() {
      // Refresh the state after deleting the history
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        title: Text(
          "History",
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        backgroundColor: appBarColor,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              // Handle the menu selection
              if (value == 'delete_mcq') {
                _deleteHistory('mcq_history');
              } else if (value == 'delete_written') {
                _deleteHistory('written_exam_history');
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'delete_mcq',
                child: Text("Delete MCQ History"),
              ),
              PopupMenuItem<String>(
                value: 'delete_written',
                child: Text("Delete Written History"),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'MCQ History'),
            Tab(text: 'Written History'),
          ],
          indicatorColor: isDarkMode ? Color(0xFFFF4081) : Color(0xFF4CAF50),
          labelColor: isDarkMode ? Colors.white : Colors.black,
          unselectedLabelColor: isDarkMode
              ? Colors.white.withOpacity(0.7)
              : Colors.black.withOpacity(0.7),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(isDarkMode ? 'Asset/images/bg_dark.png' : 'Asset/images/bg_light.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // MCQ History Tab
                  FutureBuilder<List<Map<String, dynamic>>>(  // Updated FutureBuilder
                    future: _getMcqHistory(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Center(child: CircularProgressIndicator());
                      }
                      List<Map<String, dynamic>> data = snapshot.data!;
                      if (data.isEmpty) {
                        return Center(child: Text("No MCQ History Found"));
                      }
                      return Column(
                        children: [
                          _buildMcqChart(data),
                          _buildMcqHistoryList(data),
                        ],
                      );
                    },
                  ),
                  // Written History Tab
                  FutureBuilder<List<Map<String, dynamic>>>(  // Updated FutureBuilder
                    future: _getWrittenHistory(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Center(child: CircularProgressIndicator());
                      }
                      List<Map<String, dynamic>> data = snapshot.data!;
                      if (data.isEmpty) {
                        return Center(child: Text("No Written History Found"));
                      }
                      return Column(
                        children: [
                          _buildWrittenChart(data),
                          _buildWrittenHistoryList(data),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
