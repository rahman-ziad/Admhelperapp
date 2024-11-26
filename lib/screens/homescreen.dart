import 'package:flutter/material.dart';
import 'package:untitled/screens/qbank.dart';
import 'mcq.dart';
import 'written.dart';
import 'todo_main.dart';
import 'history.dart';
import 'ReminderScreen.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:csv/csv.dart';
import 'package:pub_semver/pub_semver.dart';


class HomeScreen extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onThemeChange;

  HomeScreen({required this.isDarkMode, required this.onThemeChange});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hasCheckedForUpdate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_hasCheckedForUpdate) {
      _hasCheckedForUpdate = true;
      checkForUpdate(context); // Runs check only once after widget is fully built
    }
  }

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;
    double buttonWidth = size.width * 0.40;
    double buttonHeight = size.height * 0.22;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
              widget.isDarkMode
                  ? 'Asset/images/bg_dark.png'
                  : 'Asset/images/bg_light.png',
            ),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppBar(
                backgroundColor: widget.isDarkMode
                    ? Colors.transparent
                    : Colors.transparent,
                elevation: 0,
                leading: Builder(
                  builder: (BuildContext context) {
                    return Padding(
                      padding: EdgeInsets.all(10),
                      child: IconButton(
                        icon: Icon(
                          Icons.menu,
                          color: widget.isDarkMode ? Colors.white : Colors.black,
                          size: 35.0,
                        ),
                        onPressed: () {
                          Scaffold.of(context).openDrawer();
                        },
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 5, 0, 0),
                child: Text(
                  'Welcome to,\nAdmission Prep Helper',
                  style: TextStyle(
                    color: widget.isDarkMode ? Colors.white : Colors.black,
                    fontSize: 25.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: Center(
                    child: Wrap(
                      spacing: 16.0,
                      runSpacing: 16.0,
                      children: <Widget>[
                        CustomCard(
                          imageUrl: 'Asset/images/mcq.png',
                          title: 'Mcq',
                          buttonWidth: buttonWidth,
                          buttonHeight: buttonHeight,
                          onTap: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => mcqscreen()));
                          },
                        ),
                        CustomCard(
                          imageUrl: 'Asset/images/written.png',
                          title: 'Written',
                          buttonWidth: buttonWidth,
                          buttonHeight: buttonHeight,
                          onTap: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        writtenscreen()));
                          },
                        ),
                        CustomCard(
                          imageUrl: 'Asset/images/todo_list.png',
                          title: 'To-Do',
                          buttonWidth: buttonWidth,
                          buttonHeight: buttonHeight,
                          onTap: () {
                            Navigator.push(context,
                                MaterialPageRoute(builder: (context) => TodoHomeScreen()));
                          },
                        ),
                        CustomCard(
                          imageUrl: 'Asset/images/qb.png',
                          title: 'Qbank',
                          buttonWidth: buttonWidth,
                          buttonHeight: buttonHeight,
                          onTap: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => qbankScreen()));
                          },
                        ),
                        CustomCard(
                          imageUrl: 'Asset/images/info.png',
                          title: 'Uni Info',
                          buttonWidth: buttonWidth,
                          buttonHeight: buttonHeight,
                          onTap: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => ReminderScreen()));
                          },
                        ),
                        CustomCard(
                          imageUrl: 'Asset/images/history.png',
                          title: 'History',
                          buttonWidth: buttonWidth,
                          buttonHeight: buttonHeight,
                          onTap: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => HistoryScreen()));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            DrawerHeader(
              decoration: BoxDecoration(
                color: widget.isDarkMode ? const Color(0xFF0A7075) : Color(0xFF9BC7D0),
              ),
              child: Text(
                'Menu',
                style: TextStyle(
                  color: widget.isDarkMode? Colors.white : Colors.black,
                  fontSize: 24,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.home),
              title: Text('Home'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),

            ListTile(
              leading: Icon(Icons.update),
              title: Text('Check for updates'),
              onTap: () {
                Navigator.pop(context); // Close the drawer first
                checkForUpdate(context); // Then check for update
              },
            ),

            SwitchListTile(
              title: Text('Dark Mode'),
              value: widget.isDarkMode,
              onChanged: (bool value) {
                widget.onThemeChange(value);
              },
              secondary: Icon(
                widget.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                color: widget.isDarkMode ? Colors.white : Colors.black, // Icon color adjustment based on theme
              ),
              activeColor: widget.isDarkMode
                  ? const Color(0xFFFFC107) // Amber for active color in Dark Mode
                  : const Color(0xFF00B0FF), // Bright Blue for active color in Light Mode
              // Adjust the text color based on the mode

            ),

            ListTile(
              leading: Icon(Icons.favorite),
              title: Text('Support Us'),
              onTap: () async {
                const url = 'https://appgrids-free-app-landing-page-template.vercel.app/#supportus'; // Replace with your actual support link
                if (await canLaunch(url)) {
                  await launch(url);
                } else {
                  throw 'Could not launch $url';
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class CustomCard extends StatelessWidget {
  final String imageUrl; // This will now represent the asset image path
  final String title;
  final double buttonWidth;
  final double buttonHeight;
  final VoidCallback onTap;

  CustomCard({
    required this.imageUrl, // Pass the asset image path here
    required this.title,
    required this.buttonWidth,
    required this.buttonHeight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: buttonWidth,
      height: buttonHeight,
      child: Card(
        elevation: 5.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.0), // Match the card's border radius
          child: InkWell(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15.0), // Match the card's border radius
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Image.asset(
                    imageUrl, // Use Image.asset to load the image from assets
                    width: 75.0,
                    height: 75.0,
                  ),
                  SizedBox(height: 10.0),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
Future<void> checkForUpdate(BuildContext context) async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    print("Current Version: $currentVersion");

    // Validate current version
    if (currentVersion == null || currentVersion.isEmpty) {
      print("Current version is null or empty.");
      return; // No valid current version available
    }

    // Define the URL and add a cache-busting parameter (optional but recommended)
    final url = 'https://raw.githubusercontent.com/rahman-ziad/appdata/refs/heads/main/appv.csv?${DateTime.now().millisecondsSinceEpoch}';

    // Make the HTTP request with Cache-Control header to prevent caching
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Cache-Control': 'no-cache', // Disable caching of the response
      },
    );

    if (response.statusCode == 200) {
      // Convert the CSV response into a list of lists
      final csv = const CsvToListConverter().convert(response.body);

      // Ensure the CSV is not empty and has the expected format
      if (csv.isEmpty || csv[0].length < 2 || csv[0][0] == null || csv[0][1] == null) {
        print("Invalid or empty version data in CSV.");
        return; // No valid version data found in the CSV
      }

      final latestVersion = csv[0][0]; // Latest version is in the first column
      final apkUrl = csv[0][1]; // APK URL is in the second column

      print("Latest Version from CSV: $latestVersion");

      // Ensure latestVersion is not null or empty
      if (latestVersion == null || latestVersion.isEmpty) {
        print("Latest version in CSV is null or empty.");
        return; // Don't proceed further if there's no valid latest version
      }

      // Compare versions using pub_semver package
      try {
        Version latestVersionParsed = Version.parse(latestVersion);
        Version currentVersionParsed = Version.parse(currentVersion);

        if (latestVersionParsed > currentVersionParsed) {
          if (apkUrl == null || apkUrl.isEmpty) {
            print("APK URL is missing or empty, no update link available.");
            return; // Don't show the update dialog if there's no APK URL
          }

          // Show update dialog if versions differ and APK URL is valid
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text("Update Available"),
                content: Text("A new version is available. Please update the app."),
                actions: <Widget>[
                  TextButton(
                    child: Text("Update"),
                    onPressed: () async {
                      // Close the dialog first before launching the APK
                      Navigator.of(context).pop();

                      // Launch the APK URL after the dialog is closed
                      if (await canLaunch(apkUrl)) {
                        await launch(apkUrl); // Open the APK URL
                      } else {
                        throw 'Could not launch $apkUrl';
                      }
                    },
                  ),
                  TextButton(
                    child: Text("Cancel"),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              );
            },
          );
        } else {
          // If the versions are the same, show a "You are up to date" message only when the user manually checks
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("You are up to date!"),
              duration: Duration(seconds: 2), // Show for 2 seconds
            ),
          );
        }
      } catch (e) {
        print("Error parsing version: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error parsing version information."),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      print("Failed to fetch version data.");
      // Show error message if data fetch fails
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to check for updates. Please try again later."),
          duration: Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    print("Error: $e");
    // Show error message in case of an exception
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("An error occurred while checking for updates."),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

