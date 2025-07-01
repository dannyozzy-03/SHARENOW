import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:twitterr/helper/image_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'dart:math';
import 'package:twitterr/screens/auth/submission/classDetails.dart';
import 'package:twitterr/screens/auth/submission/classwork.dart';
import 'package:twitterr/screens/auth/submission/participants.dart';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:twitterr/services/notification_service.dart';

const Color kPrimaryColor = Color(0xFF4A90E2);
const Color kTextPrimaryColor = Color(0xFF2C3E50);
const Color kTextSecondaryColor = Color(0xFF95A5A6);

enum PostType {
  announcement,
  assignment,
  material
}

class ClassPage extends StatefulWidget {
  final String classId;
  final String className;
  final Function(int)? onPageChange;

  const ClassPage({
    Key? key, 
    required this.classId,
    required this.className,
    this.onPageChange,
  }) : super(key: key);

  @override
  State<ClassPage> createState() => _ClassPageState();
}

class _ClassPageState extends State<ClassPage> {
  final TextEditingController _announcementController = TextEditingController();
  final TextEditingController _instructionController = TextEditingController(); // Add this
  File? _selectedImage;
  File? _selectedDocument;
  String? _documentName;
  bool _isPosting = false;
  final ImagePicker _picker = ImagePicker();

  bool _isLecturer = false; // Add this near the top of the _ClassPageState class

