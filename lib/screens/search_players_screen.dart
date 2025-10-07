import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'edit_player_screen.dart';

class SearchPlayersScreen extends StatefulWidget {
  final String clubId;

  const SearchPlayersScreen({super.key, required this.clubId});

  @override
  _SearchPlayersScreenState createState() => _SearchPlayersScreenState();
}

class _SearchPlayersScreenState extends State<SearchPlayersScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredPlayers = [];
  List<Map<String, dynamic>> _allPlayers = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_searchPlayers);
    _loadAllPlayers();
  }

  Future<void> _loadAllPlayers() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('players').get();
      setState(() {
        _allPlayers = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
        _filteredPlayers = _allPlayers;
      });
    } catch (e) {
      print('Error loading players: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading players: $e')),
        );
      }
    }
  }

  Future<void> _searchPlayers() async {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredPlayers = _allPlayers.where((player) {
        return (player['name']?.toLowerCase().contains(query) ?? false) ||
            (player['phone_number']?.toLowerCase().contains(query) ?? false) ||
            (player['in_game_name']?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search Players')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by Name, IGN, or Phone',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (_) => _searchPlayers(),
            ),
          ),
          Expanded(
            child: _filteredPlayers.isEmpty
                ? const Center(child: Text('No players found'))
                : ListView.builder(
              itemCount: _filteredPlayers.length,
              itemBuilder: (context, index) {
                final player = _filteredPlayers[index];
                final playerName = player['name'] ?? 'Unknown';
                final playerIGN = player['in_game_name'] ?? 'N/A';
                final playerPhone = player['phone_number'] ?? 'N/A';
                final photoUrl = player['image_url'] ?? '';
                final nameAndIGN = '$playerName ($playerIGN)';
                final truncatedNameAndIGN = nameAndIGN.length > 20
                    ? '${nameAndIGN.substring(0, 17)}...'
                    : nameAndIGN;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                  child: GestureDetector(
                    onTap: () {
                      try {
                        Navigator.pop(context);
                      } catch (e) {
                        print('Error navigating back: $e');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    },
                    child: Container(
                      height: 90,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          photoUrl.isNotEmpty
                              ? CircleAvatar(
                            radius: 30,
                            backgroundImage: NetworkImage(photoUrl),
                          )
                              : CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.blue.shade200,
                            child: Text(
                              playerName.isNotEmpty ? playerName[0].toUpperCase() : '?',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  truncatedNameAndIGN,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                ),
                                Text(
                                  playerPhone,
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EditPlayerScreen(
                                  clubId: widget.clubId,
                                  player: player,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}