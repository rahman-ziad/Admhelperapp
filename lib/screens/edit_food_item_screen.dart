import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shimmer_animation/shimmer_animation.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class EditFoodItemScreen extends StatefulWidget {
  final String clubId;
  final Map<String, dynamic> foodItem;

  const EditFoodItemScreen({Key? key, required this.clubId, required this.foodItem}) : super(key: key);

  @override
  State<EditFoodItemScreen> createState() => _EditFoodItemScreenState();
}

class _EditFoodItemScreenState extends State<EditFoodItemScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _stockController = TextEditingController();
  final _priceController = TextEditingController();

  String? _selectedCategory;
  File? _pickedImage;
  String? _existingImageUrl;
  bool _isLoading = true;
  bool _isSubmitting = false;

  final List<String> _categories = ['Appetizer', 'Main Dish', 'Beverage', 'Snacks'];

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.foodItem['name'] ?? '';
    _descriptionController.text = widget.foodItem['description'] ?? '';
    _stockController.text = widget.foodItem['stock']?.toString() ?? '0';
    _priceController.text = widget.foodItem['price']?.toString() ?? '0.0';
    _selectedCategory = widget.foodItem['category'];
    _existingImageUrl = widget.foodItem['image_url'];
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _pickedImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    if (_nameController.text.isEmpty ||
        _priceController.text.isEmpty ||
        _selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
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

      final clubDoc = await FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .get();

      if (!clubDoc.exists || clubDoc['admin_id'] != user.uid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only club admins can edit food items')),
        );
        return;
      }

      String? imageUrl = _existingImageUrl;

      if (_pickedImage != null) {
        final ref = FirebaseStorage.instance
            .ref('food_images/${widget.clubId}/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putFile(_pickedImage!);
        imageUrl = await ref.getDownloadURL();
      }

      await FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .collection('food_items')
          .doc(widget.foodItem['id'])
          .update({
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'stock': int.tryParse(_stockController.text.trim()) ?? 0,
        'price': double.tryParse(_priceController.text.trim()) ?? 0.0,
        'category': _selectedCategory,
        'image_url': imageUrl,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Food item updated successfully')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating food: $e')),
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
      appBar: AppBar(title: const Text('Edit Food Item')),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _stockController,
                  decoration: const InputDecoration(
                    labelText: 'Stock',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _priceController,
                  decoration: const InputDecoration(
                    labelText: 'Price',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _categories.contains(_selectedCategory) ? _selectedCategory : null,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: _categories
                      .map((category) => DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCategory = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Pick New Image'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_pickedImage != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _pickedImage!,
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  )
                else if (_existingImageUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      _existingImageUrl!,
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: Colors.green,
                  ),
                  child: _isSubmitting
                      ? LoadingAnimationWidget.staggeredDotsWave(
                    color: Colors.white,
                    size: 24,
                  )
                      : const Text('Save Changes'),
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