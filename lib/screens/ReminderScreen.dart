import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';

class ReminderScreen extends StatefulWidget {
  @override
  _ReminderScreenState createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> with SingleTickerProviderStateMixin {
  bool isDarkMode = false;
  late TabController _tabController;
  List<Map<String, dynamic>> universityData = [];
  List<Map<String, dynamic>> registrationData = [];
  List<Map<String, dynamic>> resultData = [];
  DateTime currentDate = DateTime.now();
  bool isLoadingExam = true;
  bool isLoadingReg = true;
  bool isLoadingResult = true;
  late NativeAd nativeAd;
  bool isNativeAdLoaded = false;
  late NativeAd nativeAd1;
  bool isNativeAdLoaded1 = false;
  late NativeAd nativeAd2;
  bool isNativeAdLoaded2 = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _tabController = TabController(length: 3, vsync: this);
    _loadUniversityData();  // Load exam date data
    _loadRegistrationData(); // Load registration data
    _loadResultData(); // Load result data
    _loadNativeAd();
  }
  void _loadNativeAd() {
    nativeAd = NativeAd(
      adUnitId: 'ca-app-pub-2413088365868094/2309147374', // Replace with your AdMob unit ID
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          setState(() {
            isNativeAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          print('Native Ad Failed to Load: $error');
          ad.dispose();
        },
      ),
        request: const AdRequest(),
        nativeTemplateStyle: NativeTemplateStyle(templateType: TemplateType.small));
    nativeAd!.load();

    nativeAd1 = NativeAd(
        adUnitId: 'ca-app-pub-2413088365868094/5793930966', // Replace with your AdMob unit ID
        listener: NativeAdListener(
          onAdLoaded: (ad) {
            setState(() {
              isNativeAdLoaded1 = true;
            });
          },
          onAdFailedToLoad: (ad, error) {
            print('Native Ad 1 Failed to Load: $error');
            ad.dispose();
          },
        ),
        request: const AdRequest(),
        nativeTemplateStyle: NativeTemplateStyle(templateType: TemplateType.small));
    nativeAd1!.load();

    nativeAd2 = NativeAd(
        adUnitId: 'ca-app-pub-2413088365868094/4480849296', // Replace with your AdMob unit ID
        listener: NativeAdListener(
          onAdLoaded: (ad) {
            setState(() {
              isNativeAdLoaded2 = true;
            });
          },
          onAdFailedToLoad: (ad, error) {
            print('Native Ad 2 Failed to Load: $error');
            ad.dispose();
          },
        ),
        request: const AdRequest(),
        nativeTemplateStyle: NativeTemplateStyle(templateType: TemplateType.small));
    nativeAd2!.load();
  }
  @override
  void dispose() {
    nativeAd.dispose();
    nativeAd1.dispose();
    nativeAd2.dispose();
    super.dispose();
  }
  void _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  void _loadUniversityData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('universityData');

      if (cachedData != null) {
        // Use cached data if available
        setState(() {
          universityData = List<Map<String, dynamic>>.from(json.decode(cachedData));
          isLoadingExam = false;
        });
      }

      // Fetch the data from the server
      final response = await http.get(Uri.parse(
          'https://raw.githubusercontent.com/rahman-ziad/appdata/refs/heads/main/university%20exam%20date%20-%20Sheet1.csv'));

