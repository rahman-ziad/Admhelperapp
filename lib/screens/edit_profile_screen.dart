import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shimmer_animation/shimmer_animation.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class EditProfileScreen extends StatefulWidget {
  final String clubId;

  const EditProfileScreen({super.key, required this.clubId});

  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _clubNameController = TextEditingController();
  final _tableCountController = TextEditingController();
  File? _imageFile;
  String? _existingLogoUrl;
  bool _isLoading = true; // For shimmer during initial load
  bool _isSubmitting = false; // For button loading state

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final clubDoc =
      await FirebaseFirestore.instance.collection('clubs').doc(widget.clubId).get();
      if (userDoc.exists) {
        _nameController.text = userDoc['name'] ?? '';
      }
      if (clubDoc.exists) {
        _clubNameController.text = clubDoc['name'] ?? '';
        _tableCountController.text = clubDoc['table_count']?.toString() ?? '';
        _existingLogoUrl = clubDoc['logo_url'];
      }
    } catch (e) {
      print('Error loading profile: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    final user = FirebaseAuth.instance.currentUser!;
    try {
      String? logoUrl = _existingLogoUrl;
      if (_imageFile != null) {
        final storageRef =
        FirebaseStorage.instance.ref().child('club_logos/${user.uid}');
        await storageRef.putFile(_imageFile!);
        logoUrl = await storageRef.getDownloadURL();
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'name': _nameController.text.trim(),
      });

      await FirebaseFirestore.instance.collection('clubs').doc(widget.clubId).update({
        'name': _clubNameController.text.trim(),
        'logo_url': logoUrl,
        'table_count': int.parse(_tableCountController.text.trim()),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: Colors.red,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.redAccent),
                ),
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
                            alignment: Alignment.center,
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundColor: Colors.grey[300],
                                backgroundImage: _imageFile != null
                                    ? FileImage(_imageFile!)
                                    : (_existingLogoUrl != null
                                    ? NetworkImage(_existingLogoUrl!)
                                    : const AssetImage('assets/club_logo.png')
                                as ImageProvider),
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
                              borderSide: BorderSide(color: Colors.redAccent),
                            ),
                            prefixIcon: Icon(Icons.person, color: Colors.red),
                          ),
                          validator: (value) =>
                          value!.isEmpty ? 'Enter your name' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _clubNameController,
                          decoration: InputDecoration(
                            labelText: 'Club Name',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.redAccent),
                            ),
                            prefixIcon: Icon(Icons.store, color: Colors.red),
                          ),
                          validator: (value) =>
                          value!.isEmpty ? 'Enter club name' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _tableCountController,
                          decoration: InputDecoration(
                            labelText: 'Number of Tables',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.redAccent),
                            ),
                            prefixIcon: Icon(Icons.table_chart, color: Colors.red),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value!.isEmpty) return 'Enter number of tables';
                            if (int.tryParse(value) == null || int.parse(value) <= 0)
                              return 'Enter a valid positive integer';
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.red, Colors.redAccent],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submit,
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

  @override
  void dispose() {
    _nameController.dispose();
    _clubNameController.dispose();
    _tableCountController.dispose();
    super.dispose();
  }
}