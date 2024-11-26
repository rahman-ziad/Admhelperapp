import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart'; // Import vibration package
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'written.dart'; // Assuming written.dart is your destination screen after finishing the exam.
import 'history.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
class WrittenTimerScreen extends StatefulWidget {
  final int totalSeconds;
  final int writtenCount;

  const WrittenTimerScreen({
    required this.totalSeconds,
    required this.writtenCount,
  });

  @override
  _WrittenTimerScreenState createState() => _WrittenTimerScreenState();
}

class _WrittenTimerScreenState extends State<WrittenTimerScreen> {
  bool isDarkMode = false; // Initialize dark mode
  late int remainingTime;
  late Timer timer;
  bool isTimerRunning = true; // Track if the timer is running
  late String totalTimeM;
  late BannerAd _bannerAd;
  bool _isBannerAdLoaded = false;
  @override
  void initState() {
    super.initState();
    _loadTheme();
    remainingTime = widget.totalSeconds;
    startTimer();
    _loadBannerAd();
  }
  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-2413088365868094/5994331855', // Test ad unit ID
      size: AdSize.banner,
      request: AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          setState(() {
            _isBannerAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          print('Failed to load a banner ad: $error');
          ad.dispose();
        },
      ),
    );
    _bannerAd.load();
  }
  void _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool('isDarkMode') ?? false; // Default to false if no value is found
    });
  }

  void startTimer() {
    timer = Timer.periodic(Duration(seconds: 1), (Timer timer) {
      if (remainingTime <= 0) {
        timer.cancel();
        isTimerRunning = false; // Update timer status
        _vibrateEnd();
        _showEndNotification();
      } else {
        setState(() {
          remainingTime--;
        });
        if (remainingTime % (widget.totalSeconds ~/ widget.writtenCount) == 0) {
          _vibrateWritten();
        }
      }
      WakelockPlus.enable();
    });
  }

  void _vibrateWritten() async {
    bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(duration: 500); // Vibrate for 500 milliseconds
    }
  }

  void _vibrateEnd() async {
    bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(duration: 1000); // Vibrate for 1 second
    }
  }

  // Show an alert when the timer ends
  void _showEndNotification() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Time\'s Up!',
            style: TextStyle(
              color: Colors.red, // Set the title text color here
            ),
          ),
          content: Text('The timer has ended for this written section.',
            style: TextStyle(
              color: isDarkMode? Colors.white: Colors.black, // Set the content text color here
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showSummaryAndSave(); // Show the summary and allow user to save
              },
              child: Text('OK',
                style: TextStyle(
                  color: Colors.green, // Set the OK button text color here
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Pause or resume the timer based on its current state
  void _toggleTimer() {
    if (isTimerRunning) {
      // Pause the timer
      setState(() {
        isTimerRunning = false;
      });
      timer.cancel(); // Stop the periodic timer
      WakelockPlus.disable();
    } else {
      // Resume the timer
      setState(() {
        isTimerRunning = true;
      });
      startTimer(); // Restart the timer from the current remaining time
      WakelockPlus.enable();
    }
  }

  // Show summary dialog and save session data to SharedPreferences
  Future<void> _showSummaryAndSave() async {
    DateTime endTime = DateTime.now();
    int timeTaken = widget.totalSeconds - remainingTime;
    double timePerWritten = timeTaken / widget.writtenCount;
    totalTimeM = "${(widget.totalSeconds ~/ 60).toString().padLeft(2, '0')}m ${widget.totalSeconds % 60}s";
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Session Summary"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Total Time: ${totalTimeM}"),
            Text("Time Taken: ${timeTaken}s"),
            Text("Writtens: ${widget.writtenCount}"),
            Text("Avg Time/Question: ${timePerWritten.toStringAsFixed(2)}s"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _saveSession(timeTaken, timePerWritten);
              Navigator.of(context).pop();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => HistoryScreen()), // Navigate to HistoryScreen
              );
            },
            child: Text(
              "Save & View History",
              style: TextStyle(
                color: Colors.blue, // Set color for "Save & View History" button text
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              _saveSession(timeTaken, timePerWritten);
              Navigator.of(context).pop();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => writtenscreen()), // Navigate to writtenscreen
              );
            },
            child: Text(
              "Save & Test Again",
              style: TextStyle(
                color: Colors.green, // Set color for "Save & Test Again" button text
              ),
            ),
          ),
        ],

      ),
    );
  }

  // Show confirm finish dialog before saving and exiting
  Future<bool> _showConfirmFinishDialog() async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Confirm Finish"),
        content: Text("Are you sure you want to finish this session?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // No, don't finish
            child: Text(
              "No",
              style: TextStyle(
                color: Colors.red, // Set color for "No" button text
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              // Pause the timer and finish
              setState(() {
                isTimerRunning = false;
              });
              timer.cancel(); // Stop the timer
              Navigator.of(context).pop(true); // Yes, finish
            },
            child: Text(
              "Yes",
              style: TextStyle(
                color: Colors.green, // Set color for "Yes" button text
              ),
            ),
          ),
        ],

      ),
    ) ?? false; // Default to false if dialog is dismissed
  }

  // Save session data to SharedPreferences under 'written_exam_history'
  Future<void> _saveSession(int timeTaken, double timePerWritten) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('written_exam_history') ?? [];

    Map<String, dynamic> sessionData = {
      "date": DateTime.now().toIso8601String(),
      "totalTime": widget.totalSeconds,
      "timeTaken": timeTaken,
      "writtenCount": widget.writtenCount,
      "timePerWritten": timePerWritten
    };

    history.add(jsonEncode(sessionData));
    prefs.setStringList('written_exam_history', history);
  }

  Future<bool> _onWillPop() async {
    if (isTimerRunning) {
      return await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Confirm Exit'),
          content: Text('Are you sure you want to exit the timer?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'No',
                style: TextStyle(
                  color: Colors.red, // Set color for "No" button text
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Yes',
                style: TextStyle(
                  color: Colors.green, // Set color for "Yes" button text
                ),
              ),
            ),
          ],

        ),
      ) ?? false; // Return false if dialog is dismissed
    }
    return true; // Allow back navigation if timer is not running
  }

  @override
  void dispose() {
    _bannerAd.dispose();
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text('Written Timer'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(
            color: isDarkMode ? Colors.white : Colors.black,
          ),
          actions: [
            // Adding the "Complete Exam" button on the AppBar
            IconButton(
              icon: Icon(Icons.check),
              onPressed: () async {
                // Confirm finish before proceeding
                bool confirmFinish = await _showConfirmFinishDialog();
                if (confirmFinish) {
                  _showSummaryAndSave(); // Show summary if confirmed
                }
              },
              color: isDarkMode ? Colors.white : Colors.black,
            ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(
                isDarkMode ? 'Asset/images/bg_dark.png' : 'Asset/images/bg_light.png',
              ),
              fit: BoxFit.cover,
            ),
          ),
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                GestureDetector(
                  onTap: _toggleTimer, // Toggle the timer on tap
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: remainingTime / widget.totalSeconds),
                    duration: Duration(seconds: 1),
                    builder: (context, value, child) {
                      return Container(
                        width: 250,
                        height: 250,
                        child: CircularProgressIndicator(
                          value: value, // The progress value (0.0 to 1.0)
                          strokeWidth: 15,
                          backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[300], // Background color based on dark mode
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDarkMode ? Color(0xff0a7075) : Color(0xFF0BC8EE), // Progress color based on dark mode
                          ),
                        ),

                      );
                    },
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${(remainingTime ~/ 60).toString().padLeft(2, '0')} : ${(remainingTime % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontSize: 36,
                        color: isDarkMode ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Remaining',
                      style: TextStyle(
                        fontSize: 18,
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        bottomSheet: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.grey[900] : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                offset: Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildSummaryCard(
                      title: 'Total MCQ',
                      value: widget.writtenCount.toString(),
                      isDarkMode: isDarkMode,
                    ),
                    _buildSummaryCard(
                      title: 'Total Time',
                      value: '${(widget.totalSeconds ~/ 60).toString().padLeft(2, '0')} m ${widget.totalSeconds % 60} s',
                      isDarkMode: isDarkMode,
                    ),
                  ],
                ),
              ),
              if (_isBannerAdLoaded)
                Container(
                  height: _bannerAd.size.height.toDouble(),
                  child: AdWidget(ad: _bannerAd),
                ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _toggleTimer,
          backgroundColor: isDarkMode ? Color(0xff0a7075) : Color(0xFF0BC8EE),
          child: Icon(
            isTimerRunning ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required bool isDarkMode,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            color: isDarkMode ? Colors.white : Colors.black,
          ),
        ),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isDarkMode ? Colors.white : Colors.black,
          ),
        ),
      ],
    );
  }
}