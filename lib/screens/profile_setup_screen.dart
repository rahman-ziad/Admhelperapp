import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'edit_table_screen.dart';
import 'home_screen.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  _ProfileSetupScreenState createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _clubNameController = TextEditingController();
  final _tableCountController = TextEditingController();
  final _practiceDiscountController = TextEditingController();
  File? _imageFile;
  bool _isLoading = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      String? logoUrl;
      if (_imageFile != null) {
        final storageRef = FirebaseStorage.instance.ref().child('club_logos/${user.uid}');
        await storageRef.putFile(_imageFile!);
        logoUrl = await storageRef.getDownloadURL();
      }

      double? practiceDiscount;
      if (_practiceDiscountController.text.isNotEmpty) {
        practiceDiscount = double.tryParse(_practiceDiscountController.text);
      }

      final clubDoc = await FirebaseFirestore.instance.collection('clubs').add({
        'name': _clubNameController.text.trim(),
        'logo_url': logoUrl,
        'admin_id': user.uid,
        'table_count': int.parse(_tableCountController.text.trim()),
        'practice_mode_discount_percentage': practiceDiscount, // New parameter
      });

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'email': user.email,
        'name': _nameController.text.trim(),
        'club_id': clubDoc.id,
        'userType': 'admin',
        'isProfileSetup': true,
      }, SetOptions(merge: true));

      ref.refresh(userProfileProvider(user.uid));

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => EditTableScreen(clubId: clubDoc.id)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _clubNameController.dispose();
    _tableCountController.dispose();
    _practiceDiscountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Up Profile'),
        backgroundColor: Colors.red,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.grey[300],
                            backgroundImage: _imageFile != null
                                ? FileImage(_imageFile!)
                                : const AssetImage('assets/club_logo.png') as ImageProvider,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.redAccent,
                              child: Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Upload Club Logo',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Your Name',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.person, color: Colors.redAccent),
                      ),
                      validator: (value) => value!.isEmpty ? 'Enter your name' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _clubNameController,
                      decoration: InputDecoration(
                        labelText: 'Club Name',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.store, color: Colors.redAccent),
                      ),
                      validator: (value) => value!.isEmpty ? 'Enter club name' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _tableCountController,
                      decoration: InputDecoration(
                        labelText: 'Number of Tables',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.table_chart, color: Colors.redAccent),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value!.isEmpty) return 'Enter number of tables';
                        if (int.tryParse(value) == null || int.parse(value) <= 0)
                          return 'Enter a valid positive integer';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _practiceDiscountController,
                      decoration: InputDecoration(
                        labelText: 'Practice Mode Discount (%)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.discount, color: Colors.green),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value!.isEmpty) return null; // Optional field
                        final discount = double.tryParse(value!);
                        if (discount == null || discount < 0 || discount > 100)
                          return 'Enter a valid percentage (0-100)';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : Container(
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
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Submit',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}