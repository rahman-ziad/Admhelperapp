import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class CategoryImageUploadScreen extends StatefulWidget {
  final String category;

  const CategoryImageUploadScreen({super.key, required this.category});

  @override
  _CategoryImageUploadScreenState createState() => _CategoryImageUploadScreenState();
}

class _CategoryImageUploadScreenState extends State<CategoryImageUploadScreen> {
  File? _imageFile;
  String? _existingImageUrl;

  @override
  void initState() {
    super.initState();
    _loadExistingImage();
  }

  Future<void> _loadExistingImage() async {
    try {
      final storageRef =
      FirebaseStorage.instance.ref().child('category_images/${widget.category}.jpg');
      final url = await storageRef.getDownloadURL();
      setState(() => _existingImageUrl = url);
    } catch (e) {
      // Image doesn't exist yet
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  Future<void> _uploadImage() async {
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image')),
      );
      return;
    }
    try {
      final storageRef =
      FirebaseStorage.instance.ref().child('category_images/${widget.category}.jpg');
      await storageRef.putFile(_imageFile!);
      final url = await storageRef.getDownloadURL();
      setState(() => _existingImageUrl = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Category image uploaded successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading image: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Upload Image for ${widget.category}')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_imageFile != null)
              Image.file(_imageFile!, height: 150)
            else if (_existingImageUrl != null)
              Image.network(_existingImageUrl!, height: 150)
            else
              const Text('No image selected'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _pickImage,
              child: const Text('Select Image'),
            ),
            ElevatedButton(
              onPressed: _uploadImage,
              child: const Text('Upload Image'),
            ),
          ],
        ),
      ),
    );
  }
}