import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:twitterr/screens/auth/submission/class.dart';
import 'package:twitterr/screens/auth/submission/classDetails.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:twitterr/screens/auth/submission/participants.dart';
import 'dart:math';

const Color kBackgroundColor = Color(0xFFF8F9FA);
const Color kSurfaceColor = Colors.white;
const Color kPrimaryColor = Color(0xFF6366F1);
const Color kTextPrimaryColor = Color(0xFF1F2937);
const Color kTextSecondaryColor = Color(0xFF6B7280);
const Color kDividerColor = Color(0xFFE5E7EB);

// Modern color palette for different assignment types
const List<Color> kModernColors = [
  Color(0xFFEF4444), // Red
  Color(0xFF3B82F6), // Blue  
  Color(0xFF10B981), // Green
  Color(0xFFF59E0B), // Yellow
  Color(0xFF8B5CF6), // Purple
  Color(0xFFEC4899), // Pink
  Color(0xFF06B6D4), // Cyan
  Color(0xFFF97316), // Orange
];

class Classwork extends StatefulWidget {
  final String classId;
  final String className;
  final Function(int)? onPageChange; // Add this parameter

  const Classwork({
    Key? key,
    required this.classId,
    required this.className,
    this.onPageChange, // Add this parameter
  }) : super(key: key);

  @override
  State<Classwork> createState() => _ClassworkPageState();
}

