import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:twitterr/screens/auth/submission/class.dart';

class Submission extends StatefulWidget {
  const Submission({super.key});

  @override
  State<Submission> createState() => _SubmissionState();
}

class _SubmissionState extends State<Submission> {
  // List of classes fetched from Firestore
  List<Map<String, dynamic>> classes = [];

  // Lecturer name (initialize with a default value)
  String lecturerName = "Loading...";
  String? userId;
  String userRole = "Loading...";

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _fetchClasses();
  }

  // Fetch the current user's data (name and role)
  void _fetchUserData() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      userId = user.uid; // Store the current user's UID
      DocumentSnapshot<Map<String, dynamic>> userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      setState(() {
        lecturerName = userDoc.data()?['name'] ?? 'Unknown Lecturer'; // Use Firestore name
        userRole = userDoc.data()?['role'] ?? 'user'; // Fetch user role
      });
    }
  }

  // Fetch classes where the current user is a participant
  void _fetchClasses() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      QuerySnapshot<Map<String, dynamic>> querySnapshot = await FirebaseFirestore.instance
          .collection('classes')
          .where('participants', arrayContains: uid) // Filter by participants
          .get();

      setState(() {
        classes = querySnapshot.docs.map((doc) {
          return {
            'id': doc.id,
            ...doc.data(),
          };
        }).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], // Light background
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          "My Classes",
          style: TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      // Update empty state colors
      body: classes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.school_outlined,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "No Classes Yet",
                    style: TextStyle(
                      fontSize: 24,
                      color: Colors.grey[800],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    userRole == 'Lecturer'
                        ? "Create your first class to get started"
                        : "Join a class using a class code",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            )
          // Update ListView item design
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: classes.length,
              itemBuilder: (context, index) {
                final classData = classes[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
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
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ClassPage(
                              classId: classData['id'],
                              className: classData['title'] ?? '',
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    classData['title'] ?? '',
                                    style: const TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                                PopupMenuButton(
                                  icon: Icon(
                                    Icons.more_vert,
                                    color: Colors.grey[600],
                                  ),
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      child: ListTile(
                                        leading: const Icon(Icons.exit_to_app),
                                        title: const Text('Unenroll'),
                                        onTap: () {
                                          Navigator.pop(context);
                                          _showUnenrollDialog(
                                              context, classData['id']);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(Icons.person,
                                    size: 16,
                                    color: Colors.blue[600]),
                                const SizedBox(width: 8),
                                Text(
                                  "Lecturer: ${classData['lecturer'] ?? ''}",
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.key,
                                    size: 16, color: Colors.amber),
                                const SizedBox(width: 8),
                                Text(
                                  "Code: ${classData['code'] ?? ''}",
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
      // Update FloatingActionButton design
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: userRole == 'Lecturer'
                ? [Colors.blue[400]!, Colors.blue[600]!]
                : [Colors.green[400]!, Colors.green[600]!],
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: (userRole == 'Lecturer' ? Colors.blue : Colors.green)
                  .withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () {
            userRole == 'Lecturer'
                ? _showCreateClassDialog(context)
                : _showJoinClassDialog(context);
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: Icon(
            userRole == 'Lecturer' ? Icons.add : Icons.login,
            color: Colors.white,
          ),
          label: Text(
            userRole == 'Lecturer'
                ? "Create Class"
                : "Join Class",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  void _showUnenrollDialog(BuildContext context, String classId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Unenroll from Class"),
          content: const Text("Are you sure you want to unenroll from this class?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                // Remove the current user from the participants array
                await FirebaseFirestore.instance
                    .collection('classes')
                    .doc(classId)
                    .update({
                  'participants': FieldValue.arrayRemove([userId]),
                });

                _fetchClasses(); // Refresh the class list

                Navigator.of(context).pop();
              },
              child: const Text("Unenroll"),
            ),
          ],
        );
      },
    );
  }

  void _showCreateClassDialog(BuildContext context) {
    final TextEditingController classNameController = TextEditingController();
    final String classCode = _generateClassCode();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            "Create New Class",
            style: TextStyle(color: Colors.black87),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: classNameController,
                style: const TextStyle(color: Colors.black87),
                decoration: InputDecoration(
                  labelText: "Class Name",
                  labelStyle: TextStyle(color: Colors.grey[700]),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.blue[600]!),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.key, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Class Code",
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            classCode,
                            style: TextStyle(
                              color: Colors.grey[900],
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.copy, color: Colors.blue[600]),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: classCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Class code copied!"),
                            backgroundColor: Colors.blue,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                final String className = classNameController.text;

                if (className.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Class name cannot be empty!")),
                  );
                  return;
                }

                // Save class data to Firestore
                await FirebaseFirestore.instance.collection('classes').add({
                  'title': className,
                  'lecturer': lecturerName, // Use the current user's name
                  'code': classCode,
                  'participants': [userId], // Add the current user as a participant
                });

                _fetchClasses(); // Refresh the class list

                Navigator.of(context).pop();
              },
              child: const Text("Create"),
            ),
          ],
        );
      },
    );
  }

  void _showJoinClassDialog(BuildContext context) {
    final TextEditingController classCodeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Join Class"),
          content: TextField(
            controller: classCodeController,
            decoration: const InputDecoration(
              labelText: "Enter Class Code",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final String classCode = classCodeController.text;

                if (classCode.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Class code cannot be empty!")),
                  );
                  return;
                }

                // Find the class by code and add the current user to participants
                QuerySnapshot<Map<String, dynamic>> querySnapshot =
                    await FirebaseFirestore.instance
                        .collection('classes')
                        .where('code', isEqualTo: classCode)
                        .get();

                if (querySnapshot.docs.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Invalid class code!")),
                  );
                  return;
                }

                final classDoc = querySnapshot.docs.first;
                await FirebaseFirestore.instance
                    .collection('classes')
                    .doc(classDoc.id)
                    .update({
                  'participants': FieldValue.arrayUnion([userId]),
                });

                _fetchClasses(); // Refresh the class list

                Navigator.of(context).pop();
              },
              child: const Text("Join"),
            ),
          ],
        );
      },
    );
  }

  String _generateClassCode() {
    const String chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final Random random = Random();
    return String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }
}