  void _showAttachmentOptions(StateSetter dialogSetState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF202124),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera, color: Colors.white),
                title: const Text('Take Photo', 
                  style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera, dialogSetState);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.white),
                title: const Text('Choose from Gallery', 
                  style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery, dialogSetState);
                },
              ),
              ListTile(
                leading: const Icon(Icons.upload_file, color: Colors.white),
                title: const Text('Upload Document', 
                  style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickDocument(dialogSetState);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source, StateSetter dialogSetState) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        dialogSetState(() {
          _selectedImage = File(pickedFile.path);
          _selectedDocument = null; // Reset document when image is selected
          _documentName = null;
        });
      }
    } catch (e) {
      print('Error picking image: $e');
    }
  }

  Future<void> _pickDocument(StateSetter dialogSetState) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final path = result.files.single.path;
        if (path != null) {
          dialogSetState(() {
            _selectedDocument = File(path);
            _documentName = result.files.single.name;
            _selectedImage = null; // Reset image when document is selected
          });
        }
      }
    } catch (e) {
      print('Error picking document: $e');
    }
  }

  DateTime? _selectedDueDate;

  Future<void> _selectDueDate(BuildContext context) async {
    final DateTime? picked = await showDateTimePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDueDate = picked;
      });
    }
  }

  Widget _buildDueDatePicker(PostType selectedType) {
    if (selectedType != PostType.assignment) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.schedule, color: Colors.grey[400]),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _selectDueDate(context),
            child: Text(
              _selectedDueDate != null
                  ? 'Due: ${_selectedDueDate!.toString().split('.')[0]}'
                  : 'Set due date',
              style: TextStyle(
                color: Colors.grey[400],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Modify the _postAnnouncement method
Future<void> _postAnnouncement(PostType type) async {
  if (_announcementController.text.trim().isEmpty) {
    return;
  }

  setState(() {
    _isPosting = true;
  });

  try {
    String? imageUrl;
    String? documentUrl;

    if (_selectedImage != null) {
      imageUrl = await ImageHelper.uploadImageToFirebase(_selectedImage!);
    }

    if (_selectedDocument != null) {
      try {
        final fileName = path.basename(_selectedDocument!.path);
        final ref = FirebaseStorage.instance
            .ref()
            .child('documents')
            .child(widget.classId)
            .child(DateTime.now().millisecondsSinceEpoch.toString() + '_' + fileName);
        
        await ref.putFile(_selectedDocument!);
        documentUrl = await ref.getDownloadURL();
      } catch (e) {
        print('Error uploading document: $e');
        throw e;
      }
    }

    // Add the announcement to Firestore
    final announcementRef = await FirebaseFirestore.instance
        .collection('classes')
        .doc(widget.classId)
        .collection('announcements')
        .add({
      'text': _announcementController.text.trim(),
      'instructions': _instructionController.text.trim(),
      'imageUrl': imageUrl,
      'documentUrl': documentUrl,
      'documentName': _documentName,
      'timestamp': FieldValue.serverTimestamp(),
      'type': type.toString().split('.').last,
      'dueDate': type == PostType.assignment ? _selectedDueDate?.toUtc() : null,
      'lecturerName': FirebaseAuth.instance.currentUser?.displayName ?? 'Lecturer',
    });

    print('Getting students from participants for class: ${widget.classId}');

    // Get class participants who are students
    final classDoc = await FirebaseFirestore.instance
        .collection('classes')
        .doc(widget.classId)
        .get();

    if (!classDoc.exists) {
      print('Class document not found');
      return;
    }

    final participants = List<String>.from(classDoc.data()?['participants'] ?? []);
    print('Found ${participants.length} total participants');

    // Get all users who are students
    final studentsSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'Student')
        .where(FieldPath.documentId, whereIn: participants)
        .get();

    print('Found ${studentsSnapshot.docs.length} students in class');

    for (var studentDoc in studentsSnapshot.docs) {
      String? token = studentDoc.data()['fcmToken'];
      print('Processing student: ${studentDoc.id}, Token: $token');

      if (token != null) {
        print('Creating notification for student: ${studentDoc.data()['name']}');
        
        // Inside _postAnnouncement method, update the notification creation:
await FirebaseFirestore.instance.collection('notifications').add({
  'token': token,
  'notification': {
    'title': '${widget.className} - New ${type.toString().split('.').last}',
    'body': _announcementController.text.trim(),
    'android_channel_id': 'high_importance_channel',
  },
  'data': {
    'classId': widget.classId,
    'announcementId': announcementRef.id,
    'type': type.toString().split('.').last,
    'click_action': 'FLUTTER_NOTIFICATION_CLICK',
    'android_channel_id': 'high_importance_channel',
  },
  'android': {
    'priority': 'high',
    'notification': {
      'channel_id': 'high_importance_channel',
      'priority': 'high',
      'default_sound': true,
      'default_vibrate_timings': true,
    },
  },
  'apns': {
    'headers': {
      'apns-priority': '10',
    },
    'payload': {
      'aps': {
        'sound': 'default',
        'badge': 1,
        'content-available': 1,
      },
    },
  },
  'priority': 'high',
  'timestamp': FieldValue.serverTimestamp(),
});
      }
    }

    if (mounted) {
      setState(() {
        _announcementController.clear();
        _instructionController.clear();
        _selectedImage = null;
        _selectedDocument = null;
        _documentName = null;
        _isPosting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${type.toString().split('.').last} posted successfully')),
      );
    }
  } catch (e) {
    print('Error posting announcement: $e');
    if (mounted) {
      setState(() {
        _isPosting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to post')),
      );
    }
  }
}

  void _showAnnouncementDialog(BuildContext context) {
    PostType selectedType = PostType.announcement;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.8,
                height: MediaQuery.of(context).size.height * 0.8,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Modern header with close and post buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: kTextPrimaryColor),
                          onPressed: () => Navigator.pop(context),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.grey[100],
                            padding: const EdgeInsets.all(8),
                          ),
                        ),
                        TextButton(
                          onPressed: _isPosting ? null : () {
                            _postAnnouncement(selectedType);
                            Navigator.pop(context);
                          },
                          style: TextButton.styleFrom(
                            backgroundColor: _isPosting ? Colors.grey[300] : kPrimaryColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: _isPosting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text(
                                  'Post',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    
                    // Scrollable content
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 24),
                            
                            // Modern post type selection
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _buildFilterChip(
                                      label: 'Announcement',
                                      selected: selectedType == PostType.announcement,
                                      onSelected: (selected) {
                                        setState(() {
                                          selectedType = PostType.announcement;
                                        });
                                      },
                                      color: Colors.blue,
                                    ),
                                    const SizedBox(width: 12),
                                    _buildFilterChip(
                                      label: 'Assignment',
                                      selected: selectedType == PostType.assignment,
                                      onSelected: (selected) {
                                        setState(() {
                                          selectedType = PostType.assignment;
                                        });
                                      },
                                      color: Colors.orange,
                                    ),
                                    const SizedBox(width: 12),
                                    _buildFilterChip(
                                      label: 'Material',
                                      selected: selectedType == PostType.material,
                                      onSelected: (selected) {
                                        setState(() {
                                          selectedType = PostType.material;
                                        });
                                      },
                                      color: Colors.green,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Enhanced title TextField
                            TextField(
                              controller: _announcementController,
                              style: const TextStyle(
                                color: kTextPrimaryColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                hintText: selectedType == PostType.assignment 
                                    ? 'Enter assignment title...'
                                    : selectedType == PostType.material
                                        ? 'Enter material title...'
                                        : 'Announce something to your class',
                                hintStyle: TextStyle(
                                  color: kTextSecondaryColor,
                                  fontSize: 18,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: kPrimaryColor),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                                contentPadding: const EdgeInsets.all(16),
                              ),
                              maxLines: null,
                            ),

                            const SizedBox(height: 16),

                            // Enhanced instructions TextField
                            TextField(
                              controller: _instructionController,
                              style: const TextStyle(
                                color: kTextPrimaryColor,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                hintText: selectedType == PostType.assignment 
                                    ? 'Add assignment instructions...'
                                    : selectedType == PostType.material
                                        ? 'Add material description...'
                                        : 'Add announcement details...',
                                hintStyle: TextStyle(
                                  color: kTextSecondaryColor,
                                  fontSize: 16,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: kPrimaryColor),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                                contentPadding: const EdgeInsets.all(16),
                              ),
                              maxLines: 5,
                            ),

                            // Enhanced due date picker
                            _buildDueDatePicker(selectedType),

                            // Modern attachment button
                            Container(
                              margin: const EdgeInsets.only(top: 16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  Icons.attach_file,
                                  color: kPrimaryColor,
                                ),
                                title: const Text(
                                  'Add attachment',
                                  style: TextStyle(
                                    color: kTextPrimaryColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.add_circle_outline,
                                  color: kPrimaryColor,
                                ),
                                onTap: () => _showAttachmentOptions(setState), // Pass setState here
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            // Add this container right after for instant display
                            if (_selectedImage != null || _selectedDocument != null)
                              Container(
                                margin: const EdgeInsets.only(top: 16),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Text(
                                        'Attachments',
                                        style: TextStyle(
                                          color: kTextPrimaryColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (_selectedImage != null)
                                      Stack(
                                        children: [
                                          Container(
                                            width: double.infinity,
                                            height: 200,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: Image.file(
                                                _selectedImage!,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 8,
                                            right: 8,
                                            child: IconButton(
                                              icon: const Icon(Icons.close),
                                              onPressed: () {
                                                setState(() {
                                                  _selectedImage = null;
                                                });
                                              },
                                              style: IconButton.styleFrom(
                                                backgroundColor: Colors.white.withOpacity(0.8),
                                                padding: const EdgeInsets.all(8),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    if (_selectedDocument != null)
                                      ListTile(
                                        leading: const Icon(Icons.insert_drive_file),
                                        title: Text(
                                          _documentName ?? 'Document',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.close),
                                          onPressed: () {
                                            setState(() {
                                              _selectedDocument = null;
                                              _documentName = null;
                                            });
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Add this helper method for filter chips
  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required Function(bool) onSelected,
    required Color color,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      backgroundColor: Colors.grey[100],
      selectedColor: color.withOpacity(0.15),
      checkmarkColor: color,
      labelStyle: TextStyle(
        color: selected ? color : kTextSecondaryColor,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? color : Colors.grey[300]!,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _announcementController.dispose();
    _instructionController.dispose(); // Add this line
    super.dispose();
  }

  String _classCode = '';
  String _lecturerName = '';

  @override
  void initState() {
    super.initState();
    _loadClassInfo();
    _checkLecturerStatus();
    // Add these lines for debugging
    _updateAndPrintFCMToken();
  }

  // Add this method
  Future<void> _updateAndPrintFCMToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      String? token = await FirebaseMessaging.instance.getToken();
      print('Current FCM Token: $token'); // Debugging line

      // Update token in Firestore
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      });

      // Verify token was saved
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      print('Saved FCM Token: ${userDoc.data()?['fcmToken']}'); // Debugging line
    } catch (e) {
      print('Error updating FCM token: $e');
    }
  }

  // Add this method to load class information
  Future<void> _loadClassInfo() async {
    try {
      final classDoc = await FirebaseFirestore.instance
          .collection('classes')
          .doc(widget.classId)
          .get();

      if (mounted && classDoc.exists) {
        setState(() {
          _classCode = classDoc.data()?['code'] ?? 'No code available';
          _lecturerName = classDoc.data()?['lecturer'] ?? 'No lecturer assigned'; // Fixed: changed 'Lecturer' to 'lecturer'
        });
      }
    } catch (e) {
      print('Error loading class info: $e');
      setState(() {
        _classCode = 'Error loading code';
        _lecturerName = 'Error loading lecturer info';
      });
    }
  }

  // Add this method to check lecturer status
  Future<void> _checkLecturerStatus() async {
  try {
    // Get current user's ID
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // Get user's role from users collection
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();
    
    if (mounted && userDoc.exists) {
      // Check if user's role is "Lecturer"
      setState(() {
        _isLecturer = userDoc.data()?['role'] == 'Lecturer';
      });
    }
  } catch (e) {
    print('Error checking lecturer status: $e');
  }
}

  // Add this method to show class info dialog
  void _showClassInfo() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF202124),
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Class Information',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.class_, color: Colors.blue),
                  title: const Text(
                    'Class Code',
                    style: TextStyle(color: Colors.grey),
                  ),
                  subtitle: Text(
                    _classCode,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person, color: Colors.green),
                  title: const Text(
                    'Lecturer',
                    style: TextStyle(color: Colors.grey),
                  ),
                  subtitle: Text(
                    _lecturerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          widget.className,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.black87),
            onPressed: _showClassInfo,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black87),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        children: [
          // Modern Header Card with Glass Effect
          Container(
            height: 180,
            margin: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.blue[700]!,
                      Colors.purple[500]!,
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    // Decorative circle
                    Positioned(
                      right: -20,
                      top: -20,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                    ),
                    // Content
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            widget.className,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.key,
                                  size: 16,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Class Code: $_classCode',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Conditionally show the create post card
          if (_isLecturer)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  backgroundColor: Colors.blue[100],
                  child: const Icon(Icons.add, color: Colors.blue),
                ),
                title: const Text(
                  'Create something for your class',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                  ),
                ),
                onTap: () => _showAnnouncementDialog(context),
              ),
            ),

          // Announcements List
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('classes')
                .doc(widget.classId)
                .collection('announcements')
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  final announcement = snapshot.data!.docs[index];
                  final type = announcement['type'] as String;
                  final color = type == 'assignment'
                      ? Colors.orange
                      : type == 'material'
                          ? Colors.blue
                          : Colors.green;

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            backgroundColor: color.withOpacity(0.1),
                            child: Icon(
                              type == 'assignment'
                                  ? Icons.assignment
                                  : type == 'material'
                                      ? Icons.article
                                      : Icons.announcement,
                              color: color,
                            ),
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  type.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: color,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                announcement['text'] ?? '',
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Posted ${announcement['timestamp']?.toDate().toString().split('.')[0] ?? 'Recently'}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ),
                          trailing: Icon(Icons.chevron_right, color: color),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ClassDetails(
                                  announcement: {
                                    ...announcement.data() as Map<String, dynamic>,
                                    'id': announcement.id, // Add this line
                                  },
                                  classId: widget.classId,
                                ),
                              ),
                            );
                          },
                        ),
                        if (announcement['imageUrl'] != null ||
                            announcement['documentUrl'] != null)
                          Container(
                            padding: const EdgeInsets.only(
                              left: 72,
                              right: 16,
                              bottom: 16,
                            ),
                            child: Row(
                              children: [
                                if (announcement['imageUrl'] != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.image_outlined,
                                          color: Colors.grey[600],
                                          size: 16,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Image',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (announcement['documentUrl'] != null)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.attachment,
                                          color: Colors.grey[600],
                                          size: 16,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Document',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: widget.onPageChange == null
          ? BottomNavigationBar(
              backgroundColor: Colors.white,
              selectedItemColor: Colors.blue,
              unselectedItemColor: Colors.grey[400],
              currentIndex: 0,
              elevation: 8,
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.forum_outlined),
                  label: 'Stream',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.assignment_outlined),
                  label: 'Classwork',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.people_outline),
                  label: 'Participants',
                ),
              ],
              onTap: (index) {
                if (index == 1) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Classwork(
                        classId: widget.classId,
                        className: widget.className,
                      ),
                    ),
                  );
                } else if (index == 2) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Participants(
                        classId: widget.classId,
                        className: widget.className,
                      ),
                    ),
                  );
                }
              },
            )
          : null,
    );
  }
}

Future<DateTime?> showDateTimePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) async {
  final DateTime? date = await showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
  );
  if (date == null) return null;

  final TimeOfDay? time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initialDate),
  );

  return time == null
      ? null
      : DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
}