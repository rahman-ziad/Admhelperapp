import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:shimmer_animation/shimmer_animation.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'bill_settlement_screen.dart'; // Assuming this is where CapturePhotoScreen is defined

class AddPlayerFormScreen extends StatefulWidget {
  final String clubId;

  const AddPlayerFormScreen({Key? key, required this.clubId}) : super(key: key);

  @override
  State<AddPlayerFormScreen> createState() => _AddPlayerFormScreenState();
}

class _AddPlayerFormScreenState extends State<AddPlayerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _inGameNameController = TextEditingController();
  String _phoneNumber = '';
  File? _selectedImage;
  String? _warningMessage;
  bool _isLoading = true; // For initial loading
  bool _isSaving = false; // For save button loading

  Future<bool> _checkPhoneAvailability(String phoneNumber) async {
    final querySnapshot = await FirebaseFirestore.instance
        .collection('players')
        .where('phone_number', isEqualTo: phoneNumber.trim())
        .get();
    return querySnapshot.docs.isNotEmpty;
  }

  Future<void> _pickImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedImage = File(result.files.single.path!);
      });
      Navigator.pop(context);
    }
  }

  Future<void> _takePhoto() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CapturePhotoScreen(
          onImageCaptured: (image) {
            setState(() {
              _selectedImage = image;
            });
          },
          phoneNumber: _phoneNumber,
        ),
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('Upload Photo'),
              onTap: () {
                _pickImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Capture Photo'),
              onTap: () {
                _takePhoto();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _savePlayer() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not authenticated')),
        );
        return;
      }

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!userDoc.exists || userDoc['userType'] != 'admin') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only admins can add players')),
        );
        return;
      }

      String? imageUrl;
      if (_selectedImage != null) {
        final playerId = FirebaseFirestore.instance.collection('players').doc().id;
        final storageRef = FirebaseStorage.instance.ref().child('player_img/$playerId.jpg');
        await storageRef.putFile(_selectedImage!);
        imageUrl = await storageRef.getDownloadURL();
      }

      final playerData = {
        'name': _nameController.text.trim(),
        'phone_number': _phoneNumber.trim(),
        'in_game_name': _inGameNameController.text.trim(),
        'image_url': imageUrl,
      };

      await FirebaseFirestore.instance.collection('players').add(playerData);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Player added successfully')),
      );
      Navigator.pop(context);
    } catch (e) {
      print('Error saving player: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add player: $e')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Simulate initial loading (e.g., fetching data if needed)
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _isLoading = false);
    });
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
      appBar: AppBar(
        title: const Text('Add New Player'),
      ),
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
                        backgroundImage: _selectedImage != null
                            ? FileImage(_selectedImage!)
                            : const AssetImage('assets/placeholder.png') as ImageProvider,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 4,
                        child: GestureDetector(
                          onTap: _showPhotoOptions,
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
                  IntlPhoneField(
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      border: OutlineInputBorder(),
                    ),
                    initialCountryCode: 'BD',
                    onChanged: (phone) async {
                      _phoneNumber = phone.completeNumber;
                      final isTaken = await _checkPhoneAvailability(_phoneNumber);
                      setState(() {
                        _warningMessage = isTaken ? 'Phone number already registered!' : null;
                      });
                    },
                    validator: (phone) =>
                    phone == null || phone.number.isEmpty ? 'Enter phone number' : null,
                  ),
                  const SizedBox(height: 10),
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
                  TextFormField(
                    controller: _inGameNameController,
                    decoration: const InputDecoration(
                      labelText: 'In-Game Name (IGN)',
                      prefixIcon: Icon(Icons.sports_esports),
                      border: OutlineInputBorder(),
                    ),
                    maxLength: 10,
                    validator: (value) => value!.isEmpty ? 'Enter IGN' : null,
                  ),
                  const SizedBox(height: 20),
                  if (_warningMessage != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.red),
                      ),
                      child: Text(
                        _warningMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 14),
                      ),
                    ),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _savePlayer,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.red,
                    ),
                    child: _isSaving
                        ? LoadingAnimationWidget.staggeredDotsWave(
                        color: Colors.white, size: 24)
                        : const Text(
                      'Save Player',
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

// Updated CapturePhotoScreen
class CapturePhotoScreen extends StatefulWidget {
  final Function(File) onImageCaptured;
  final String phoneNumber;

  const CapturePhotoScreen({
    Key? key,
    required this.onImageCaptured,
    required this.phoneNumber,
  }) : super(key: key);

  @override
  _CapturePhotoScreenState createState() => _CapturePhotoScreenState();
}

class _CapturePhotoScreenState extends State<CapturePhotoScreen> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
    );

    _initializeControllerFuture = _controller!.initialize();
    if (mounted) {
      setState(() {});
    }
  }

  Future<File> _resizeAndRenameImage(XFile imageFile, String phoneNumber) async {
    final image = img.decodeImage(await imageFile.readAsBytes())!;
    final resizedImage = img.copyResize(image, width: 512, height: 512);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final newFileName = '${phoneNumber}_$timestamp.jpg';

    final tempDir = await getTemporaryDirectory();
    final newFilePath = '${tempDir.path}/$newFileName';
    final newFile = File(newFilePath);
    await newFile.writeAsBytes(img.encodeJpg(resizedImage));

    return newFile;
  }

  void _capturePhoto() async {
    if (_isCapturing || !_controller!.value.isInitialized) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      final XFile file = await _controller!.takePicture();
      final resizedImage = await _resizeAndRenameImage(file, widget.phoneNumber);
      widget.onImageCaptured(resizedImage);
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error capturing photo: $e')),
      );
    } finally {
      setState(() {
        _isCapturing = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture Photo'),
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (_controller!.value.isInitialized) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  CameraPreview(_controller!),
                  CustomPaint(
                    painter: FaceGridPainter(),
                    child: Container(),
                  ),
                  Positioned(
                    bottom: 20,
                    child: ElevatedButton(
                      onPressed: _isCapturing ? null : _capturePhoto,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: _isCapturing
                          ? LoadingAnimationWidget.staggeredDotsWave(
                          color: Colors.white, size: 24)
                          : const Text('Capture', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              );
            } else {
              return const Center(child: Text('Camera initialization failed'));
            }
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}

class FaceGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    const gridSize = 200.0;

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: gridSize,
        height: gridSize,
      ),
      paint,
    );

    canvas.drawLine(
      Offset(centerX - gridSize / 4, centerY),
      Offset(centerX + gridSize / 4, centerY),
      paint,
    );
    canvas.drawLine(
      Offset(centerX, centerY - gridSize / 4),
      Offset(centerX, centerY + gridSize / 4),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}