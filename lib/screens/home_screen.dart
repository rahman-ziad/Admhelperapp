import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../screens/main_home_screen.dart';
import '../screens/profile_setup_screen.dart';
import 'login_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const LoginScreen();

    final profileAsync = ref.watch(userProfileProvider(user.uid));
    return profileAsync.when(
      data: (profile) {
        // If profile doesn't exist or isProfileSetup is false, show ProfileSetupScreen
        if (profile == null || !profile.isProfileSetup) {
          return const ProfileSetupScreen();
        }
        return MainHomeScreen(clubId: profile.clubId);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }
}

final userProfileProvider = FutureProvider.family<UserProfile?, String>((ref, uid) async {
  final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
  return doc.exists ? UserProfile.fromMap(doc.data()!) : null;
});

class UserProfile {
  final String name;
  final String clubId;
  final bool isProfileSetup; // New field

  UserProfile({required this.name, required this.clubId, required this.isProfileSetup});

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      name: map['name'] ?? '',
      clubId: map['club_id'] ?? '',
      isProfileSetup: map['isProfileSetup'] ?? false, // Default to false if not set
    );
  }
}