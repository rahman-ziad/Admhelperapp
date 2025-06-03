import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shimmer_animation/shimmer_animation.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class EditDiscountCodesScreen extends StatefulWidget {
  final String clubId;

  const EditDiscountCodesScreen({super.key, required this.clubId});

  @override
  _EditDiscountCodesScreenState createState() => _EditDiscountCodesScreenState();
}

class _EditDiscountCodesScreenState extends State<EditDiscountCodesScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit Discount Codes'),
          bottom: const TabBar(
            labelColor: Colors.red,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.redAccent,
            tabs: [
              Tab(text: 'General'),
              Tab(text: 'Player-wise'),
              Tab(text: 'All'),
            ],
          ),
        ),
        body: Stack(
          children: [
            TabBarView(
              children: [
                DiscountCodeListView(
                  clubId: widget.clubId,
                  filter: (data) => data['applies_to_all'] == true,
                ),
                DiscountCodeListView(
                  clubId: widget.clubId,
                  filter: (data) => data['applies_to_all'] == false,
                ),
                DiscountCodeListView(
                  clubId: widget.clubId,
                  filter: (data) => true,
                ),
              ],
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
      ),
    );
  }
}

class DiscountCodeListView extends StatefulWidget {
  final String clubId;
  final bool Function(Map<String, dynamic>) filter;

  const DiscountCodeListView({
    super.key,
    required this.clubId,
    required this.filter,
  });

  @override
  _DiscountCodeListViewState createState() => _DiscountCodeListViewState();
}

class _DiscountCodeListViewState extends State<DiscountCodeListView> {
  List<QueryDocumentSnapshot> _cachedDiscountCodes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDiscountCodes();
  }

  Future<void> _fetchDiscountCodes() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .collection('discount_codes')
          .get();
      if (mounted) {
        setState(() {
          _cachedDiscountCodes = snapshot.docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching discount codes: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('clubs')
              .doc(widget.clubId)
              .collection('discount_codes')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && _cachedDiscountCodes.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            // Update cache with new data if available
            if (snapshot.hasData) {
              _cachedDiscountCodes = snapshot.data!.docs;
            }

            if (_cachedDiscountCodes.isEmpty) {
              return const Center(child: Text('No discount codes found'));
            }

            final discountCodes = _cachedDiscountCodes
                .where((doc) => widget.filter(doc.data() as Map<String, dynamic>))
                .toList();

            if (discountCodes.isEmpty) {
              return const Center(child: Text('No discount codes in this category'));
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: discountCodes.length,
              itemBuilder: (context, index) {
                final codeData = discountCodes[index].data() as Map<String, dynamic>;
                final codeId = discountCodes[index].id;
                final appliesToAll = codeData['applies_to_all'] ?? false;
                final isActive = codeData['is_active'] ?? true;
                final isTimeRestricted = codeData['is_time_restricted'] ?? false;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    title: Text(
                      codeData['code'] ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Discount: ${codeData['discount_value']}%'),
                        Text(
                          appliesToAll ? 'Applies to: All Players' : 'Applies to: Specific Players',
                        ),
                        if (isTimeRestricted)
                          Text(
                            'Time: ${codeData['start_time'] ?? 'N/A'} - ${codeData['end_time'] ?? 'N/A'}',
                          )
                        else
                          const Text('Time: All Day'),
                        Text(
                          'Status: ${isActive ? 'Active' : 'Inactive'}',
                          style: TextStyle(
                            color: isActive ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit, color: Colors.red),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EditDiscountCodeDetailScreen(
                              clubId: widget.clubId,
                              discountCodeId: codeId,
                              initialData: codeData,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
        if (_isLoading)
          Shimmer(
            color: Colors.grey[300]!,
            child: Container(
              color: Colors.grey[200],
            ),
          ),
      ],
    );
  }
}

class EditDiscountCodeDetailScreen extends StatefulWidget {
  final String clubId;
  final String discountCodeId;
  final Map<String, dynamic> initialData;

  const EditDiscountCodeDetailScreen({
    super.key,
    required this.clubId,
    required this.discountCodeId,
    required this.initialData,
  });

  @override
  _EditDiscountCodeDetailScreenState createState() => _EditDiscountCodeDetailScreenState();
}

class _EditDiscountCodeDetailScreenState extends State<EditDiscountCodeDetailScreen> {
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
  bool isActive = true;
  bool _isSubmitting = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeFields();
    _fetchPlayers();
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _initializeFields() {
    _codeController.text = widget.initialData['code'] ?? '';
    _discountValueController.text = widget.initialData['discount_value']?.toString() ?? '';
    isTimeRestricted = widget.initialData['is_time_restricted'] ?? false;
    startTime = _parseTime(widget.initialData['start_time']);
    endTime = _parseTime(widget.initialData['end_time']);
    isAllSelected = widget.initialData['applies_to_all'] ?? false;
    selectedPlayers = List<String>.from(widget.initialData['assigned_players'] ?? []);
    isActive = widget.initialData['is_active'] ?? true;
  }

  TimeOfDay? _parseTime(String? timeStr) {
    if (timeStr == null) return null;
    final parts = timeStr.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  Future<void> _fetchPlayers() async {
    try {
      final playersSnapshot = await FirebaseFirestore.instance.collection('players').get();
      if (mounted) {
        setState(() {
          for (var doc in playersSnapshot.docs) {
            playerNames[doc.id] = doc.data()['name'] as String? ?? 'Unknown';
          }
          allPlayers = playersSnapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
          filteredPlayers = allPlayers;
        });
      }
    } catch (e) {
      print('Error fetching players: $e');
    }
  }

  Future<void> _selectTime(BuildContext context, bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStart ? startTime ?? TimeOfDay.now() : endTime ?? TimeOfDay.now(),
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
          const SnackBar(content: Text('Only club admins can edit discount codes')),
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
          .doc(widget.discountCodeId)
          .update({
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
        'is_active': isActive,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Discount code updated successfully')),
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
        title: const Text('Edit Discount Code'),
        backgroundColor: Colors.red,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
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
                  const Text(
                    'Select Players',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
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
                              if (isAllSelected) {
                                selectedPlayers.clear();
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
                                      color: isAllSelected ? Colors.red : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: const CircleAvatar(
                                    radius: 28,
                                    child: Text(
                                      'All',
                                      style: TextStyle(fontSize: 16),
                                    ),
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
                                    : DateFormat('hh:mm a')
                                    .format(DateTime(0, 1, 1, startTime!.hour, startTime!.minute)),
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
                                    : DateFormat('hh:mm a')
                                    .format(DateTime(0, 1, 1, endTime!.hour, endTime!.minute)),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Is Active'),
                    value: isActive,
                    activeColor: Colors.redAccent,
                    onChanged: (value) {
                      setState(() {
                        isActive = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
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
                        'Save Changes',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
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