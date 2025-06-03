import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../screens/add_players_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/food_screen.dart';
import '../screens/invoice_screen.dart';
import '../screens/profile_drawer.dart';
import '../screens/table_screen.dart';

class MainHomeScreen extends ConsumerStatefulWidget {
  final String clubId;

  const MainHomeScreen({super.key, required this.clubId});

  @override
  _MainHomeScreenState createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends ConsumerState<MainHomeScreen> {
  int _selectedIndex = 0;
  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      DashboardScreen(clubId: widget.clubId),
      FoodScreen(clubId: widget.clubId),
      TableScreen(clubId: widget.clubId),
      AddPlayersScreen(clubId: widget.clubId),
      InvoiceScreen(clubId: widget.clubId),
    ];
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: Image.asset(
          'assets/logo.png',
          height: 30,

        ),
        actions: [
          Builder(
            builder: (BuildContext context) {
              final clubAsync = ref.watch(clubProvider(widget.clubId));
              return clubAsync.when(
                data: (club) {
                  if (club == null) {
                    return const IconButton(
                      icon: Icon(Icons.person),
                      onPressed: null,
                    );
                  }
                  return IconButton(
                    icon: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.red,
                          width: 2,
                        ),
                      ),
                      child: club['logo_url'] != null
                          ? CircleAvatar(
                        backgroundImage: NetworkImage(club['logo_url']),
                        radius: 16,
                      )
                          : const CircleAvatar(
                        backgroundColor: Colors.grey,
                        radius: 16,
                        child: Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    onPressed: () => Scaffold.of(context).openEndDrawer(),
                  );
                },
                loading: () => const CircularProgressIndicator(),
                error: (error, _) {
                  String errorMessage = 'Error loading club';
                  if (error.toString().contains('PERMISSION_DENIED')) {
                    errorMessage = 'Permission denied to access club data';
                  }
                  return IconButton(
                    icon: const Icon(Icons.error),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(errorMessage)),
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
      endDrawer: ProfileDrawer(clubId: widget.clubId),
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: [
          BottomNavigationBarItem(
            icon: Image.asset(
              _selectedIndex == 0 ? 'assets/home.png' : 'assets/home-bw.png',
              height: 28,
              width: 28,
            ),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Image.asset(
              _selectedIndex == 1 ? 'assets/food.png' : 'assets/food-bw.png',
              height: 28,
              width: 28,
            ),
            label: 'Food',
          ),
          BottomNavigationBarItem(
            icon: Image.asset(
              _selectedIndex == 2 ? 'assets/table.png' : 'assets/table-bw.png',
              height: 34,
              width: 34,
            ),
            label: 'Table',
          ),
          BottomNavigationBarItem(
            icon: Image.asset(
              _selectedIndex == 3 ? 'assets/add-player.png' : 'assets/add-player-bw.png',
              height: 28,
              width: 28,
            ),
            label: 'Add Players',
          ),
          BottomNavigationBarItem(
            icon: Image.asset(
              _selectedIndex == 4 ? 'assets/invoice.png' : 'assets/invoice-bw.png',
              height: 28,
              width: 28,
            ),
            label: 'Invoice',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.red,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        type: BottomNavigationBarType.fixed,
        onTap: _onItemTapped,
      ),
    );
  }
}

final clubProvider = StreamProvider.family<Map<String, dynamic>?, String>((ref, clubId) {
  return FirebaseFirestore.instance
      .collection('clubs')
      .doc(clubId)
      .snapshots()
      .map((snapshot) => snapshot.data());
});