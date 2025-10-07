import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_wrapper.dart';
import 'edit_discount_codes.dart';
import 'edit_profile_screen.dart';
import 'dashboard_screen.dart'; // For AddFoodItemScreen, EditTableScreen, CreateDiscountCodeScreen, EditDiscountCodesScreen
import 'edit_table_screen.dart';
import 'home_screen.dart'; // For userProfileProvider
import 'create_discount_code.dart';
import 'add_food_items.dart';
import 'report.dart';
class ProfileDrawer extends ConsumerWidget {
  final String clubId;

  const ProfileDrawer({super.key, required this.clubId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Drawer(
        child: Center(child: Text('User not logged in')),
      );
    }

    final profileAsync = ref.watch(userProfileProvider(user.uid));
    return Drawer(
      child: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Profile not found'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      ref.refresh(userProfileProvider(user.uid));
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          return ListView(
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(color: Colors.redAccent),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: const TextStyle(color: Colors.white, fontSize: 20),
                    ),
                    Text(
                      user.email ?? '',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit Profile'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditProfileScreen(clubId: clubId),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.fastfood),
                title: const Text('Add Food Item'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddFoodItemScreen(clubId: clubId),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.table_restaurant_sharp),
                title: const Text('Edit Table'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditTableScreen(clubId: clubId),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_add),
                title: const Text('Add Employees'),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Feature coming soon')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.discount),
                title: const Text('Create Discount Code'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreateDiscountCodeScreen(clubId: clubId),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit Discount Codes'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditDiscountCodesScreen(clubId: clubId),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.newspaper_rounded),
                title: const Text('Reports'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReportScreen(clubId: clubId),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  ref.refresh(authStateProvider);
                  ref.refresh(userProfileProvider(user.uid));
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthWrapper()),
                  );
                },
              ),

            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          String errorMessage = 'Error: $error';
          if (error.toString().contains('PERMISSION_DENIED')) {
            errorMessage = 'Permission denied. Please check your access rights.';
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(errorMessage),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    ref.refresh(userProfileProvider(user.uid));
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

