import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

class qbankScreen extends StatefulWidget {
  @override
  _qbankScreenState createState() => _qbankScreenState();
}

class _qbankScreenState extends State<qbankScreen> {
  bool isDarkMode = false; // Initialize dark mode
  late BannerAd _bannerAd;
  bool _isBannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadTheme(); // Load the saved theme
    _loadBannerAd(); // Load the banner ad
  }

  @override
  void dispose() {
    _bannerAd.dispose();
    super.dispose();
  }

  // Function to load the saved theme from shared preferences
  void _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  // Function to load the banner ad
  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-2413088365868094/1620179404', // Test ad unit ID
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: Text(
                  'Question Bank',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: Center(
                    child: _buildContent(),
                  ),
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
      ),
    );
  }

  // Method to build the specific content of this question bank screen
  Widget _buildContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Card(
          color: isDarkMode ? Colors.black54 : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Lottie.asset(
                  'Asset/images/underdev.json', // Add your Lottie file here
                  height: 100,
                  width: 100,
                ),
                SizedBox(height: 10),
                Text(
                  'This section of the app is still under development.',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); // Navigate back
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDarkMode ? Color(0xff0a7075) : Color(0xFF0BC8EE),
                    foregroundColor: Colors.white,
                  ),
                  child: Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
