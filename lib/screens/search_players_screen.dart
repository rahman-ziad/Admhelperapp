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
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by Name, Phone, or IGN',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: _filteredPlayers.isEmpty
                ? const Center(child: Text('No players found'))
                : ListView.builder(
              itemCount: _filteredPlayers.length,
              itemBuilder: (context, index) {
                final player = _filteredPlayers[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: player['image_url'] != null
                        ? CircleAvatar(
                      backgroundImage: NetworkImage(player['image_url']),
                      radius: 20,
                    )
                        : const Icon(Icons.person, size: 40),
                    title: Text(
                      '${player['name'] ?? 'Unknown'} (${player['in_game_name'] ?? 'N/A'})',
                    ),
                    subtitle: Text('Phone: ${player['phone_number'] ?? 'N/A'}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                        const Icon(Icons.check),
                      ],
                    ),
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