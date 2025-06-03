import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shimmer_animation/shimmer_animation.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'edit_discount_codes.dart';
import 'edit_table_screen.dart';

class CreateDiscountCodeScreen extends StatefulWidget {
  final String clubId;

  const CreateDiscountCodeScreen({super.key, required this.clubId});

  @override
  _CreateDiscountCodeScreenState createState() => _CreateDiscountCodeScreenState();
}

class _CreateDiscountCodeScreenState extends State<CreateDiscountCodeScreen> {
  final _codeController = TextEditingController();
  final _discountValueController = TextEditingController();
  TimeOfDay? startTime;
  TimeOfDay? endTime;
  bool isTimeRestricted = true;
  List<String> selectedPlayers = [];
  Map<String, String> playerNames = {};
  final TextEditingController searchController = TextEditingController();
  List<Map<String, dynamic>> filteredPlayers = [];
  late List<Map<String, dynamic>> allPlayers;
  bool isAllSelected = false;
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _fetchPlayers();
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Future<void> _fetchPlayers() async {
    try {
      final playersSnapshot = await FirebaseFirestore.instance.collection('players').get();
      for (var doc in playersSnapshot.docs) {
        playerNames[doc.id] = doc.data()['name'] as String? ?? 'Unknown';
      }
      allPlayers = playersSnapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      filteredPlayers = allPlayers;
      setState(() {});
    } catch (e) {
      print('Error fetching players: $e');
    }
  }

  Future<void> _selectTime(BuildContext context, bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) startTime = picked;
        else endTime = picked;
      });
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    if (_codeController.text.isEmpty || _discountValueController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    if (isTimeRestricted && (startTime == null || endTime == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select start and end times')),
      );
      return;
    }

    if (!isAllSelected && selectedPlayers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one player or "All"')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not authenticated')),
        );
        return;
      }

      final clubDoc = await FirebaseFirestore.instance.collection('clubs').doc(widget.clubId).get();
      if (!clubDoc.exists || clubDoc['admin_id'] != user.uid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only club admins can create discount codes')),
        );
        return;
      }

      final discountValue = double.tryParse(_discountValueController.text) ?? 0.0;
      if (discountValue <= 0 || discountValue > 100) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Discount value must be between 0 and 100')),
        );
        return;
      }

      await FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .collection('discount_codes')
          .doc(_codeController.text)
          .set({
        'code': _codeController.text,
        'discount_value': discountValue,
        'assigned_players': isAllSelected ? [] : selectedPlayers,
        'applies_to_all': isAllSelected,
        'start_time': isTimeRestricted
            ? DateFormat('HH:mm').format(DateTime(0, 1, 1, startTime!.hour, startTime!.minute))
            : null,
        'end_time': isTimeRestricted
            ? DateFormat('HH:mm').format(DateTime(0, 1, 1, endTime!.hour, endTime!.minute))
            : null,
        'is_time_restricted': isTimeRestricted,
        'created_at': Timestamp.now(),
        'is_active': true,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Discount code created successfully')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Discount Code'),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search Player (IGN/Name/Phone)',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (value) {
                    final query = value.trim().toLowerCase();
                    setState(() {
                      filteredPlayers = allPlayers.where((player) {
                        return (player['name']?.toLowerCase().contains(query) ?? false) ||
                            (player['phone_number']?.toLowerCase().contains(query) ?? false) ||
                            (player['ign']?.toLowerCase().contains(query) ?? false);
                      }).toList();
                    });
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 90,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            isAllSelected = !isAllSelected;
                            if (isAllSelected) selectedPlayers.clear();
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Column(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isAllSelected ? Colors.red : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: const CircleAvatar(
                                  radius: 28,
                                  child: Text('All', style: TextStyle(fontSize: 16)),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'All Players',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isAllSelected ? Colors.red : Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ...filteredPlayers.map((player) {
                        final isSelected = selectedPlayers.contains(player['id']);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isAllSelected) {
                                isAllSelected = false;
                                selectedPlayers.clear();
                              }
                              if (isSelected) {
                                selectedPlayers.remove(player['id']);
                              } else {
                                selectedPlayers.add(player['id']);
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Column(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? Colors.red : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    radius: 28,
                                    backgroundImage: player['image_url'] != null
                                        ? NetworkImage(player['image_url'])
                                        : null,
                                    child: player['image_url'] == null
                                        ? const Icon(Icons.person, size: 28)
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  (player['ign'] ?? player['name'] ?? 'Unknown').length > 8
                                      ? '${(player['ign'] ?? player['name'] ?? 'Unknown').substring(0, 8)}...'
                                      : player['ign'] ?? player['name'] ?? 'Unknown',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isSelected ? Colors.red : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _codeController,
                          decoration: const InputDecoration(labelText: 'Discount Code Name'),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _discountValueController,
                          decoration: const InputDecoration(labelText: 'Discount Percentage'),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          title: const Text('Time Restricted'),
                          value: isTimeRestricted,
                          activeColor: Colors.redAccent,
                          onChanged: (value) {
                            setState(() {
                              isTimeRestricted = value;
                              if (!isTimeRestricted) {
                                startTime = null;
                                endTime = null;
                              }
                            });
                          },
                        ),
                        if (isTimeRestricted) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _selectTime(context, true),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      startTime == null
                                          ? 'Select Start Time'
                                          : DateFormat('hh:mm a').format(
                                          DateTime(0, 1, 1, startTime!.hour, startTime!.minute)),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _selectTime(context, false),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      endTime == null
                                          ? 'Select End Time'
                                          : DateFormat('hh:mm a').format(
                                          DateTime(0, 1, 1, endTime!.hour, endTime!.minute)),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: _isSubmitting
                        ? LoadingAnimationWidget.staggeredDotsWave(
                        color: Colors.white, size: 24)
                        : const Text(
                      'Create Discount Code',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading)
            Shimmer(
              color: Colors.grey[300]!,
              child: Container(
                color: Colors.grey[200],
              ),
            ),
        ],
      ),
    );
  }
}