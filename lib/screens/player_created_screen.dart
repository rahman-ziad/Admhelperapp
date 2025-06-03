import 'package:flutter/material.dart';
import 'main_home_screen.dart';

class PlayerCreatedScreen extends StatelessWidget {
  final String clubId;

  const PlayerCreatedScreen({super.key, required this.clubId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Player Created'),
        automaticallyImplyLeading: false, // Remove default back button
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 100),
            const SizedBox(height: 16),
            const Text(
              'Player Created Successfully!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MainHomeScreen(clubId: clubId),
                  ),
                      (route) => false, // Clear stack to prevent going back to AddPlayersScreen
                );
              },
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}