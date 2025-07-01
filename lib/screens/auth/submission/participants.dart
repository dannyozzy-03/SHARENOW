import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:twitterr/screens/auth/chat/personalChat.dart';
import 'package:twitterr/screens/auth/submission/class.dart';
import 'package:twitterr/screens/auth/submission/classwork.dart';
import 'package:twitterr/screens/auth/main/profile/profile.dart';

const Color kBackgroundColor = Color(0xFFF8F9FA);
const Color kSurfaceColor = Colors.white;
const Color kPrimaryColor = Color(0xFF4A90E2);
const Color kTextPrimaryColor = Color(0xFF2C3E50);
const Color kTextSecondaryColor = Color(0xFF95A5A6);
const Color kDividerColor = Color(0xFFECEEF1);

class Participants extends StatefulWidget {
  final String classId;
  final String className;
  final Function(int)? onPageChange;

  const Participants({
    Key? key,
    required this.classId,
    required this.className,
    this.onPageChange,
  }) : super(key: key);

  @override
  State<Participants> createState() => _ParticipantsState();
}

class _ParticipantsState extends State<Participants> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        elevation: 1,
        title: Text(
          'Participants in ${widget.className}',
          style: const TextStyle(
            color: kTextPrimaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: kTextPrimaryColor),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('classes')
            .doc(widget.classId)
            .snapshots(),
        builder: (context, classSnapshot) {
          if (!classSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final classData = classSnapshot.data!.data() as Map<String, dynamic>;
          final participants = List<String>.from(classData['participants'] ?? []);

          if (participants.isEmpty) {
            return const Center(
              child: Text(
                'No participants in this class yet',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Teachers Section
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('role', isEqualTo: 'Lecturer')
                      .where(FieldPath.documentId, whereIn: participants)
                      .snapshots(),
                  builder: (context, snapshot) {
                    return _buildSection(
                      'Lecturer',
                      snapshot,
                      Colors.blue,
                      Icons.school,
                    );
                  },
                ),

                // Students Section
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('role', isEqualTo: 'Student') // Change from 'student' to 'Student'
                      .where(FieldPath.documentId, whereIn: participants)
                      .snapshots(),
                  builder: (context, snapshot) {
                    return _buildSection(
                      'Students',
                      snapshot,
                      Colors.green,
                      Icons.person,
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: widget.onPageChange == null ? BottomNavigationBar(
        backgroundColor: kSurfaceColor,
        selectedItemColor: kPrimaryColor,
        unselectedItemColor: kTextSecondaryColor,
        currentIndex: 2,
        onTap: (index) {
          if (widget.onPageChange != null) {
            widget.onPageChange!(index);
          } else {
            if (index == 0) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ClassPage(
                    classId: widget.classId,
                    className: widget.className,
                  ),
                ),
              );
            } else if (index == 1) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => Classwork(
                    classId: widget.classId,
                    className: widget.className,
                  ),
                ),
              );
            }
          }
        },
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
      ) : null,
    );
  }

  Widget _buildSection(
    String title,
    AsyncSnapshot<QuerySnapshot> snapshot,
    Color color,
    IconData icon,
  ) {
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }

    final users = snapshot.data!.docs;

    if (users.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(
                '$title (${users.length})',
                style: TextStyle(
                  color: kTextPrimaryColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final userData = users[index].data() as Map<String, dynamic>;
            final isCurrentUser = 
                users[index].id == FirebaseAuth.instance.currentUser?.uid;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: kSurfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: kDividerColor,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListTile(
                leading: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => Profile(id: users[index].id),
                      ),
                    );
                  },
                  child: CircleAvatar(
                    backgroundColor: color.withOpacity(0.1),
                    backgroundImage: userData['profileImageUrl'] != null && 
                                   userData['profileImageUrl'].toString().isNotEmpty
                        ? NetworkImage(userData['profileImageUrl'])
                        : null,
                    child: userData['profileImageUrl'] == null || 
                           userData['profileImageUrl'].toString().isEmpty
                        ? Text(
                            userData['name']?[0]?.toUpperCase() ?? '?',
                            style: TextStyle(color: color),
                          )
                        : null,
                  ),
                ),
                title: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => Profile(id: users[index].id),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          userData['name'] ?? 'Unknown',
                          style: const TextStyle(
                            color: kTextPrimaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCurrentUser)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: kDividerColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'You',
                            style: TextStyle(
                              color: kTextSecondaryColor,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                subtitle: Text(
                  userData['email'] ?? '',
                  style: const TextStyle(color: kTextSecondaryColor),
                ),
                trailing: !isCurrentUser ? IconButton(
                  icon: const Icon(
                    Icons.message_outlined,
                    color: kPrimaryColor,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PersonalChat(
                          receiverId: users[index].id,
                        ),
                      ),
                    );
                  },
                ) : null,
              ),
            );
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}