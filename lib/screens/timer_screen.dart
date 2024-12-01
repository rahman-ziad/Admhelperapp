import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'mcq.dart';
import 'history.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:just_audio/just_audio.dart';
class TimerScreen extends StatefulWidget {
  final int totalSeconds;
  final int mcqCount;

  const TimerScreen({
    required this.totalSeconds,
    required this.mcqCount,
  });

  @override
  _TimerScreenState createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  late int remainingTime;
  late Timer timer;
  bool isTimerRunning = true;
  bool isDarkMode = false;
  DateTime startTime = DateTime.now();

  late BannerAd _bannerAd;
  bool _isBannerAdLoaded = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  @override
  void initState() {
    super.initState();
    _loadTheme();
    remainingTime = widget.totalSeconds;
    startTimer();
    _loadBannerAd();
  }

  void _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool('isDarkMode') ?? false; // Default to false if no value is found
    });
  }
  // Load the banner ad
  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-2413088365868094/3460810464', // Test ad unit ID
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
  void startTimer() {
    timer = Timer.periodic(Duration(seconds: 1), (Timer timer) {
      if (remainingTime <= 0) {
        timer.cancel();
        isTimerRunning = false;
        _vibrateEnd();
        _playEndAlert();
        _showEndNotification();
      } else {
        setState(() {
          remainingTime--;
        });
        if (remainingTime % (widget.totalSeconds ~/ widget.mcqCount) == 0) {
          _vibrateMcq();
          _playMcqAlert();
        }
      }
      WakelockPlus.enable();
    });
  }

  void _vibrateMcq() async {
    if (await Vibration.hasVibrator() == true) {
      Vibration.vibrate(duration: 500);
    }
  }

  void _vibrateEnd() async {
    if (await Vibration.hasVibrator() == true) {
      Vibration.vibrate(duration: 1000);
    }
  }

  // Function to play the first alert sound when each MCQ milestone is reached
  void _playMcqAlert() async {
    // Play the first alert sound (you can replace it with your actual file path or asset)
    try {
      await _audioPlayer.setAsset('Asset/alert.mp3'); // Assuming the sound file is in your assets
      _audioPlayer.play();
    } catch (e) {
      print("Error playing MCQ alert: $e");
    }
  }

  // Function to play the second alert sound when the timer ends
  void _playEndAlert() async {
    // Play the second alert sound (you can replace it with your actual file path or asset)
    try {
      await _audioPlayer.setAsset('Asset/end.mp3'); // Assuming the sound file is in your assets
      _audioPlayer.play();
    } catch (e) {
      print("Error playing end alert: $e");
    }
  }

  void _showEndNotification() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Time\'s Up!',
            style: TextStyle(
              color: Colors.red, // Set the title text color here
            ),
          ),
          content: Text(
            'The timer has ended.',
            style: TextStyle(
              color: isDarkMode? Colors.white: Colors.black, // Set the content text color here
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showSummaryAndSave();
              },
              child: Text(
                'OK',
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


  void _toggleTimer() {
    if (isTimerRunning) {
      setState(() {
        isTimerRunning = false;
      });
      timer.cancel();
      WakelockPlus.disable();
    } else {
      setState(() {
        isTimerRunning = true;
      });
      startTimer();
      WakelockPlus.enable();
    }
  }

  Future<void> _showSummaryAndSave() async {
    DateTime endTime = DateTime.now();
    int timeTaken = widget.totalSeconds - remainingTime;
    double timePerMcq = timeTaken / widget.mcqCount;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Session Summary"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Total Time: ${widget.totalSeconds}s"),
            Text("Time Taken: ${timeTaken}s"),
            Text("MCQs: ${widget.mcqCount}"),
            Text("Avg Time/MCQ: ${timePerMcq.toStringAsFixed(2)}s"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _saveSession(timeTaken, timePerMcq);
              Navigator.of(context).pop();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => HistoryScreen()), // Navigate to HistoryScreen
              );
            },
            child: Text(
              "Save & View History",
              style: TextStyle(
                color: Colors.blue, // Button text color (can be customized)
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              _saveSession(timeTaken, timePerMcq);
              Navigator.of(context).pop(); // Close dialog
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => mcqscreen()), // Navigate to mcqscreen
              );
            },
            child: Text(
              "Save & Test Again",
              style: TextStyle(
                color: Colors.green, // Button text color (can be customized)
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSession(int timeTaken, double timePerMcq) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('exam_history') ?? [];

    Map<String, dynamic> sessionData = {
      "date": DateTime.now().toIso8601String(),
      "totalTime": widget.totalSeconds,
      "timeTaken": timeTaken,
      "mcqCount": widget.mcqCount,
      "timePerMcq": timePerMcq
    };

    history.add(jsonEncode(sessionData));
    prefs.setStringList('exam_history', history);
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
      ) ?? false;
    }
    return true;
  }

  @override
  void dispose() {
    _bannerAd.dispose();
    timer.cancel();
    super.dispose();
    _audioPlayer.dispose(); // Clean up the audio player when done
  }

  // **Confirm Finish Method Inside the State Class**
  Future<bool> _confirmFinish(BuildContext context) async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Finish Session'),
        content: Text('Are you sure you want to finish this session?'),
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
            onPressed: () {
              Navigator.of(context).pop(true);
              // Stop the timer when user confirms finish
              setState(() {
                isTimerRunning = false;
              });
              timer.cancel();  // Cancel the timer
            },
            child: Text(
              'Yes',
              style: TextStyle(
                color: Colors.green, // Set color for "Yes" button text
              ),
            ),
          ),
        ],

      ),
    ) ?? false;
  }


  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context); // Access device dimensions

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text('MCQ Timer'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(
            color: isDarkMode ? Colors.white : Colors.black,
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.done),
              onPressed: () async {
                if (await _confirmFinish(context)) {
                  _showSummaryAndSave();
                }
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            // Main Content with Background Image
            Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(
                    isDarkMode ? 'Asset/images/bg_dark.png' : 'Asset/images/bg_light.png',
                  ),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  GestureDetector(
                    onTap: _toggleTimer, // Pause or resume the timer on tap
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: remainingTime / widget.totalSeconds),
                      duration: Duration(seconds: 1),
                      builder: (context, value, child) {
                        return Container(
                          width: 250, // Diameter of the circular progress bar
                          height: 250,
                          child: CircularProgressIndicator(
                            value: value, // The progress value (0.0 to 1.0)
                            strokeWidth: 15, // Thicker stroke for better visibility
                            backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[300], // Adaptive background color
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDarkMode ? Color(0xff0a7075) : Color(0xFF0BC8EE), // Adaptive progress color
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
                          fontSize: 36, // Larger font size for timer
                          color: isDarkMode ? Colors.white : Colors.black, // Adaptive text color
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Remaining',
                        style: TextStyle(
                          fontSize: 18, // Smaller subtitle text
                          color: isDarkMode ? Colors.white70 : Colors.black54, // Adaptive text color
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),


          ],
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
                      value: widget.mcqCount.toString(),
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
