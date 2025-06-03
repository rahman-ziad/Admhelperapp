import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shimmer_animation/shimmer_animation.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'main_home_screen.dart';

class EditTableScreen extends StatefulWidget {
  final String clubId;

  const EditTableScreen({super.key, required this.clubId});

  @override
  _EditTableScreenState createState() => _EditTableScreenState();
}

class _EditTableScreenState extends State<EditTableScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoadingTables = true;
  bool _isSubmitting = false;

  int? _tableCount;
  List<Map<String, dynamic>> _tables = [];

  @override
  void initState() {
    super.initState();
    _loadClubData();
  }

  Future<void> _loadClubData() async {
    try {
      final clubDoc = await FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .get();
      if (clubDoc.exists) {
        setState(() {
          _tableCount = clubDoc['table_count'] ?? 0;
          _loadTablesFromFirestore();
        });
      } else {
        setState(() {
          _tableCount = 0;
          _isLoadingTables = false;
        });
      }
    } catch (e) {
      print('Error loading club data: $e');
      setState(() {
        _tableCount = 0;
        _isLoadingTables = false;
      });
    }
  }

  Future<void> _loadTablesFromFirestore() async {
    setState(() {
      _isLoadingTables = true;
    });

    try {
      final tablesRef = FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .collection('tables');
      final existingTables = await tablesRef.get();

      _tables.clear();

      if (existingTables.docs.length < _tableCount!) {
        final batch = FirebaseFirestore.instance.batch();
        for (int i = existingTables.docs.length; i < _tableCount!; i++) {
          final docId = 'table_${i + 1}';
          batch.set(tablesRef.doc(docId), {
            'name': 'Table ${i + 1}',
            'type': 'Pool',
            'is_active': false,
            'current_session_id': null,
            'per_min_cost': 5.0,
            'coin_price': 20.0,
          });
        }
        await batch.commit();
        final updatedTables = await tablesRef.get();
        for (var doc in updatedTables.docs) {
          final docId = doc.id;
          final order = int.tryParse(docId.replaceFirst('table_', '')) ?? 0;
          _tables.add({
            'id': docId,
            'name': doc['name'] ?? 'Table $order',
            'type': doc.data().containsKey('type') ? doc['type'] as String : 'Pool',
            'is_active': doc.data().containsKey('is_active') ? doc['is_active'] as bool : false,
            'current_session_id': doc['current_session_id'] ?? null,
            'per_min_cost': doc.data().containsKey('per_min_cost') ? doc['per_min_cost']?.toDouble() : 5.0,
            'coin_price': doc.data().containsKey('coin_price') ? doc['coin_price']?.toDouble() : 20.0,
            'order': order,
          });
        }
      } else {
        for (var doc in existingTables.docs) {
          final docId = doc.id;
          final order = int.tryParse(docId.replaceFirst('table_', '')) ?? 0;
          _tables.add({
            'id': docId,
            'name': doc['name'] ?? 'Table $order',
            'type': doc.data().containsKey('type') ? doc['type'] as String : 'Pool',
            'is_active': doc.data().containsKey('is_active') ? doc['is_active'] as bool : false,
            'current_session_id': doc['current_session_id'] ?? null,
            'per_min_cost': doc.data().containsKey('per_min_cost') ? doc['per_min_cost']?.toDouble() : 5.0,
            'coin_price': doc.data().containsKey('coin_price') ? doc['coin_price']?.toDouble() : 20.0,
            'order': order,
          });
        }
      }
      _tables.sort((a, b) => (a['order'] ?? 0).compareTo(b['order'] ?? 0));
    } catch (e) {
      print('Error loading tables: $e');
    } finally {
      setState(() {
        _isLoadingTables = false;
      });
    }
  }

  Future<void> _saveTablesToFirestore() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      final tablesRef = FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .collection('tables');
      final existingDocs = await tablesRef.get();
      for (final doc in existingDocs.docs) {
        batch.delete(doc.reference);
      }
      for (final table in _tables) {
        if (table['id'] != null) {
          batch.set(tablesRef.doc(table['id']), {
            'name': table['name'],
            'type': table['type'],
            'is_active': table['is_active'],
            'current_session_id': table['current_session_id'],
            'per_min_cost': table['per_min_cost'],
            'coin_price': table['coin_price'],
          });
        }
      }
      await batch.commit();
      print('Tables saved successfully');
    } catch (e) {
      print('Error saving tables: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving tables: $e')),
      );
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _updateTableName(int index, String newName) {
    if (index >= 0 && index < _tables.length) {
      setState(() {
        _tables[index]['name'] = newName.isEmpty ? 'Table ${index + 1}' : newName;
      });
      _saveTablesToFirestore();
    }
  }

  void _updateTableType(int index, String newType) {
    if (index >= 0 && index < _tables.length) {
      setState(() {
        _tables[index]['type'] = newType;
      });
      _saveTablesToFirestore();
    }
  }

  void _showEditOptions(int index) {
    if (index < 0 || index >= _tables.length) return;
    final table = _tables[index];
    final _perMinCostController = TextEditingController(text: table['per_min_cost'].toString());
    final _coinPriceController = TextEditingController(text: table['coin_price'].toString());
    bool _isModalSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Stack(
              children: [
                SingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Edit Pricing for ${table['name']}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _perMinCostController,
                          decoration: InputDecoration(
                            labelText: 'Per Minute Cost (TK)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            prefixIcon: const Icon(Icons.money_outlined, color: Colors.red),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _coinPriceController,
                          decoration: InputDecoration(
                            labelText: 'Coin Price (TK)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            prefixIcon: const Icon(Icons.money_outlined, color: Colors.red),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.red, Colors.redAccent],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ElevatedButton(
                            onPressed: _isModalSubmitting
                                ? null
                                : () async {
                              setModalState(() {
                                _isModalSubmitting = true;
                              });
                              final perMinCost = double.tryParse(_perMinCostController.text);
                              final coinPrice = double.tryParse(_coinPriceController.text);
                              if (perMinCost != null && perMinCost > 0 && coinPrice != null && coinPrice > 0) {
                                setState(() {
                                  _tables[index]['per_min_cost'] = perMinCost;
                                  _tables[index]['coin_price'] = coinPrice;
                                });
                                await _saveTablesToFirestore();
                                Navigator.pop(context);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Enter valid positive numbers')),
                                );
                                setModalState(() {
                                  _isModalSubmitting = false;
                                });
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: _isModalSubmitting
                                ? LoadingAnimationWidget.staggeredDotsWave(
                              color: Colors.white,
                              size: 24,
                            )
                                : const Text(
                              'Save',
                              style: TextStyle(fontSize: 16, color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                if (_isLoadingTables)
                  Shimmer(
                    color: Colors.grey[300]!,
                    child: Container(
                      color: Colors.grey[200],
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Tables'),
        surfaceTintColor: Colors.transparent,
        elevation: 5,
      ),
      body: Stack(
        children: [
          (_tableCount == null || _isLoadingTables)
              ? const Center(child: CircularProgressIndicator(color: Colors.red))
              : SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < _tableCount!; i++)
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            const Icon(Icons.table_restaurant_sharp, color: Colors.red, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: _tables.length > i
                                              ? _tables[i]['name']
                                              : 'Table ${i + 1}',
                                          decoration: InputDecoration(
                                            hintText: 'Enter table name',
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                              borderSide: const BorderSide(color: Colors.redAccent),
                                            ),
                                            contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            suffixIcon: const Icon(
                                              Icons.edit,
                                              color: Colors.red,
                                              size: 20,
                                            ),
                                          ),
                                          style: const TextStyle(fontSize: 16),
                                          onFieldSubmitted: (value) => _updateTableName(i, value),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      ChoiceChip(
                                        label: const Text(
                                          'Pool',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        selected: i < _tables.length && _tables[i]['type'] == 'Pool',
                                        onSelected: (selected) {
                                          if (selected) _updateTableType(i, 'Pool');
                                        },
                                        selectedColor: Colors.redAccent,
                                        backgroundColor: Colors.grey[200],
                                        labelStyle: TextStyle(
                                          color: i < _tables.length && _tables[i]['type'] == 'Pool'
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ChoiceChip(
                                        label: const Text(
                                          'Snooker',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        selected: i < _tables.length && _tables[i]['type'] == 'Snooker',
                                        onSelected: (selected) {
                                          if (selected) _updateTableType(i, 'Snooker');
                                        },
                                        selectedColor: Colors.redAccent,
                                        backgroundColor: Colors.grey[200],
                                        labelStyle: TextStyle(
                                          color: i < _tables.length && _tables[i]['type'] == 'Snooker'
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings, color: Colors.red),
                              onPressed: () => _showEditOptions(i),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.redAccent, Colors.red],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ElevatedButton(
                      onPressed: _isSubmitting
                          ? null
                          : () async {
                        await _saveTablesToFirestore();
                        if (mounted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => MainHomeScreen(clubId: widget.clubId)),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSubmitting
                          ? LoadingAnimationWidget.staggeredDotsWave(
                        color: Colors.white,
                        size: 24,
                      )
                          : const Text(
                        'Save and Continue',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          if (_isLoadingTables)
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

  @override
  void dispose() {
    super.dispose();
  }
}