class _ClassworkPageState extends State<Classwork> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.className,
          style: const TextStyle(
            color: kTextPrimaryColor,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: kTextPrimaryColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('classes')
            .doc(widget.classId)
            .collection('announcements')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: kPrimaryColor),
            );
          }

          if (snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final isLast = index == snapshot.data!.docs.length - 1;
              
              return _buildTimelineTaskCard(data, doc.id, index, isLast);
            },
          );
        },
      ),
      bottomNavigationBar: widget.onPageChange == null ? BottomNavigationBar(
        backgroundColor: kSurfaceColor,
        selectedItemColor: kPrimaryColor,
        unselectedItemColor: kTextSecondaryColor,
        currentIndex: 1,
        onTap: (index) {
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

  Widget _buildTimelineTaskCard(Map<String, dynamic> data, String docId, int index, bool isLast) {
    final type = data['type'] as String;
    final title = data['text'] ?? 'Untitled';
    final instructions = data['instructions'] ?? '';
    final dueDate = data['dueDate'] as Timestamp?;
    final timestamp = data['timestamp'] as Timestamp?;
    
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Timeline
            SizedBox(
              width: 20,
              child: Column(
                children: [
                  // Animated Timeline Dot
                  type == 'assignment'
                      ? StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('classes')
                              .doc(widget.classId)
                              .collection('submissions')
                              .where('studentId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                              .where('assignmentId', isEqualTo: docId)
                              .snapshots(),
                          builder: (context, snapshot) {
                            Color dotColor = const Color(0xFFEF4444); // Default red
                            
                            if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                              final submission = snapshot.data!.docs.first.data() as Map<String, dynamic>;
                              final isSubmitted = submission['submitted'] ?? false;
                              final isLate = submission['isLate'] ?? false;
                              
                              if (isSubmitted) {
                                dotColor = isLate 
                                    ? const Color(0xFFF59E0B) // Orange for late
                                    : const Color(0xFF10B981); // Green for submitted
                              } else if (dueDate != null) {
                                final now = DateTime.now();
                                final dueDateObj = dueDate.toDate();
                                final isOverdue = dueDateObj.isBefore(now);
                                final isDueSoon = dueDateObj.difference(now).inHours <= 24 && dueDateObj.isAfter(now);
                                
                                if (isOverdue) {
                                  dotColor = const Color(0xFFDC2626); // Dark red for past due
                                } else if (isDueSoon) {
                                  dotColor = const Color(0xFFF97316); // Orange for due soon
                                } else {
                                  dotColor = const Color(0xFF3B82F6); // Blue for pending
                                }
                              }
                            }
                            
                            return _buildAnimatedTimelineDot(dotColor);
                          },
                        )
                      : _buildAnimatedTimelineDot(
                          type == 'material' 
                              ? const Color(0xFF3B82F6) // Blue for materials
                              : const Color(0xFF10B981), // Green for announcements
                        ),
                  
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              const Color(0xFFE5E7EB).withOpacity(0.8),
                              const Color(0xFFE5E7EB).withOpacity(0.6),
                              const Color(0xFFE5E7EB).withOpacity(0.4),
                              const Color(0xFFE5E7EB).withOpacity(0.2),
                              const Color(0xFFE5E7EB).withOpacity(0.1),
                            ],
                            stops: const [0.0, 0.3, 0.6, 0.8, 1.0],
                          ),
                          borderRadius: BorderRadius.circular(1),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE5E7EB).withOpacity(0.1),
                              blurRadius: 2,
                              offset: const Offset(0, 0),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Content
            Expanded(
              child: Column(
                children: [
                  // Time
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        timestamp != null ? _formatTime(timestamp.toDate()) : 'Recently',
                        style: const TextStyle(
                          color: kTextSecondaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Task Card with Status-based Color
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ClassDetails(
                            announcement: {...data, 'id': docId},
                            classId: widget.classId,
                          ),
                        ),
                      );
                    },
                    child: type == 'assignment'
                        ? StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('classes')
                                .doc(widget.classId)
                                .collection('submissions')
                                .where('studentId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                                .where('assignmentId', isEqualTo: docId)
                                .snapshots(),
                            builder: (context, snapshot) {
                              // Determine status and color
                              String status = 'Not Submitted';
                              Color cardColor = const Color(0xFFEF4444); // Red for not submitted
                              Color textColor = Colors.white;
                              
                              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                                final submission = snapshot.data!.docs.first.data() as Map<String, dynamic>;
                                final isSubmitted = submission['submitted'] ?? false;
                                final isLate = submission['isLate'] ?? false;
                                
                                if (isSubmitted) {
                                  if (isLate) {
                                    status = 'Submitted Late';
                                    cardColor = const Color(0xFFF59E0B); // Orange for late
                                  } else {
                                    status = 'Submitted';
                                    cardColor = const Color(0xFF10B981); // Green for submitted
                                  }
                                } else {
                                  // Check if due soon
                                  if (dueDate != null) {
                                    final now = DateTime.now();
                                    final dueDateObj = dueDate.toDate();
                                    final isOverdue = dueDateObj.isBefore(now);
                                    final isDueSoon = dueDateObj.difference(now).inHours <= 24 && dueDateObj.isAfter(now);
                                    
                                    if (isOverdue) {
                                      status = 'Past Due';
                                      cardColor = const Color(0xFFDC2626); // Dark red for past due
                                    } else if (isDueSoon) {
                                      status = 'Due Soon';
                                      cardColor = const Color(0xFFF97316); // Orange for due soon
                                    } else {
                                      status = 'Pending';
                                      cardColor = const Color(0xFF3B82F6); // Blue for pending
                                    }
                                  }
                                }
                              }
                              
                              return _buildTaskCard(
                                title: title,
                                description: instructions,
                                dueDate: dueDate,
                                type: type,
                                status: status,
                                cardColor: cardColor,
                                textColor: textColor,
                              );
                            },
                          )
                        : _buildTaskCard(
                            title: title,
                            description: instructions,
                            dueDate: dueDate,
                            type: type,
                            status: type == 'material' ? 'Material' : 'Announcement',
                            cardColor: type == 'material' 
                                ? const Color(0xFF3B82F6) // Blue for materials
                                : const Color(0xFF10B981), // Green for announcements
                            textColor: Colors.white,
                          ),
                  ),
                  
                  SizedBox(height: isLast ? 24 : 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard({
    required String title,
    required String description,
    required Timestamp? dueDate,
    required String type,
    required String status,
    required Color cardColor,
    required Color textColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cardColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            title,
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Description
          if (description.isNotEmpty)
            Text(
              description,
              style: TextStyle(
                color: textColor.withOpacity(0.9),
                fontSize: 14,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          
          const SizedBox(height: 16),
          
          // Bottom row with status and due date
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              
              // Due date
              if (dueDate != null)
                Text(
                  'Due ${_formatDueDate(dueDate.toDate())}',
                  style: TextStyle(
                    color: textColor.withOpacity(0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 400,
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No classwork yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Assignments and materials will appear here',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.day}/${dateTime.month}';
    }
  }

  String _formatDueDate(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final difference = targetDate.difference(today).inDays;
    
    if (difference == 0) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')} PM';
    } else if (difference == 1) {
      return 'Tomorrow';
    } else if (difference > 1 && difference < 7) {
      return '${difference}d';
    } else {
      return '${dateTime.day}/${dateTime.month}';
    }
  }

  Widget _buildAnimatedTimelineDot(Color color) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 2000),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulsing ring
            Container(
              width: 20 + (sin(value * 3.14159 * 4) * 4).abs(),
              height: 20 + (sin(value * 3.14159 * 4) * 4).abs(),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.2 + (sin(value * 3.14159 * 3) * 0.1).abs()),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 8 + (sin(value * 3.14159 * 2) * 4).abs(),
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            
            // Middle ring
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.6),
                border: Border.all(
                  color: Colors.white.withOpacity(0.8),
                  width: 1.5,
                ),
              ),
            ),
            
            // Inner dot
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    color,
                    color.withOpacity(0.8),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      onEnd: () {
        // Restart animation to create continuous effect
        if (mounted) {
          setState(() {});
        }
      },
    );
  }
}