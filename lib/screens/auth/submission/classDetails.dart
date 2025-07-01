import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:image_picker/image_picker.dart';
import 'package:twitterr/helper/image_helper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// Define color scheme constants
const Color kPrimaryColor = Color(0xFF4A90E2); // Modern blue
const Color kBackgroundColor = Color(0xFFF8F9FA); // Light gray background
const Color kSurfaceColor = Colors.white;
const Color kTextPrimaryColor = Color(0xFF2C3E50); // Dark blue-gray
const Color kTextSecondaryColor = Color(0xFF95A5A6); // Muted gray
const Color kAccentColor = Color(0xFF1ABC9C); // Teal accent

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
    builder: (context, child) {
      return Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.blue,
            surface: Color(0xFF202124),
          ),
        ),
        child: child!,
      );
    },
  );
  
  if (date == null) return null;

  final TimeOfDay? time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initialDate),
    builder: (context, child) {
      return Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.blue,
            surface: Color(0xFF202124),
          ),
        ),
        child: child!,
      );
    },
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

class ClassDetails extends StatefulWidget {
  final Map<String, dynamic> announcement;
  final String classId;

  const ClassDetails({
    Key? key,
    required this.announcement,
    required this.classId,
  }) : super(key: key);

  @override
  State<ClassDetails> createState() => _ClassDetailsState();
}

class _ClassDetailsState extends State<ClassDetails> {
  final TextEditingController _commentController = TextEditingController();
  File? _selectedWorkFile;
  String? _workFileName;
  bool _isUploading = false;
  bool _isSubmitted = false;
  bool _isLoading = false;
  String _submissionStatus = 'Not handed in yet';  // Add this line
  bool _isLateSubmission = false; // Add this property
  StreamSubscription<QuerySnapshot>? _submissionSubscription;
  String? _draftFileUrl;
  String? _draftId;
  bool _isLecturer = false; // Add this property
  List<Map<String, dynamic>> _studentSubmissions = []; // Add this property
  List<Map<String, dynamic>> _allSubmissions = []; // Store all submissions
  String? _selectedStudentId; // Currently selected student
  String _submissionFilter = 'all'; // 'all', 'submitted', 'not_submitted'

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  Future<void> _initializeUser() async {
    await _checkLecturerStatus();
    _checkSubmissionStatus();
    if (_isLecturer && widget.announcement['type'] == 'assignment') {
      await _loadStudentSubmissions();
    }
  }

