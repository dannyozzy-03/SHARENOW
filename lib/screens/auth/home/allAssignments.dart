import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:twitterr/screens/auth/submission/classDetails.dart';
import 'dart:math';

const Color kBackgroundColor = Color(0xFFF8F9FA);
const Color kPrimaryColor = Color(0xFF6366F1);
const Color kTextPrimaryColor = Color(0xFF1F2937);
const Color kTextSecondaryColor = Color(0xFF6B7280);

class AllAssignments extends StatefulWidget {
  const AllAssignments({super.key});

  @override
  State<AllAssignments> createState() => _AllAssignmentsState();
}

class _AllAssignmentsState extends State<AllAssignments> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _animationController.repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: FutureBuilder<DocumentSnapshot>(
          future: currentUserId != null 
              ? FirebaseFirestore.instance.collection('users').doc(currentUserId).get()
              : Future.value(null),
          builder: (context, snapshot) {
            final isLecturer = snapshot.hasData && snapshot.data!.exists
                ? (snapshot.data!.data() as Map<String, dynamic>?)?.containsKey('role') ?? false
                    ? (snapshot.data!.data() as Map<String, dynamic>)['role'] == 'Lecturer'
                    : false
                : false;
            
            return Text(
              isLecturer ? 'All Assignment Status' : 'All Assignments',
              style: const TextStyle(
                color: kTextPrimaryColor,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            );
          },
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: kTextPrimaryColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _getAllAssignmentsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: kPrimaryColor),
            );
          }

          if (snapshot.hasError) {
            return _buildErrorState();
          }

          final assignments = snapshot.data ?? [];

          if (assignments.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: assignments.length,
            itemBuilder: (context, index) {
              final assignment = assignments[index];
              final isLast = index == assignments.length - 1;
              
              return _buildTimelineAssignmentCard(assignment, index, isLast);
            },
          );
        },
      ),
    );
  }

  Stream<List<Map<String, dynamic>>> _getAllAssignmentsStream() {
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    
    if (currentUserId == null) {
      return Stream.value([]);
    }

    return FirebaseFirestore.instance
        .collection('classes')
        .where('participants', arrayContains: currentUserId)
        .snapshots()
        .asyncMap((classesSnapshot) async {
      List<Map<String, dynamic>> assignments = [];

      try {
        print('📚 Checking ${classesSnapshot.docs.length} classes for user: $currentUserId');
        
        // Get current user's information to check if they're a lecturer
        final currentUserDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .get();
        
        final currentUserData = currentUserDoc.data();
        final currentUserRole = currentUserData?['role'] ?? '';
        final currentUserName = currentUserData?['name'] ?? '';
        
        print('👤 Current user role: $currentUserRole, name: $currentUserName');
        
        for (var classDoc in classesSnapshot.docs) {
          final classData = classDoc.data();
          final classId = classDoc.id;
          final className = classData['title'] ?? 'Unknown Class';
          final participants = List<String>.from(classData['participants'] ?? []);

          print('🏫 Checking class: $className (ID: $classId)');

          // Get ALL assignments from this class
          final assignmentsSnapshot = await FirebaseFirestore.instance
              .collection('classes')
              .doc(classId)
              .collection('announcements')
              .where('type', isEqualTo: 'assignment')
              .get();

          print('📋 Found ${assignmentsSnapshot.docs.length} assignments in $className');

          for (var assignmentDoc in assignmentsSnapshot.docs) {
            final assignmentData = assignmentDoc.data();
            final assignmentTitle = assignmentData['text'] ?? 'Untitled Assignment';
            final assignmentLecturerName = assignmentData['lecturerName'] ?? '';
            
            print('📝 Checking assignment: $assignmentTitle (Created by: $assignmentLecturerName)');
            
            if (currentUserRole == 'Lecturer') {
              // For lecturers: show assignments they created with submission status
              bool isLecturerAssignment = false;
              
              // First check if lecturerName matches
              if (assignmentLecturerName.isNotEmpty && assignmentLecturerName == currentUserName) {
                isLecturerAssignment = true;
                print('🎯 Match by lecturer name: $assignmentLecturerName');
              }
              
              // Additional check: if this lecturer is in the class and there's no other lecturer
              if (!isLecturerAssignment) {
                final classLecturers = await FirebaseFirestore.instance
                    .collection('users')
                    .where('role', isEqualTo: 'Lecturer')
                    .where(FieldPath.documentId, whereIn: participants.isEmpty ? ['dummy'] : participants)
                    .get();
                
                // If current user is the only lecturer in this class, assume they created all assignments
                if (classLecturers.docs.length == 1 && classLecturers.docs.first.id == currentUserId) {
                  isLecturerAssignment = true;
                  print('🎯 Match by being sole lecturer in class');
                }
              }
              
              if (isLecturerAssignment) {
                print('🎓 Processing lecturer assignment: $assignmentTitle');
                
                // Get all students in this class
                final studentsSnapshot = await FirebaseFirestore.instance
                    .collection('users')
                    .where('role', isEqualTo: 'Student')
                    .where(FieldPath.documentId, whereIn: participants.isEmpty ? ['dummy'] : participants)
                    .get();

                final totalStudents = studentsSnapshot.docs.length;
                final studentIds = studentsSnapshot.docs.map((doc) => doc.id).toList();
                
                print('👥 Total students in class: $totalStudents');

                // Get submissions for this assignment
                final submissionsSnapshot = await FirebaseFirestore.instance
                    .collection('classes')
                    .doc(classId)
                    .collection('submissions')
                    .where('assignmentId', isEqualTo: assignmentDoc.id)
                    .where('submitted', isEqualTo: true)
                    .get();

                // Count unique student submissions (avoid duplicates)
                Set<String> uniqueStudentIds = {};
                
                for (var submissionDoc in submissionsSnapshot.docs) {
                  final submissionData = submissionDoc.data();
                  final studentId = submissionData['studentId'] as String?;
                  
                  if (studentId != null) {
                    uniqueStudentIds.add(studentId);
                  }
                }
                
                // Cross-check: ensure submitted students are actually in the class
                final validSubmissions = uniqueStudentIds.where((studentId) => studentIds.contains(studentId)).toSet();
                final finalSubmittedCount = validSubmissions.length;
                
                print('📊 Submissions: $finalSubmittedCount/$totalStudents for assignment: $assignmentTitle');

                // Determine status using the validated count
                String status;
                String urgencyLevel;
                if (totalStudents == 0) {
                  status = 'No Students';
                  urgencyLevel = 'info';
                } else if (finalSubmittedCount == totalStudents) {
                  status = 'All Submitted';
                  urgencyLevel = 'completed';
                } else if (finalSubmittedCount > 0) {
                  status = 'Partially Submitted';
                  urgencyLevel = 'pending';
                } else {
                  status = 'No Submissions';
                  urgencyLevel = 'overdue';
                }

                print('📋 Assignment status: $status ($urgencyLevel)');

                assignments.add({
                  'id': assignmentDoc.id,
                  'assignmentId': assignmentDoc.id,
                  'classId': classId,
                  'className': className,
                  'title': assignmentTitle,
                  'dueDate': assignmentData['dueDate'],
                  'instructions': assignmentData['instructions'] ?? '',
                  'type': assignmentData['type'] ?? 'assignment',
                  'timestamp': assignmentData['timestamp'],
                  'isLecturerView': true,
                  'submissionStatus': status,
                  'submittedCount': finalSubmittedCount,
                  'totalStudents': totalStudents,
                  'urgencyLevel': urgencyLevel,
                  ...assignmentData,
                });
              }
            } else {
              // For students: show all assignments (not just unsubmitted ones) with their status
              if (assignmentLecturerName != currentUserName) {
                assignments.add({
                  'id': assignmentDoc.id,
                  'assignmentId': assignmentDoc.id,
                  'classId': classId,
                  'className': className,
                  'title': assignmentTitle,
                  'dueDate': assignmentData['dueDate'],
                  'instructions': assignmentData['instructions'] ?? '',
                  'type': assignmentData['type'] ?? 'assignment',
                  'timestamp': assignmentData['timestamp'],
                  'isLecturerView': false,
                  ...assignmentData,
                });
              }
            }
          }
        }

        print('📊 Total assignments found: ${assignments.length}');
        
        // Sort by priority: lecturers see pending/overdue first, students see by due date
        assignments.sort((a, b) {
          if (currentUserRole == 'Lecturer') {
            // Priority order for lecturers: overdue > pending > completed > info
            final aPriority = _getUrgencyPriority(a['urgencyLevel'] ?? 'info');
            final bPriority = _getUrgencyPriority(b['urgencyLevel'] ?? 'info');
            
            if (aPriority != bPriority) {
              return aPriority.compareTo(bPriority);
            }
          }
          
          // Secondary sort by due date
          final aDate = a['dueDate'] as Timestamp?;
          final bDate = b['dueDate'] as Timestamp?;
          
          if (aDate != null && bDate != null) {
            return aDate.compareTo(bDate);
          }
          
          if (aDate != null && bDate == null) return -1;
          if (aDate == null && bDate != null) return 1;
          
          // Tertiary sort by creation timestamp
          final aTimestamp = a['timestamp'] as Timestamp?;
          final bTimestamp = b['timestamp'] as Timestamp?;
          
          if (aTimestamp != null && bTimestamp != null) {
            return bTimestamp.compareTo(aTimestamp);
          }
          
          return 0;
        });

        return assignments;
      } catch (e) {
        print('❌ Error fetching assignments: $e');
        return <Map<String, dynamic>>[];
      }
    });
  }

  // Helper method to get urgency priority for lecturers
  int _getUrgencyPriority(String urgencyLevel) {
    switch (urgencyLevel) {
      case 'overdue': return 1;      // Highest priority
      case 'pending': return 2;      // Medium priority  
      case 'completed': return 3;    // Low priority
      case 'info': return 4;         // Lowest priority
      default: return 5;
    }
  }

  Widget _buildTimelineAssignmentCard(Map<String, dynamic> assignment, int index, bool isLast) {
    final title = assignment['title'] ?? 'Untitled';
    final className = assignment['className'] ?? 'Unknown Class';
    final instructions = assignment['instructions'] ?? '';
    final dueDate = assignment['dueDate'] as Timestamp?;
    final timestamp = assignment['timestamp'] as Timestamp?;
    final classId = assignment['classId'];
    final assignmentId = assignment['id'];
    final isLecturerView = assignment['isLecturerView'] ?? false;
    
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
                  // Animated Timeline Dot with Status
                  if (isLecturerView)
                    _buildLecturerTimelineDot(assignment)
                  else
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('classes')
                          .doc(classId)
                          .collection('submissions')
                          .where('studentId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                          .where('assignmentId', isEqualTo: assignmentId)
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
                  // Class Name and Time Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Enhanced Class Name with Icon
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                kPrimaryColor.withOpacity(0.12),
                                kPrimaryColor.withOpacity(0.08),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: kPrimaryColor.withOpacity(0.2),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: kPrimaryColor.withOpacity(0.06),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                      Container(
                                padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                                  color: kPrimaryColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.class_outlined,
                                  color: kPrimaryColor,
                                  size: 14,
                                ),
                        ),
                              const SizedBox(width: 8),
                              Flexible(
                        child: Text(
                          className,
                          style: TextStyle(
                            color: kPrimaryColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                          ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                        ),
                      ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 12),
                      
                      // Time with subtle styling
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: kTextSecondaryColor.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              color: kTextSecondaryColor,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                      Text(
                        timestamp != null ? _formatTime(timestamp.toDate()) : 'Recently',
                        style: const TextStyle(
                          color: kTextSecondaryColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Assignment Card
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ClassDetails(
                            announcement: assignment,
                            classId: classId,
                          ),
                        ),
                      );
                    },
                    child: isLecturerView
                        ? _buildLecturerAssignmentCard(assignment)
                        : StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('classes')
                                .doc(classId)
                                .collection('submissions')
                                .where('studentId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                                .where('assignmentId', isEqualTo: assignmentId)
                                .snapshots(),
                            builder: (context, snapshot) {
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
                                } else if (dueDate != null) {
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
                              
                              return _buildAssignmentCard(
                                title: title,
                                description: instructions,
                                dueDate: dueDate,
                                status: status,
                                cardColor: cardColor,
                                textColor: textColor,
                              );
                            },
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

  Widget _buildLecturerTimelineDot(Map<String, dynamic> assignment) {
    final urgencyLevel = assignment['urgencyLevel'] ?? 'info';
    
    Color dotColor;
    switch (urgencyLevel) {
      case 'completed':
        dotColor = const Color(0xFF10B981); // Green - all submitted
        break;
      case 'pending':
        dotColor = const Color(0xFFF59E0B); // Orange - partially submitted
        break;
      case 'overdue':
        dotColor = const Color(0xFFDC2626); // Red - no submissions
        break;
      case 'info':
      default:
        dotColor = const Color(0xFF6B7280); // Gray - no students
        break;
    }
    
    return _buildAnimatedTimelineDot(dotColor);
  }

  Widget _buildLecturerAssignmentCard(Map<String, dynamic> assignment) {
    final title = assignment['title'] ?? 'Untitled';
    final instructions = assignment['instructions'] ?? '';
    final dueDate = assignment['dueDate'] as Timestamp?;
    final urgencyLevel = assignment['urgencyLevel'] ?? 'info';
    final submissionStatus = assignment['submissionStatus'] ?? 'Unknown';
    final submittedCount = assignment['submittedCount'] ?? 0;
    final totalStudents = assignment['totalStudents'] ?? 0;
    
    Color cardColor;
    String status;
    
    switch (urgencyLevel) {
      case 'completed':
        cardColor = const Color(0xFF10B981); // Green - all submitted
        status = 'Work Done';
        break;
      case 'pending':
        cardColor = const Color(0xFFF59E0B); // Orange - partially submitted
        status = 'Pending ($submittedCount/$totalStudents)';
        break;
      case 'overdue':
        cardColor = const Color(0xFFDC2626); // Red - no submissions
        status = 'No Submissions';
        break;
      case 'info':
      default:
        cardColor = const Color(0xFF6B7280); // Gray - no students
        status = 'No Students';
        break;
    }
    
    return _buildAssignmentCard(
      title: title,
      description: instructions,
      dueDate: dueDate,
      status: status,
      cardColor: cardColor,
      textColor: Colors.white,
      isLecturerView: true,
      submittedCount: submittedCount,
      totalStudents: totalStudents,
    );
  }

  Widget _buildAssignmentCard({
    required String title,
    required String description,
    required Timestamp? dueDate,
    required String status,
    required Color cardColor,
    required Color textColor,
    bool isLecturerView = false,
    int submittedCount = 0,
    int totalStudents = 0,
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
          
          // Bottom row with status and due date/submission info
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
              
              // Due date for students, submission info for lecturers
              if (isLecturerView && totalStudents > 0)
                Row(
                  children: [
                    Icon(
                      Icons.people_outlined,
                      color: textColor.withOpacity(0.8),
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$submittedCount/$totalStudents submitted',
                      style: TextStyle(
                        color: textColor.withOpacity(0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                )
              else if (!isLecturerView && dueDate != null)
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

  Widget _buildAnimatedTimelineDot(Color color) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final value = _animation.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulsing ring
            Container(
              width: 20 + (sin(value * 3.14159 * 4) * 3).abs(),
              height: 20 + (sin(value * 3.14159 * 4) * 3).abs(),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.15 + (sin(value * 3.14159 * 3) * 0.05).abs()),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 6 + (sin(value * 3.14159 * 2) * 2).abs(),
                    spreadRadius: 1,
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
                    color: color.withOpacity(0.4),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    
    return FutureBuilder<DocumentSnapshot>(
      future: currentUserId != null 
          ? FirebaseFirestore.instance.collection('users').doc(currentUserId).get()
          : Future.value(null),
      builder: (context, snapshot) {
        final isLecturer = snapshot.hasData && snapshot.data!.exists
            ? (snapshot.data!.data() as Map<String, dynamic>?)?.containsKey('role') ?? false
                ? (snapshot.data!.data() as Map<String, dynamic>)['role'] == 'Lecturer'
                : false
            : false;
        
        return Container(
          height: 400,
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF10B981).withOpacity(0.08),
                const Color(0xFF059669).withOpacity(0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF10B981).withOpacity(0.15),
              width: 1,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: Color(0xFF10B981),
                ),
                const SizedBox(height: 16),
                Text(
                  isLecturer ? 'All assignments reviewed!' : 'All caught up!',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF065F46),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isLecturer ? 'No assignments to track across all classes' : 'No pending assignments from your classes',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF047857),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorState() {
    return Container(
      height: 400,
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.red[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Unable to load assignments',
              style: TextStyle(
                fontSize: 14,
                color: Colors.red[500],
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
} 