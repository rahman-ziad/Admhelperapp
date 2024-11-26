import 'package:flutter/material.dart';
import '../screens/timer_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'homescreen.dart';
class mcqscreen extends StatefulWidget {

  @override
  _mcqscreenState createState() => _mcqscreenState();
}

class _mcqscreenState extends State<mcqscreen> {
  bool isDarkMode = false;
  String mcqCount = '30';  // Default value for number of MCQs
  int selectedMinutes = 0;  // Default value for minutes
  int selectedSeconds = 36;  // Default value for seconds

  @override
  void initState() {
    super.initState();
    _loadTheme(); // Load the saved theme when the screen starts
  }

  // Function to load the saved theme from shared preferences
  void _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool('isDarkMode') ?? false; // Default to false if no value is found
    });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('MCQ Timer'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
              isDarkMode
                  ? 'Asset/images/bg_dark.png'
                  : 'Asset/images/bg_light.png',
            ),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Card(
              elevation: 8,
              margin: EdgeInsets.all(20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Enter number of MCQs',
                      style: TextStyle(
                        fontSize: 18,
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                    SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => _showMcqPicker(context),
                      child: AbsorbPointer(
                        child: _buildElevatedTextField(
                          context,
                          isDarkMode,
                              (value) {},
                          initialValue: mcqCount,
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Time for each MCQ',
                      style: TextStyle(
                        fontSize: 18,
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                    SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => _showTimePicker(context),
                      child: AbsorbPointer(
                        child: _buildElevatedTextField(
                          context,
                          isDarkMode,
                              (value) {},
                          initialValue: '${selectedMinutes}m ${selectedSeconds}s',
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        int mcqCountInt = int.tryParse(mcqCount) ?? 0;

                        if (mcqCount.isEmpty || (selectedMinutes == 0 && selectedSeconds == 0)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Please enter valid inputs.'),
                            ),
                          );
                        } else {
                          int timePerMcqInSeconds = (selectedMinutes * 60) + selectedSeconds;
                          int totalSeconds = mcqCountInt * timePerMcqInSeconds;

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => TimerScreen(
                                totalSeconds: totalSeconds,

                                mcqCount: mcqCountInt,
                              ),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDarkMode? Color(0xff0a7075): Color(0xFF0BC8EE),
                        foregroundColor: Colors.white,
                      ),
                      child: Text('Start'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildElevatedTextField(BuildContext context, bool isDarkMode, Function(String) onChanged, {String initialValue = ''}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: isDarkMode ? Colors.grey[800] : Colors.grey[300],
      ),
      child: TextField(
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        ),
        onChanged: onChanged,
        readOnly: true,
        controller: TextEditingController(text: initialValue),
      ),
    );
  }

  void _showTimePicker(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return Container(
          height: 300,
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.grey[850] : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoPicker(
                        backgroundColor: isDarkMode ? Colors.grey[850] : Colors.white,
                        onSelectedItemChanged: (int value) {
                          setState(() {
                            selectedMinutes = value;
                          });
                        },
                        itemExtent: 32.0,
                        children: List<Widget>.generate(60, (int index) {
                          return Center(
                            child: Text('$index min', style: TextStyle(color: isDarkMode ? Colors.white : Colors.black)),
                          );
                        }),
                        scrollController: FixedExtentScrollController(initialItem: selectedMinutes),
                      ),
                    ),
                    SizedBox(width: 5),
                    Expanded(
                      child: CupertinoPicker(
                        backgroundColor: isDarkMode ? Colors.grey[850] : Colors.white,
                        onSelectedItemChanged: (int value) {
                          setState(() {
                            selectedSeconds = value;
                          });
                        },
                        itemExtent: 32.0,
                        children: List<Widget>.generate(60, (int index) {
                          return Center(
                            child: Text('$index s', style: TextStyle(color: isDarkMode ? Colors.white : Colors.black)),
                          );
                        }),
                        scrollController: FixedExtentScrollController(initialItem: selectedSeconds),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                child: Text("Done", style: TextStyle(color: isDarkMode ? Colors.white : Colors.black)),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMcqPicker(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return Container(
          height: 300,
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.grey[850] : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              Expanded(
                child: CupertinoPicker(
                  backgroundColor: isDarkMode ? Colors.grey[850] : Colors.white,
                  onSelectedItemChanged: (int value) {
                    setState(() {
                      mcqCount = (value + 1).toString();
                    });
                  },
                  itemExtent: 32.0,
                  children: List<Widget>.generate(500, (int index) {
                    return Center(
                      child: Text('${index + 1}', style: TextStyle(color: isDarkMode ? Colors.white : Colors.black)),
                    );
                  }),
                  scrollController: FixedExtentScrollController(initialItem: 29),
                ),
              ),
              TextButton(
                child: Text("Done", style: TextStyle(color: isDarkMode ? Colors.white : Colors.black)),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