  // Add this method to check lecturer status
  Future<void> _checkLecturerStatus() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      
      if (mounted && userDoc.exists) {
        setState(() {
          _isLecturer = userDoc.data()?['role'] == 'Lecturer';
        });
      }
    } catch (e) {
      print('Error checking lecturer status: $e');
    }
  }

  // Add this method to load student submissions
  Future<void> _loadStudentSubmissions() async {
    try {
      // Get class participants
      final classDoc = await FirebaseFirestore.instance
          .collection('classes')
          .doc(widget.classId)
          .get();

      if (!classDoc.exists) return;

      final participants = List<String>.from(classDoc.data()?['participants'] ?? []);
      
      // Get all students in the class
      final studentsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'Student')
          .where(FieldPath.documentId, whereIn: participants)
          .get();

      // Get submissions for this assignment
      final submissionsSnapshot = await FirebaseFirestore.instance
          .collection('classes')
          .doc(widget.classId)
          .collection('submissions')
          .where('assignmentId', isEqualTo: widget.announcement['id'])
          .get();

      List<Map<String, dynamic>> allStudents = [];
      List<Map<String, dynamic>> submissions = [];
      
      // Create map of submissions by student ID
      Map<String, Map<String, dynamic>> submissionsByStudent = {};
      for (var doc in submissionsSnapshot.docs) {
        final submissionData = doc.data();
        submissionsByStudent[submissionData['studentId']] = {
          'submissionId': doc.id,
          'fileName': submissionData['fileName'],
          'fileUrl': submissionData['fileUrl'],
          'submittedAt': submissionData['submittedAt'],
          'isLate': submissionData['isLate'] ?? false,
          'isImage': submissionData['isImage'] ?? false,
        };
      }

      // Create complete list with all students
      for (var studentDoc in studentsSnapshot.docs) {
        final studentData = studentDoc.data();
        final studentId = studentDoc.id;
        final hasSubmission = submissionsByStudent.containsKey(studentId);
        
        Map<String, dynamic> studentInfo = {
          'studentId': studentId,
          'studentName': studentData['name'] ?? 'Unknown Student',
          'studentEmail': studentData['email'] ?? '',
          'hasSubmission': hasSubmission,
        };

        if (hasSubmission) {
          studentInfo.addAll(submissionsByStudent[studentId]!);
          submissions.add(studentInfo);
        }
        
        allStudents.add(studentInfo);
      }

      if (mounted) {
        setState(() {
          _allSubmissions = allStudents;
          _studentSubmissions = _filterSubmissions();
        });
      }
    } catch (e) {
      print('Error loading student submissions: $e');
    }
  }

  // Add method to filter submissions based on current selection
  List<Map<String, dynamic>> _filterSubmissions() {
    List<Map<String, dynamic>> filtered = List.from(_allSubmissions);
    
    // Filter by submission status
    if (_submissionFilter == 'submitted') {
      filtered = filtered.where((student) => student['hasSubmission'] == true).toList();
    } else if (_submissionFilter == 'not_submitted') {
      filtered = filtered.where((student) => student['hasSubmission'] == false).toList();
    }
    
    // Filter by selected student
    if (_selectedStudentId != null) {
      filtered = filtered.where((student) => student['studentId'] == _selectedStudentId).toList();
    }
    
    return filtered;
  }

  void _checkSubmissionStatus() {
    _submissionSubscription = FirebaseFirestore.instance
        .collection('classes')
        .doc(widget.classId)
        .collection('submissions')
        .where('studentId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
        .where('assignmentId', isEqualTo: widget.announcement['id']) // Add this line
        .snapshots()
        .listen((snapshot) async {
          if (mounted) {
            // Check drafts for this specific assignment
            final draftSnapshot = await FirebaseFirestore.instance
                .collection('classes')
                .doc(widget.classId)
                .collection('drafts')
                .where('studentId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                .where('assignmentId', isEqualTo: widget.announcement['id']) // Add this line
                .get();

            setState(() {
              if (draftSnapshot.docs.isNotEmpty) {
                final draft = draftSnapshot.docs.first.data();
                _draftFileUrl = draft['fileUrl'];
                _workFileName = draft['fileName'];
                _draftId = draftSnapshot.docs.first.id;
              }

              if (snapshot.docs.isNotEmpty) {
                final submission = snapshot.docs.first.data();
                _isSubmitted = submission['submitted'] ?? false;
                _workFileName = submission['fileName'];
                _isLateSubmission = submission['isLate'] ?? false;
                _submissionStatus = _isSubmitted 
                    ? _isLateSubmission 
                        ? 'Handed in late'
                        : 'Handed in'
                    : 'Not handed in yet';
                
                // Get the file URL from submission if submitted
                if (_isSubmitted) {
                  _draftFileUrl = submission['fileUrl'];
                }
              } else {
                _isSubmitted = false;
                _submissionStatus = 'Not handed in yet';
                _isLateSubmission = false;
              }
            });
          }
        });
  }

  Future<void> _pickWork() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final path = result.files.single.path;
        if (path != null) {
          setState(() {
            _selectedWorkFile = File(path);
            _workFileName = result.files.single.name;
          });
        }
      }
    } catch (e) {
      print('Error picking file: $e');
    }
  }

  // Add this method to handle file upload
  Future<void> _uploadWork() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedWorkFile = File(result.files.single.path!);
          _workFileName = result.files.single.name;
        });

        // Auto-submit when file is selected
        await _submitWork(isImage: false);
      }
    } catch (e) {
      print('Error uploading work: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error uploading file')),
      );
    }
  }

  Future<void> _submitWork({required bool isImage}) async {
    if (_draftFileUrl == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      bool isLate = false;
      if (widget.announcement['dueDate'] != null) {
        final dueDate = (widget.announcement['dueDate'] as Timestamp).toDate();
        isLate = DateTime.now().isAfter(dueDate);
      }

      // Create submission using draft file
      await FirebaseFirestore.instance
          .collection('classes')
          .doc(widget.classId)
          .collection('submissions')
          .add({
        'fileName': _workFileName,
        'fileUrl': _draftFileUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'studentId': FirebaseAuth.instance.currentUser?.uid,
        'assignmentId': widget.announcement['id'], // Make sure this is set
        'isImage': isImage,
        'submitted': true,
        'submittedAt': FieldValue.serverTimestamp(),
        'isLate': isLate,
      });

      // Delete the draft document but keep the file
      if (_draftId != null) {
        await FirebaseFirestore.instance
            .collection('classes')
            .doc(widget.classId)
            .collection('drafts')
            .doc(_draftId)
            .delete();
      }

      setState(() {
        _isLoading = false;
        _isSubmitted = true;
        _isLateSubmission = isLate;
        _draftId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isLate ? 'Work submitted late' : 'Work submitted successfully'),
          backgroundColor: isLate ? Colors.orange : Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting work: $e')),
      );
    }
  }

  // Add this method to handle saving to drafts
  Future<void> _saveToDrafts(String fileUrl, String fileName, bool isImage) async {
    try {
      // Delete existing draft if any
      if (_draftId != null) {
        await _deleteDraft();
      }

      // Create new draft
      final draftRef = await FirebaseFirestore.instance
          .collection('classes')
          .doc(widget.classId)
          .collection('drafts')
          .add({
        'fileName': fileName,
        'fileUrl': fileUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'studentId': FirebaseAuth.instance.currentUser?.uid,
        'assignmentId': widget.announcement['id'], // Add this line
        'isImage': isImage,
      });

      _draftId = draftRef.id;
      _draftFileUrl = fileUrl;
    } catch (e) {
      print('Error saving to drafts: $e');
    }
  }

  // Add this method to handle deleting draft
  Future<void> _deleteDraft() async {
    try {
      if (_draftId != null) {
        // Delete file from storage
        if (_draftFileUrl != null) {
          try {
            final ref = FirebaseStorage.instance.refFromURL(_draftFileUrl!);
            await ref.delete();
          } catch (e) {
            print('Error deleting draft file from storage: $e');
          }
        }

        // Delete draft document
        await FirebaseFirestore.instance
            .collection('classes')
            .doc(widget.classId)
            .collection('drafts')
            .doc(_draftId)
            .delete();

        _draftId = null;
        _draftFileUrl = null;
      }
    } catch (e) {
      print('Error deleting draft: $e');
    }
  }

  Future<void> _showUploadOptions() async {
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
                title: const Text(
                  'Take Photo',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final picker = ImagePicker();
                  final pickedFile = await picker.pickImage(source: ImageSource.camera);
                  if (pickedFile != null) {
                    setState(() {
                      _selectedWorkFile = File(pickedFile.path);
                      _workFileName = path.basename(pickedFile.path);
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.white),
                title: const Text(
                  'Choose from Gallery',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final picker = ImagePicker();
                  final pickedFile = await picker.pickImage(source: ImageSource.gallery);
                  if (pickedFile != null) {
                    setState(() {
                      _isLoading = true;
                    });

                    try {
                      File imageFile = File(pickedFile.path);
                      final downloadUrl = await ImageHelper.uploadImageToFirebase(imageFile);
                      
                      if (downloadUrl != null) {
                        await _saveToDrafts(
                          downloadUrl,
                          path.basename(pickedFile.path),
                          true,
                        );

                        setState(() {
                          _selectedWorkFile = imageFile;
                          _workFileName = path.basename(pickedFile.path);
                        });
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error uploading image: $e')),
                      );
                    } finally {
                      setState(() {
                        _isLoading = false;
                      });
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.upload_file, color: Colors.white),
                title: const Text(
                  'Upload File',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  FilePickerResult? result = await FilePicker.platform.pickFiles(
                    type: FileType.any,
                  );
                  if (result != null) {
                    setState(() {
                      _isLoading = true;
                    });

                    try {
                      File file = File(result.files.single.path!);
                      // Upload file to Firebase Storage
                      final fileName = path.basename(file.path);
                      final ref = FirebaseStorage.instance
                          .ref()
                          .child('drafts')
                          .child(widget.classId)
                          .child(DateTime.now().millisecondsSinceEpoch.toString() + '_' + fileName);
                      
                      await ref.putFile(file);
                      final downloadUrl = await ref.getDownloadURL();

                      // Save to drafts
                      await _saveToDrafts(
                        downloadUrl,
                        result.files.single.name,
                        false,
                      );

                      setState(() {
                        _selectedWorkFile = file;
                        _workFileName = result.files.single.name;
                      });
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error uploading file: $e')),
                      );
                    } finally {
                      setState(() {
                        _isLoading = false;
                      });
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _changeDueDate() async {
    final DateTime? picked = await showDateTimePicker(
      context: context,
      initialDate: widget.announcement['dueDate'] != null 
          ? (widget.announcement['dueDate'] as Timestamp).toDate()
          : DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      try {
        await FirebaseFirestore.instance
            .collection('classes')
            .doc(widget.classId)
            .collection('announcements')
            .doc(widget.announcement['id'])
            .update({
          'dueDate': Timestamp.fromDate(picked),
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Due date updated successfully')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating due date: $e')),
        );
      }
    }
  }

  Future<void> _deleteAnnouncement() async {
    // Show confirmation dialog
    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF202124),
          title: const Text(
            'Delete announcement?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'This action cannot be undone.',
            style: TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      try {
        // Delete the announcement
        await FirebaseFirestore.instance
            .collection('classes')
            .doc(widget.classId)
            .collection('announcements')
            .doc(widget.announcement['id'])
            .delete();

        // Delete associated files if they exist
        if (widget.announcement['imageUrl'] != null) {
          await FirebaseStorage.instance
              .refFromURL(widget.announcement['imageUrl'])
              .delete();
        }
        if (widget.announcement['documentUrl'] != null) {
          await FirebaseStorage.instance
              .refFromURL(widget.announcement['documentUrl'])
              .delete();
        }

        // Navigate back after deletion
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Announcement deleted')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting announcement: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: kSurfaceColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimaryColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: kTextPrimaryColor),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) async {
              switch (value) {
                case 'change_due_date':
                  if (widget.announcement['type'] == 'assignment') {
                    await _changeDueDate();
                  }
                  break;
                case 'delete':
                  await _deleteAnnouncement();
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              if (widget.announcement['type'] == 'assignment')
                const PopupMenuItem<String>(
                  value: 'change_due_date',
                  child: ListTile(
                    leading: Icon(
                      Icons.schedule,
                      color: Color.fromARGB(255, 82, 45, 45),
                    ),
                    title: Text(
                      'Change due date',
                      style: TextStyle(color: Color.fromARGB(255, 82, 45, 45)),
                    ),
                    contentPadding: EdgeInsets.zero,
                    minLeadingWidth: 24,
                  ),
                ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                  ),
                  title: Text(
                    'Delete announcement',
                    style: TextStyle(color: Colors.red),
                  ),
                  contentPadding: EdgeInsets.zero,
                  minLeadingWidth: 24,
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        children: [
          // Modern header section
          Container(
            margin: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.announcement['type'] == 'assignment' && 
                    widget.announcement['dueDate'] != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: kPrimaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule, color: kPrimaryColor, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Due ${(widget.announcement['dueDate'] as Timestamp).toDate().toString().split('.')[0]}',
                          style: TextStyle(
                            color: kPrimaryColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  widget.announcement['text'] ?? '',
                  style: const TextStyle(
                    color: kTextPrimaryColor,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),

          // Modern instructions card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: kSurfaceColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: kPrimaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          widget.announcement['type'] == 'assignment'
                              ? Icons.assignment_outlined
                              : Icons.description_outlined,
                          color: kPrimaryColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        widget.announcement['type'] == 'assignment'
                            ? 'Instructions'
                            : 'Description',
                        style: const TextStyle(
                          color: kTextPrimaryColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.announcement['instructions'] ?? 'No details provided.',
                    style: TextStyle(
                      color: kTextPrimaryColor.withOpacity(0.8),
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Attachments Section with Modern Cards
          if (widget.announcement['imageUrl'] != null ||
              widget.announcement['documentUrl'] != null)
            Container(
              margin: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Attachments',
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Rest of the attachments section
                  if (widget.announcement['imageUrl'] != null)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                            child: Image.network(
                              widget.announcement['imageUrl']!,
                              fit: BoxFit.cover,
                            ),
                          ),
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.image_outlined,
                                color: Colors.blue,
                              ),
                            ),
                            title: const Text(
                              'Image attachment',
                              style: TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.visibility_outlined,
                                    color: Colors.blue,
                                  ),
                                  onPressed: () => _openImageViewer(
                                    widget.announcement['imageUrl']!,
                                    'image_${DateTime.now().millisecondsSinceEpoch}.jpg',
                                  ),
                                  tooltip: 'View image',
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.download_outlined,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () => _downloadFile(
                                    widget.announcement['imageUrl']!,
                                    'image_${DateTime.now().millisecondsSinceEpoch}.jpg',
                                  ),
                                  tooltip: 'Download image',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Document attachment with modern card
                  if (widget.announcement['documentUrl'] != null)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.picture_as_pdf,
                            color: Colors.red,
                            size: 28,
                          ),
                        ),
                        title: Text(
                          widget.announcement['documentName'] ?? 'Document',
                          style: const TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          'PDF Document',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_canViewInApp(widget.announcement['documentName'] ?? 'document.pdf'))
                              IconButton(
                                icon: const Icon(
                                  Icons.visibility_outlined,
                                  color: Colors.blue,
                                ),
                                onPressed: () {
                                  final fileName = widget.announcement['documentName'] ?? 'document.pdf';
                                  if (fileName.toLowerCase().endsWith('.pdf')) {
                                    _openPdfViewer(
                                      widget.announcement['documentUrl']!,
                                      fileName,
                                    );
                                  } else {
                                    _openImageViewer(
                                      widget.announcement['documentUrl']!,
                                      fileName,
                                    );
                                  }
                                },
                                tooltip: 'View file',
                              ),
                            IconButton(
                              icon: const Icon(
                                Icons.download_outlined,
                                color: Colors.grey,
                              ),
                              onPressed: () => _downloadFile(
                                widget.announcement['documentUrl']!,
                                widget.announcement['documentName'] ?? 'document.pdf',
                              ),
                              tooltip: 'Download file',
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // Your Work Section for students or Student Submissions for lecturers
          if (widget.announcement['type'] == 'assignment')
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  title: Row(
                    children: [
                      Icon(
                        Icons.assignment_outlined,
                        color: Colors.blue[700],
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _isLecturer ? 'Student Submissions' : 'Your work',
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!_isLecturer)
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _isSubmitted
                                  ? _isLateSubmission
                                      ? Colors.orange[50]
                                      : Colors.green[50]
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _submissionStatus,
                              style: TextStyle(
                                color: _isSubmitted
                                    ? _isLateSubmission
                                        ? Colors.orange[700]
                                        : Colors.green[700]
                                    : Colors.grey[600],
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      if (_isLecturer)
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _submissionFilter == 'not_submitted'
                                  ? '${_studentSubmissions.length} not submitted'
                                  : '${_studentSubmissions.where((s) => s['hasSubmission'] == true).length}/${_studentSubmissions.length} submitted',
                              style: TextStyle(
                                color: Colors.blue[700],
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
                  children: [
                    if (_isLecturer) ...[
                      _buildStudentFilter(),
                      _buildStudentSubmissionsList(),
                    ] else if (!_isSubmitted)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            // Show selected file/image if available
                            if (_selectedWorkFile != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[200]!),
                                ),
                                child: Column(
                                  children: [
                                    if (_workFileName?.toLowerCase().endsWith('.jpg') == true ||
                                        _workFileName?.toLowerCase().endsWith('.jpeg') == true ||
                                        _workFileName?.toLowerCase().endsWith('.png') == true)
                                      Container(
                                        height: 200,
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          borderRadius: const BorderRadius.vertical(
                                            top: Radius.circular(12),
                                          ),
                                          image: DecorationImage(
                                            image: FileImage(_selectedWorkFile!),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: _getFileTypeColor(_workFileName ?? '').withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Icon(
                                              _getFileIcon(_workFileName ?? ''),
                                              color: _getFileTypeColor(_workFileName ?? ''),
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _getFileType(_workFileName ?? ''),
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  _workFileName ?? 'Unnamed file',
                                                  style: const TextStyle(
                                                    color: Colors.black87,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.close),
                                            color: Colors.grey[600],
                                            onPressed: _removeAttachment,
                                            tooltip: 'Remove attachment',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Upload button
                            InkWell(
                              onTap: _showUploadOptions,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.withOpacity(0.3),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_circle_outline,
                                      color: Colors.blue[400],
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Add or create',
                                      style: TextStyle(
                                        color: Colors.blue[400],
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Submit button
                            if (_selectedWorkFile != null)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(top: 16),
                                child: ElevatedButton(
                                  onPressed: _isLoading 
                                      ? null 
                                      : () => _submitWork(
                                          isImage: _workFileName?.toLowerCase().endsWith('.jpg') ?? false ||
                                                 _workFileName!.toLowerCase().endsWith('.png') ?? false
                                    ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        )
                                      : const Text(
                                          'Hand in',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                          ),
                                        ),
                                ),
                              ),
                          ],
                        ),
                      )
                    else
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF2C3E50).withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF2C3E50).withOpacity(0.1),
                                ),
                              ),
                              child: Column(
                                children: [
                                  // Display image if it's an image file
                                  if (_isImageFile(_workFileName ?? '') && _draftFileUrl != null)
                                    Container(
                                      height: 200,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(12),
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(12),
                                        ),
                                        child: Image.network(
                                          _draftFileUrl!,
                                          fit: BoxFit.cover,
                                          loadingBuilder: (context, child, loadingProgress) {
                                            if (loadingProgress == null) return child;
                                            return Container(
                                              height: 200,
                                              child: Center(
                                                child: CircularProgressIndicator(
                                                  value: loadingProgress.expectedTotalBytes != null
                                                      ? loadingProgress.cumulativeBytesLoaded /
                                                          loadingProgress.expectedTotalBytes!
                                                      : null,
                                                ),
                                              ),
                                            );
                                          },
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              height: 200,
                                              child: Center(
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.error_outline,
                                                      color: Colors.grey[400],
                                                      size: 48,
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      'Could not load image',
                                                      style: TextStyle(
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  // File info
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: _getFileTypeColor(_workFileName ?? '').withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          _getFileIcon(_workFileName ?? ''),
                                          color: _getFileTypeColor(_workFileName ?? ''),
                                          size: 24,
                                        ),
                                      ),
                                      title: Text(
                                        _workFileName ?? 'Unnamed file',
                                        style: const TextStyle(
                                          color: Color(0xFF2C3E50),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          _getFileType(_workFileName ?? ''),
                                          style: TextStyle(
                                            color: const Color(0xFF2C3E50).withOpacity(0.7),
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      trailing: _isLoading
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : PopupMenuButton<String>(
                                              icon: const Icon(
                                                Icons.more_vert,
                                                color: Color(0xFF2C3E50),
                                              ),
                                              onSelected: (value) {
                                                if (value == 'remove') {
                                                  _removeAttachment();
                                                } else if (value == 'download') {
                                                  if (_draftFileUrl != null) {
                                                    _downloadFile(_draftFileUrl!, _workFileName ?? 'file');
                                                  }
                                                } else if (value == 'view') {
                                                  if (_draftFileUrl != null && _workFileName != null) {
                                                    if (_workFileName!.toLowerCase().endsWith('.pdf')) {
                                                      _openPdfViewer(_draftFileUrl!, _workFileName!);
                                                    } else {
                                                      _openImageViewer(_draftFileUrl!, _workFileName!);
                                                    }
                                                  }
                                                }
                                              },
                                              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                                if (_canViewInApp(_workFileName ?? ''))
                                                  const PopupMenuItem<String>(
                                                    value: 'view',
                                                    child: ListTile(
                                                      leading: Icon(
                                                        Icons.visibility_outlined,
                                                        color: Color(0xFF3498DB),
                                                      ),
                                                      title: Text(
                                                        'View file',
                                                        style: TextStyle(
                                                          color: Color(0xFF3498DB),
                                                        ),
                                                      ),
                                                      contentPadding: EdgeInsets.zero,
                                                      minLeadingWidth: 24,
                                                    ),
                                                  ),
                                                const PopupMenuItem<String>(
                                                  value: 'download',
                                                  child: ListTile(
                                                    leading: Icon(
                                                      Icons.download_outlined,
                                                      color: Color(0xFF3498DB),
                                                    ),
                                                    title: Text(
                                                      'Download file',
                                                      style: TextStyle(
                                                        color: Color(0xFF3498DB),
                                                      ),
                                                    ),
                                                    contentPadding: EdgeInsets.zero,
                                                    minLeadingWidth: 24,
                                                  ),
                                                ),
                                                const PopupMenuItem<String>(
                                                  value: 'remove',
                                                  child: ListTile(
                                                    leading: Icon(
                                                      Icons.delete_outline,
                                                      color: Color(0xFFE74C3C),
                                                    ),
                                                    title: Text(
                                                      'Remove attachment',
                                                      style: TextStyle(
                                                        color: Color(0xFFE74C3C),
                                                      ),
                                                    ),
                                                    contentPadding: EdgeInsets.zero,
                                                    minLeadingWidth: 24,
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _unsubmitWork,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF34495E),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 0,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Text(
                                        'Unsubmit',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
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
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _submissionSubscription?.cancel(); // Add this line
    super.dispose();
  }

  // Update the _unsubmitWork method
  Future<void> _unsubmitWork() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final submissions = await FirebaseFirestore.instance
          .collection('classes')
          .doc(widget.classId)
          .collection('submissions')
          .where('studentId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .where('assignmentId', isEqualTo: widget.announcement['id']) // Add this line
          .get();

      if (submissions.docs.isNotEmpty) {
        final submission = submissions.docs.first;
        final fileUrl = submission.data()['fileUrl'];
        final fileName = submission.data()['fileName'];
        final isImage = submission.data()['isImage'];

        // Move to drafts
        await _saveToDrafts(fileUrl, fileName, isImage);

        // Delete submission
        await submission.reference.delete();
      }

      setState(() {
        _isLoading = false;
        _isSubmitted = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Work moved to drafts')),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error unsubmitting work: $e')),
      );
    }
  }

  // Add method to open image in full screen
  void _openImageViewer(String imageUrl, String fileName) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageViewerScreen(
          imageUrl: imageUrl,
          fileName: fileName,
        ),
      ),
    );
  }

  // Add method to open PDF viewer
  void _openPdfViewer(String pdfUrl, String fileName) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PdfViewerScreen(
          pdfUrl: pdfUrl,
          fileName: fileName,
        ),
      ),
    );
  }

  // Add method to determine if file can be viewed in-app
  bool _canViewInApp(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'pdf'].contains(extension);
  }

  // Add this method to download files
  Future<void> _downloadFile(String url, String fileName) async {
    try {
      bool permissionGranted = false;
      
      if (Platform.isAndroid) {
        if (await Permission.storage.request().isGranted ||
            await Permission.manageExternalStorage.request().isGranted) {
          permissionGranted = true;
        }
        
        // For Android 13 and above
        if (!permissionGranted) {
          if (await Permission.photos.request().isGranted &&
              await Permission.videos.request().isGranted) {
            permissionGranted = true;
          }
        }
      } else {
        permissionGranted = true; // iOS handles permissions differently
      }

      if (permissionGranted) {
        setState(() {
          _isLoading = true;
        });

        // Get download directory
        Directory? directory;
        if (Platform.isAndroid) {
          directory = Directory('/storage/emulated/0/Download');
          // Create directory if it doesn't exist
          if (!await directory.exists()) {
            directory = await getExternalStorageDirectory();
          }
        } else {
          directory = await getApplicationDocumentsDirectory();
        }

        if (directory == null) throw Exception('Could not access storage');

        String savePath = '${directory.path}/$fileName';

      // Download file
      await Dio().download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            print('${(received / total * 100).toStringAsFixed(0)}%');
          }
        },
      );

      setState(() {
        _isLoading = false;
      });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded to: $savePath'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please grant storage permission in app settings'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: openAppSettings,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error downloading file: $e')),
      );
    }
  }

  // Update the remove attachment handler
  Future<void> _removeAttachment() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Delete from drafts if it exists
      if (_draftId != null) {
        await _deleteDraft();
      }
      
      // Delete from submissions if it exists
      final submissions = await FirebaseFirestore.instance
          .collection('classes')
          .doc(widget.classId)
          .collection('submissions')
          .where('studentId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .where('assignmentId', isEqualTo: widget.announcement['id']) // Add this line
          .get();

      if (submissions.docs.isNotEmpty) {
        final submission = submissions.docs.first;
        final fileUrl = submission.data()['fileUrl'];
        
        // Delete file from storage
        if (fileUrl != null) {
          try {
            final ref = FirebaseStorage.instance.refFromURL(fileUrl);
            await ref.delete();
          } catch (e) {
            print('Error deleting file from storage: $e');
          }
        }
        
        // Delete submission document
        await submission.reference.delete();
      }

      setState(() {
        _isLoading = false;
        _selectedWorkFile = null;
        _workFileName = null;
        _isSubmitted = false;
        _submissionStatus = 'Not handed in yet';
        _draftFileUrl = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File removed successfully')),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error removing file: $e')),
      );
    }
  }

  String _getFileType(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return 'PDF Document';
      case 'doc':
      case 'docx':
        return 'Word Document';
      case 'jpg':
      case 'jpeg':
      case 'png':
        return 'Image File';
      case 'txt':
        return 'Text Document';
      default:
        return 'File';
    }
  }

  IconData _getFileIcon(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      case 'txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileTypeColor(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return const Color(0xFFE74C3C); // Red
      case 'doc':
      case 'docx':
        return const Color(0xFF3498DB); // Blue
      case 'jpg':
      case 'jpeg':
      case 'png':
        return const Color(0xFF27AE60); // Green
      case 'txt':
        return const Color(0xFFF39C12); // Orange
      default:
        return const Color(0xFF95A5A6); // Gray
    }
  }

  bool _isImageFile(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(extension);
  }

  // Add method to build student filter
  Widget _buildStudentFilter() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter by submission status
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _submissionFilter,
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                      ),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _submissionFilter = newValue;
                            _studentSubmissions = _filterSubmissions();
                          });
                        }
                      },
                      items: const [
                        DropdownMenuItem<String>(
                          value: 'all',
                          child: Text('All Students'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'submitted',
                          child: Text('Submitted Only'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'not_submitted',
                          child: Text('Not Submitted'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Student picker
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedStudentId,
                      isExpanded: true,
                      hint: const Text('Select Student'),
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                      ),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedStudentId = newValue;
                          _studentSubmissions = _filterSubmissions();
                        });
                      },
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All Students'),
                        ),
                        ..._allSubmissions.map((student) {
                          return DropdownMenuItem<String?>(
                            value: student['studentId'],
                            child: Text(
                              student['studentName'],
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_selectedStudentId != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedStudentId = null;
                    _submissionFilter = 'all';
                    _studentSubmissions = _filterSubmissions();
                  });
                },
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Clear Filters'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[600],
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Add method to build student submissions list
  Widget _buildStudentSubmissionsList() {
    if (_studentSubmissions.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          children: [
            Icon(
              Icons.assignment_turned_in_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No submissions yet',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Student submissions will appear here',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _studentSubmissions.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final submission = _studentSubmissions[index];
          final isLate = submission['isLate'] ?? false;
          final isImage = submission['isImage'] ?? false;
          final hasSubmission = submission['hasSubmission'] ?? false;
          
          return Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Student info header
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: !hasSubmission 
                            ? Colors.red[100]
                            : isLate 
                                ? Colors.orange[100] 
                                : Colors.green[100],
                        child: Icon(
                          !hasSubmission 
                              ? Icons.close
                              : isLate 
                                  ? Icons.schedule 
                                  : Icons.check_circle,
                          color: !hasSubmission 
                              ? Colors.red[700]
                              : isLate 
                                  ? Colors.orange[700] 
                                  : Colors.green[700],
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              submission['studentName'],
                              style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              submission['studentEmail'],
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: !hasSubmission
                              ? Colors.red[50]
                              : isLate 
                                  ? Colors.orange[50] 
                                  : Colors.green[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          !hasSubmission
                              ? 'Not submitted'
                              : isLate 
                                  ? 'Late' 
                                  : 'On time',
                          style: TextStyle(
                            color: !hasSubmission
                                ? Colors.red[700]
                                : isLate 
                                    ? Colors.orange[700] 
                                    : Colors.green[700],
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // File preview/info - only show if student has submitted
                if (hasSubmission && isImage && submission['fileUrl'] != null)
                  Container(
                    height: 150,
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        submission['fileUrl'],
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: 150,
                            child: Center(
                              child: CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 150,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Colors.grey[400],
                                    size: 32,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Could not load image',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                
                // File info - only show if student has submitted
                if (hasSubmission)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _getFileTypeColor(submission['fileName'] ?? '').withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _getFileIcon(submission['fileName'] ?? ''),
                            color: _getFileTypeColor(submission['fileName'] ?? ''),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                submission['fileName'] ?? 'Unknown file',
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Submitted ${_formatDateTime(submission['submittedAt'])}',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_canViewInApp(submission['fileName'] ?? ''))
                              IconButton(
                                icon: const Icon(
                                  Icons.visibility_outlined,
                                  color: Colors.blue,
                                ),
                                onPressed: () {
                                  final fileName = submission['fileName'] ?? '';
                                  if (fileName.toLowerCase().endsWith('.pdf')) {
                                    _openPdfViewer(
                                      submission['fileUrl'],
                                      fileName,
                                    );
                                  } else {
                                    _openImageViewer(
                                      submission['fileUrl'],
                                      fileName,
                                    );
                                  }
                                },
                                tooltip: 'View file',
                              ),
                            IconButton(
                              icon: const Icon(
                                Icons.download_outlined,
                                color: Colors.grey,
                              ),
                              onPressed: () => _downloadFile(
                                submission['fileUrl'],
                                submission['fileName'] ?? 'file',
                              ),
                              tooltip: 'Download file',
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else
                  // Show message for students who haven't submitted
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.red[700],
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'This student has not submitted their work yet.',
                              style: TextStyle(
                                color: Colors.red[700],
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Helper method to format datetime
  String _formatDateTime(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    
    DateTime dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is DateTime) {
      dateTime = timestamp;
    } else {
      return 'Unknown';
    }
    
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} at ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  // Add helper methods for status styling
  Color _getStatusColor() {
    if (_isSubmitted) {
      return _isLateSubmission ? Colors.orange : kAccentColor;
    }
    return kTextSecondaryColor;
  }

  IconData _getStatusIcon() {
    if (_isSubmitted) {
      return _isLateSubmission ? Icons.warning_rounded : Icons.check_circle_rounded;
    }
    return Icons.pending_rounded;
  }
}

// Image Viewer Screen
class ImageViewerScreen extends StatelessWidget {
  final String imageUrl;
  final String fileName;

  const ImageViewerScreen({
    Key? key,
    required this.imageUrl,
    required this.fileName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          fileName,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined, color: Colors.white),
            onPressed: () async {
              // Call download method
              Navigator.pop(context);
              // You can add download functionality here if needed
            },
            tooltip: 'Download',
          ),
        ],
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                  color: Colors.white,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 64,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Could not load image',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// PDF Viewer Screen
class PdfViewerScreen extends StatefulWidget {
  final String pdfUrl;
  final String fileName;

  const PdfViewerScreen({
    Key? key,
    required this.pdfUrl,
    required this.fileName,
  }) : super(key: key);

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _hasError = false;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _isLoading = false;
              _hasError = true;
            });
          },
        ),
      );

    // Load PDF using Google Docs Viewer
    final viewerUrl = 'https://docs.google.com/gview?embedded=true&url=${Uri.encodeComponent(widget.pdfUrl)}';
    _controller.loadRequest(Uri.parse(viewerUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.fileName,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () {
              setState(() {
                _hasError = false;
              });
              _initializeWebView();
            },
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser_outlined),
            onPressed: () async {
              final url = Uri.parse(widget.pdfUrl);
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            tooltip: 'Open in browser',
          ),
        ],
      ),
      body: Stack(
        children: [
          if (!_hasError)
            WebViewWidget(controller: _controller)
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Could not load PDF',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please check your internet connection',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _hasError = false;
                      });
                      _initializeWebView();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () async {
                      final url = Uri.parse(widget.pdfUrl);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('Open in browser'),
                  ),
                ],
              ),
            ),
          if (_isLoading && !_hasError)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Loading PDF...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}