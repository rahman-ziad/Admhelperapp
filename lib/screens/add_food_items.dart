import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shimmer_animation/shimmer_animation.dart';
class AddFoodItemScreen extends StatefulWidget {
  final String clubId;

  const AddFoodItemScreen({super.key, required this.clubId});

  @override
  _AddFoodItemScreenState createState() => _AddFoodItemScreenState();
}

class _AddFoodItemScreenState extends State<AddFoodItemScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _stockController = TextEditingController();
  final _priceController = TextEditingController();
  String? _category = 'Appetizer';
  File? _imageFile;
  bool _isSubmitting = false; // New state to track submission

  final List<String> _categories = ['Appetizer', 'Main Dish', 'Beverage', 'Snacks'];

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return; // Prevent multiple submissions

    if (_nameController.text.isEmpty || _priceController.text.isEmpty || _category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name, Price, and Category are required')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true; // Set submitting state
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
          const SnackBar(content: Text('Only club admins can add food items')),
        );
        return;
      }
      String? imageUrl;
      if (_imageFile != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('food_images/${widget.clubId}/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await storageRef.putFile(_imageFile!);
        imageUrl = await storageRef.getDownloadURL();
      }

      await FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .collection('food_items')
          .add({
        'name': _nameController.text,
        'description': _descriptionController.text,
        'image_url': imageUrl,
        'stock': int.tryParse(_stockController.text) ?? 0,
        'price': double.tryParse(_priceController.text) ?? 0.0,
        'category': _category,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Food item added successfully')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding food item: $e')),
      );
    } finally {
      setState(() {
        _isSubmitting = false; // Reset submitting state
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Food Item'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              TextField(
                controller: _stockController,
                decoration: const InputDecoration(labelText: 'Stock'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: _priceController,
                decoration: const InputDecoration(labelText: 'Price'),
                keyboardType: TextInputType.number,
              ),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _categories
                    .map((category) => DropdownMenuItem<String>(
                  value: category,
                  child: Text(category),
                ))
                    .toList(),
                onChanged: (value) => setState(() => _category = value),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _pickImage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  'Upload Image',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              if (_imageFile != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Image.file(_imageFile!, height: 100),
                ),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit, // Disable button during submission
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : const Text(
                  'Submit',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}