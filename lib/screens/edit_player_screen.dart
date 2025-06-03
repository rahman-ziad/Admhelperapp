import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:shimmer_animation/shimmer_animation.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class EditPlayerScreen extends StatefulWidget {
  final String clubId;
  final Map<String, dynamic> player;

  const EditPlayerScreen({super.key, required this.clubId, required this.player});

  @override
  _EditPlayerScreenState createState() => _EditPlayerScreenState();
}

class _EditPlayerScreenState extends State<EditPlayerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _inGameNameController = TextEditingController();
  String _phoneNumber = '';
  File? _imageFile;
  String? _existingImageUrl;
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.player['name'] ?? '';
    _phoneNumber = widget.player['phone_number'] ?? '';
    _inGameNameController.text = widget.player['in_game_name'] ?? '';
    _existingImageUrl = widget.player['image_url'];
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  Future<void> _updatePlayer() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

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
      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!userDoc.exists || userDoc['userType'] != 'admin') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only admins can edit players')),
        );
        return;
      }
      String? imageUrl = _existingImageUrl;
      if (_imageFile != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('player_img/${widget.player['id']}.jpg');
        await storageRef.putFile(_imageFile!);
        imageUrl = await storageRef.getDownloadURL();
      }
      await FirebaseFirestore.instance
          .collection('players')
          .doc(widget.player['id'])
          .update({
        'name': _nameController.text.trim(),
        'phone_number': _phoneNumber.trim(),
        'in_game_name': _inGameNameController.text.trim(),
        'image_url': imageUrl,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Player updated successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      print('Error updating player: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating player: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _inGameNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Player')),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.grey.shade300,
                        backgroundImage: _imageFile != null
                            ? FileImage(_imageFile!)
                            : _existingImageUrl != null
                            ? NetworkImage(_existingImageUrl!)
                            : const AssetImage('assets/placeholder.png') as ImageProvider,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 4,
                        child: GestureDetector(
                          onTap: _pickImage,
                          child: CircleAvatar(
                            backgroundColor: Theme.of(context).primaryColor,
                            radius: 18,
                            child: const Icon(
                              Icons.add,
                              size: 22,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value!.isEmpty ? 'Enter player name' : null,
                  ),
                  const SizedBox(height: 10),
                  IntlPhoneField(
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      border: OutlineInputBorder(),
                    ),
                    initialCountryCode: 'BD',
                    initialValue: _phoneNumber,
                    onChanged: (phone) {
                      setState(() {
                        _phoneNumber = phone.completeNumber;
                      });
                    },
                    validator: (phone) =>
                    phone == null || phone.number.isEmpty ? 'Enter phone number' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _inGameNameController,
                    decoration: const InputDecoration(
                      labelText: 'In-Game Name (Max 8 letters)',
                      prefixIcon: Icon(Icons.sports_esports),
                      border: OutlineInputBorder(),
                    ),
                    maxLength: 8,
                    validator: (value) => value!.isEmpty ? 'Enter IGN' : null,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _updatePlayer,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.red,
                    ),
                    child: _isSubmitting
                        ? LoadingAnimationWidget.staggeredDotsWave(
                      color: Colors.white,
                      size: 24,
                    )
                        : const Text(
                      'Update Player',
                      style: TextStyle(color: Colors.white),
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