      if (response.statusCode == 200) {
        List<String> lines = const LineSplitter().convert(response.body);
        List<Map<String, dynamic>> loadedData = [];
        for (var i = 1; i < lines.length; i++) {
          List<String> values = lines[i].split(',');
          Map<String, dynamic> entry = {
            'Image URL': values[0],
            'University Name': values[1],
            'Exam Date': values[2],
            'Link': values[3]
          };
          loadedData.add(entry);
        }

        // Cache the fetched data
        await prefs.setString('universityData', json.encode(loadedData));

        setState(() {
          universityData = loadedData;
          isLoadingExam = false;
        });
      } else {
        throw Exception('Failed to load university data');
      }
    } catch (e) {
      setState(() {
        isLoadingExam = false;
      });
      _showErrorDialog();
    }
  }

  void _loadRegistrationData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('registrationData');

      if (cachedData != null) {
        // Use cached data if available
        setState(() {
          registrationData = List<Map<String, dynamic>>.from(json.decode(cachedData));
          isLoadingReg = false;
        });
      }

      // Fetch the data from the server
      final response = await http.get(Uri.parse(
          'https://raw.githubusercontent.com/rahman-ziad/appdata/refs/heads/main/reg.csv'));

      if (response.statusCode == 200) {
        List<String> lines = const LineSplitter().convert(response.body);
        List<Map<String, dynamic>> loadedData = [];
        for (var i = 1; i < lines.length; i++) {
          List<String> values = lines[i].split(',');
          Map<String, dynamic> entry = {
            'Image URL': values[0],
            'University Name': values[1],
            'Registration Start': values[2],
            'Registration End': values[3],
            'Link': values[4]
          };
          loadedData.add(entry);
        }

        // Cache the fetched data
        await prefs.setString('registrationData', json.encode(loadedData));

        setState(() {
          registrationData = loadedData;
          isLoadingReg = false;
        });
      } else {
        throw Exception('Failed to load registration data');
      }
    } catch (e) {
      setState(() {
        isLoadingReg = false;
      });
      _showErrorDialog();
    }
  }

  void _loadResultData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('resultData');

      if (cachedData != null) {
        // Use cached data if available
        setState(() {
          resultData = List<Map<String, dynamic>>.from(json.decode(cachedData));
          isLoadingResult = false;
        });
      }

      // Fetch the data from the server
      final response = await http.get(Uri.parse(
          'https://raw.githubusercontent.com/rahman-ziad/appdata/refs/heads/main/result.csv'));

      if (response.statusCode == 200) {
        List<String> lines = const LineSplitter().convert(response.body);
        List<Map<String, dynamic>> loadedData = [];
        for (var i = 1; i < lines.length; i++) {
          List<String> values = lines[i].split(',');
          Map<String, dynamic> entry = {
            'Image URL': values[0],
            'University Name': values[1],
            'Result Date': values[2],
            'Link': values[3]
          };
          loadedData.add(entry);
        }

        // Cache the fetched data
        await prefs.setString('resultData', json.encode(loadedData));

        setState(() {
          resultData = loadedData;
          isLoadingResult = false;
        });
      } else {
        throw Exception('Failed to load result data');
      }
    } catch (e) {
      setState(() {
        isLoadingResult = false;
      });
      _showErrorDialog();
    }
  }



  void _showErrorDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Error'),
          content: Text('Failed to load data. Please try again later.'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  String _calculateTimeRemaining(String startDate, [String? endDate]) {
    DateTime start = DateTime.parse(startDate);
    DateTime now = DateTime.now();

    // If end date is provided (for registration), calculate for registration
    if (endDate != null) {
      DateTime end = DateTime.parse(endDate);
      if (now.isBefore(start)) {
        return "Registration Not Started";
      } else if (now.isBefore(end.add(Duration(days: 1)))) { // Include the end date
        return "Registration Ongoing";
      } else {
        return "Registration Closed";
      }
    }

    // Otherwise, for exam date, calculate time remaining
    Duration difference = start.difference(now);
    if (difference.isNegative) {
      return "Exam Passed";
    } else {
      return "${difference.inDays} days";
    }
  }

  @override
  Widget build(BuildContext context) {
    Color appBarColor = isDarkMode ? const Color(0xFF0A7075) : Color(0xFF9BC7D0);
    Color textColor = isDarkMode ? Colors.white : Colors.black;
    Color subTextColor = isDarkMode ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.6);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "University Info",
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        backgroundColor: appBarColor,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Exam Date'),
            Tab(text: 'Registration'),
            Tab(text: 'Result'),
          ],
          indicatorColor: isDarkMode ? Color(0xFFFF4081) : Color(0xFF4CAF50),
          labelColor: isDarkMode ? Colors.white : Colors.black,
          unselectedLabelColor: isDarkMode ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.7),
        ),
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
          child: TabBarView(
            controller: _tabController,
            children: [
              // Exam Date Tab
              Center(
                child: isLoadingExam
                    ? CircularProgressIndicator()
                    : universityData.isNotEmpty
                    ? ListView.builder(
                  itemCount: universityData.length + (isNativeAdLoaded ? 1: 0),
                  itemBuilder: (context, index) {
                    if (isNativeAdLoaded && index == 4) {
                      return Container(
                        height: 100, // Adjust height as per your design
                        margin: EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                        decoration: BoxDecoration(
                          color: Colors.white, // Background color (optional)
                          borderRadius: BorderRadius.circular(12), // Rounded corners
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.3),
                              blurRadius: 4,
                              offset: Offset(0, 4), // Shadow offset
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12), // Same as Container's borderRadius
                          child: AdWidget(ad: nativeAd),
                        ),
                      );
                    }


                    // Adjust index for data list when ad is inserted

                    final adjustedIndex =
                    (isNativeAdLoaded && index > 4 && index < universityData.length + 1)
                        ? index - 1
                        : index;

                    final university = universityData[adjustedIndex];
                    return Card(
                      margin: EdgeInsets.all(8.0),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.all(12),
                        leading: university['Image URL'] != null
                            ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 50,
                            height: 50,
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: Image.network(
                                university['Image URL'],
                              ),
                            ),
                          ),
                        )
                            : null,
                        title: Text(
                          university['University Name'],
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Exam Date: ${university['Exam Date']}',
                              style: TextStyle(color: subTextColor),
                            ),
                            Text(
                              'Time Remaining: ${_calculateTimeRemaining(university['Exam Date'])}',
                              style: TextStyle(color: subTextColor),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.open_in_browser,
                            color: textColor,
                            size: 24,
                          ),
                          onPressed: () {
                            // Check if the link is available or not
                            final link = university['Link'];
                            if (link == null || link.isEmpty) {
                              // Call the dialog if no link is found
                              _showNoLinkDialog();
                            } else {
                              // Launch the URL if a link is found
                              _launchURL(link);
                            }
                          },
                        ),
                      ),
                    );
                  },
                )
                    : Center(
                  child: Text(
                    'No university data available.',
                    style: TextStyle(color: textColor),
                  ),
                ),
              ),

              // Registration Tab
              Center(
                child: isLoadingReg
                    ? CircularProgressIndicator()
                    : registrationData.isNotEmpty
                    ? ListView.builder(
                  itemCount: registrationData.length + (isNativeAdLoaded1 ? 1 : 0),
                  itemBuilder: (context, index) {

                    if (isNativeAdLoaded1 && index == 4) {
                      return Container(
                        height: 100, // Adjust height as per your design
                        margin: EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                        decoration: BoxDecoration(
                          color: Colors.white, // Background color (optional)
                          borderRadius: BorderRadius.circular(12), // Rounded corners
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.3),
                              blurRadius: 4,
                              offset: Offset(0, 4), // Shadow offset
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12), // Same as Container's borderRadius
                          child: AdWidget(ad: nativeAd1),
                        ),
                      );
                    }

                    final adjustedIndex =
                    (isNativeAdLoaded && index > 4 && index < registrationData.length + 1)
                        ? index - 1
                        : index;

                    final registration = registrationData[adjustedIndex];
                    return Card(
                      margin: EdgeInsets.all(8.0),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.all(12),
                        leading: registration['Image URL'] != null
                            ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 50,
                            height: 50,
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: Image.network(
                                registration['Image URL'],
                              ),
                            ),
                          ),
                        )
                            : null,
                        title: Text(
                          registration['University Name'],
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Registration Start: ${registration['Registration Start']}',
                              style: TextStyle(color: subTextColor),
                            ),
                            Text(
                              'Registration End: ${registration['Registration End']}',
                              style: TextStyle(color: subTextColor),
                            ),
                            Text(
                              'Status: ${_calculateTimeRemaining(registration['Registration Start'], registration['Registration End'])}',
                              style: TextStyle(color: subTextColor),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.open_in_browser,
                            color: textColor,
                            size: 24,
                          ),
                          onPressed: () {
                            // Check if the link is available or not
                            final link = registration['Link'];
                            if (link == null || link.isEmpty) {
                              // Call the dialog if no link is found
                              _showNoLinkDialog();
                            } else {
                              // Launch the URL if a link is found
                              _launchURL(link);
                            }
                          },
                        ),
                      ),
                    );
                  },
                )
                    : Center(
                  child: Text(
                    'No registration data available.',
                    style: TextStyle(color: textColor),
                  ),
                ),
              ),

              // Result Tab
              Center(
                child: isLoadingResult
                    ? CircularProgressIndicator()
                    : resultData.isNotEmpty
                    ? ListView.builder(
                  itemCount: resultData.length + (isNativeAdLoaded2 ? 1:0),
                  itemBuilder: (context, index) {
                    if (isNativeAdLoaded2 && index == 4) {
                      return Container(
                        height: 100, // Adjust height as per your design
                        margin: EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                        decoration: BoxDecoration(
                          color: Colors.white, // Background color (optional)
                          borderRadius: BorderRadius.circular(12), // Rounded corners
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.3),
                              blurRadius: 4,
                              offset: Offset(0, 4), // Shadow offset
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12), // Same as Container's borderRadius
                          child: AdWidget(ad: nativeAd2),
                        ),
                      );
                    }
                    final adjustedIndex =
                    (isNativeAdLoaded && index > 4 && index < resultData.length + 1)
                    ? index - 1
                        : index;

                    final result = resultData[adjustedIndex];
                    return Card(
                      margin: EdgeInsets.all(8.0),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.all(12),
                        leading: result['Image URL'] != null
                            ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 50,
                            height: 50,
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: Image.network(
                                result['Image URL'],
                              ),
                            ),
                          ),
                        )
                            : null,
                        title: Text(
                          result['University Name'],
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              result['Result Date'] != null
                                  ? 'Result Date: ${result['Result Date']}'
                                  : 'Result Date: Not Published',
                              style: TextStyle(color: subTextColor),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.open_in_browser,
                            color: textColor,
                            size: 24,
                          ),
                          onPressed: () {
                            if (result['Link'] != null && result['Link'] != '') {
                              _launchURL(result['Link']);
                            } else {
                              _showNoLinkDialog();
                            }
                          },
                        ),
                      ),
                    );
                  },
                )
                    : Center(
                  child: Text(
                    'No result data available.',
                    style: TextStyle(color: textColor),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  void _showNoLinkDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('No Associated Link Available'),
          content: Text('There is no link available for this university right now.'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('OK',
              style: TextStyle(
                color: Colors.blueAccent,
              ),),
            ),
          ],
        );
      },
    );
  }
}

Future<void> _launchURL(String url) async {
  final Uri uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  } else {
    throw 'Could not launch $url';
  }
}
