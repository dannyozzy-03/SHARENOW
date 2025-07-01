import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:twitterr/models/posts.dart';
import 'package:twitterr/screens/auth/main/posts/list.dart';
import 'package:twitterr/services/posts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:twitterr/screens/auth/submission/classDetails.dart';
import 'package:twitterr/screens/auth/home/allAssignments.dart';

class Feed extends StatefulWidget {
  const Feed({super.key});

  @override
  FeedState createState() => FeedState();
}

class FeedState extends State<Feed> {
  final PostService _postService = PostService();

  @override
  Widget build(BuildContext context) {
    return FutureProvider<List<PostModel>>(
      create: (_) => _postService.getFeed(),
      initialData: [], // Provide an empty list as initial data
      catchError: (_, error) {
        return []; // Return an empty list in case of errors
      },
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(
                child: _buildTodaysTasks(),
              ),
            ];
          },
        body: ListPosts(),
        ),
      ),
    );
  }

  Widget _buildTodaysTasks() {
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    
    if (currentUserId == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(currentUserId).get(),
            builder: (context, snapshot) {
              final isLecturer = snapshot.hasData && snapshot.data!.exists
                  ? (snapshot.data!.data() as Map<String, dynamic>?)?.containsKey('role') ?? false
                      ? (snapshot.data!.data() as Map<String, dynamic>)['role'] == 'Lecturer'
                      : false
                  : false;
              
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isLecturer ? "Today's Tasks" : "Today's Tasks",
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D3436),
                      letterSpacing: -0.5,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AllAssignments(),
                        ),
                      );
                    },
                    child: const Text(
                      "See All",
                      style: TextStyle(
                        color: Color(0xFF6366F1),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          
          // Tasks Stream - Simplified approach
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _getUnsubmittedAssignmentsStream(currentUserId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildLoadingSkeleton();
              }

              if (snapshot.hasError) {
                print('Error loading assignments: ${snapshot.error}');
                return _buildErrorState();
              }

              final assignments = snapshot.data ?? [];

              // Debug: Print assignment data
              print('📊 StreamBuilder received ${assignments.length} assignments');
              for (var assignment in assignments) {
                print('  📋 ${assignment['title']} - ${assignment['isLecturerView'] == true ? 'LECTURER' : 'STUDENT'} view');
              }

              if (assignments.isEmpty) {
                return _buildEmptyState();
              }

                                return SizedBox(
                    height: 140,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: assignments.length,
                      itemBuilder: (context, index) {
                        return _buildTaskCard(assignments[index]);
                      },
                    ),
                  );
            },
          ),
        ],
      ),
    );
  }

  Stream<List<Map<String, dynamic>>> _getUnsubmittedAssignmentsStream(String userId) {
    return FirebaseFirestore.instance
        .collection('classes')
        .where('participants', arrayContains: userId)
        .snapshots()
        .asyncMap((classesSnapshot) async {
      List<Map<String, dynamic>> assignments = [];

      try {
        print('📚 Checking ${classesSnapshot.docs.length} classes for user: $userId');
        
        // Get current user's information to check if they're a lecturer
        final currentUserDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
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
              // Use more robust matching - check both lecturerName and if lecturer is in class
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
                if (classLecturers.docs.length == 1 && classLecturers.docs.first.id == userId) {
                  isLecturerAssignment = true;
                  print('🎯 Match by being sole lecturer in class');
                }
              }
              
              if (isLecturerAssignment) {
                print('🎓 Processing lecturer assignment: $assignmentTitle (LecturerName: "$assignmentLecturerName", CurrentUser: "$currentUserName")');
                
                // Get all students in this class
                final studentsSnapshot = await FirebaseFirestore.instance
                    .collection('users')
                    .where('role', isEqualTo: 'Student')
                    .where(FieldPath.documentId, whereIn: participants.isEmpty ? ['dummy'] : participants)
                    .get();

                final totalStudents = studentsSnapshot.docs.length;
                final studentIds = studentsSnapshot.docs.map((doc) => doc.id).toList();
                final studentNames = studentsSnapshot.docs.map((doc) => doc.data()['name'] ?? 'Unknown').toList();
                
                print('👥 Total students in class: $totalStudents');
                print('📝 Student IDs: $studentIds');
                print('📝 Student names: $studentNames');

                // Get submissions for this assignment - improved logic
                final submissionsSnapshot = await FirebaseFirestore.instance
                    .collection('classes')
                    .doc(classId)
                    .collection('submissions')
                    .where('assignmentId', isEqualTo: assignmentDoc.id)
                    .where('submitted', isEqualTo: true)
                    .get();

                // Count unique student submissions (avoid duplicates)
                Set<String> uniqueStudentIds = {};
                List<String> submittedStudentIds = [];
                
                for (var submissionDoc in submissionsSnapshot.docs) {
                  final submissionData = submissionDoc.data();
                  final studentId = submissionData['studentId'] as String?;
                  
                  if (studentId != null) {
                    uniqueStudentIds.add(studentId);
                    submittedStudentIds.add(studentId);
                  }
                }

                final submittedCount = uniqueStudentIds.length;
                
                // Cross-check: ensure submitted students are actually in the class
                final validSubmissions = uniqueStudentIds.where((studentId) => studentIds.contains(studentId)).toSet();
                final invalidSubmissions = uniqueStudentIds.where((studentId) => !studentIds.contains(studentId)).toSet();
                
                final finalSubmittedCount = validSubmissions.length;
                
                print('📊 Submissions: $finalSubmittedCount/$totalStudents for assignment: $assignmentTitle');
                print('📋 Raw submissions found: ${submissionsSnapshot.docs.length}, Unique students: $submittedCount, Valid: $finalSubmittedCount');
                print('✅ Valid submitted student IDs: ${validSubmissions.toList()}');
                if (invalidSubmissions.isNotEmpty) {
                  print('❌ Invalid submitted student IDs (not in class): ${invalidSubmissions.toList()}');
                }

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
              } else {
                print('❌ Assignment not recognized as lecturer\'s: $assignmentTitle (LecturerName: "$assignmentLecturerName", CurrentUser: "$currentUserName")');
              }
            } else {
              // For students: show unsubmitted assignments (existing logic)
              if (assignmentLecturerName != currentUserName) {
                // Check if user has submitted this assignment
                final submissionSnapshot = await FirebaseFirestore.instance
                    .collection('classes')
                    .doc(classId)
                    .collection('submissions')
                    .where('studentId', isEqualTo: userId)
                    .where('assignmentId', isEqualTo: assignmentDoc.id)
                    .where('submitted', isEqualTo: true)
                    .limit(1)
                    .get();

                // If no submission found, add to unsubmitted list
                if (submissionSnapshot.docs.isEmpty) {
                  final dueDate = assignmentData['dueDate'] as Timestamp?;
                  
                  print('❌ Assignment NOT submitted: $assignmentTitle');
                  
                  assignments.add({
                    'id': assignmentDoc.id,
                    'assignmentId': assignmentDoc.id,
                    'classId': classId,
                    'className': className,
                    'title': assignmentTitle,
                    'dueDate': dueDate,
                    'instructions': assignmentData['instructions'] ?? '',
                    'type': assignmentData['type'] ?? 'assignment',
                    'timestamp': assignmentData['timestamp'],
                    'isLecturerView': false,
                    ...assignmentData,
                  });
                } else {
                  print('✅ Assignment already submitted: $assignmentTitle');
                }
              }
            }
          }
        }

        print('📊 Total assignments found: ${assignments.length}');
        
        // Debug: Print all assignments for lecturers
        if (currentUserRole == 'Lecturer') {
          print('🔍 LECTURER ASSIGNMENTS DEBUG:');
          for (var assignment in assignments) {
            print('  - ${assignment['title']} | Status: ${assignment['submissionStatus']} | Urgency: ${assignment['urgencyLevel']} | Count: ${assignment['submittedCount']}/${assignment['totalStudents']}');
          }
        }

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

  Widget _buildTaskCard(Map<String, dynamic> assignment) {
    final dueDate = assignment['dueDate'] as Timestamp?;
    final now = DateTime.now();
    final dueDateObj = dueDate?.toDate();
    final isLecturerView = assignment['isLecturerView'] ?? false;
    
    Color cardColor;
    Color accentColor = Colors.white;
    String urgencyText;
    
    if (isLecturerView) {
      // Lecturer view - color based on submission status
      final urgencyLevel = assignment['urgencyLevel'] ?? 'info';
      final submissionStatus = assignment['submissionStatus'] ?? 'Unknown';
      final submittedCount = assignment['submittedCount'] ?? 0;
      final totalStudents = assignment['totalStudents'] ?? 0;
      
      switch (urgencyLevel) {
        case 'completed':
          cardColor = const Color(0xFF10B981); // Green - all submitted
          urgencyText = 'Work Done';
          break;
        case 'pending':
          cardColor = const Color(0xFFF59E0B); // Orange - partially submitted
          urgencyText = 'Pending ($submittedCount/$totalStudents)';
          break;
        case 'overdue':
          cardColor = const Color(0xFFDC2626); // Red - no submissions
          urgencyText = 'No Submissions';
          break;
        case 'info':
        default:
          cardColor = const Color(0xFF6B7280); // Gray - no students
          urgencyText = 'No Students';
          break;
      }
    } else {
      // Student view - existing logic
      bool isOverdue = dueDateObj != null && dueDateObj.isBefore(now);
      bool isDueSoon = dueDateObj != null && 
          dueDateObj.difference(now).inHours <= 24 && 
          dueDateObj.isAfter(now);
      
      if (isOverdue) {
        // Past due - Red color
        cardColor = const Color(0xFFDC2626); // Darker red
        urgencyText = 'Past Due';
      } else if (isDueSoon) {
        // Due soon - Orange/Amber color
        cardColor = const Color(0xFFF59E0B); // Amber
        urgencyText = 'Due Soon';
      } else if (dueDateObj != null) {
        // Not submitted, has due date, not urgent - Blue color
        cardColor = const Color(0xFF3B82F6); // Blue
        urgencyText = 'Pending';
      } else {
        // No due date - Purple color
        cardColor = const Color(0xFF8B5CF6); // Purple
        urgencyText = 'No Due Date';
      }
    }

    return Container(
      width: 240,
      margin: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ClassDetails(
                announcement: assignment,
                classId: assignment['classId'],
              ),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cardColor,
                cardColor.withOpacity(0.85),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: cardColor.withOpacity(0.25),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Subtle decorative circle
              Positioned(
                right: -15,
                top: -15,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
              ),
              
              // Content
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with urgency badge and icon
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            urgencyText,
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.assignment_outlined,
                          color: accentColor.withOpacity(0.9),
                          size: 18,
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 10),
                    
                    // Assignment title - more compact
                    Text(
                      assignment['title'] ?? 'Assignment',
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    const SizedBox(height: 6),
                    
                    // Class name - smaller
                    Text(
                      assignment['className'] ?? 'Unknown Class',
                      style: TextStyle(
                        color: accentColor.withOpacity(0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    const Spacer(),
                    
                    // Bottom info - different for lecturers vs students
                    Row(
                      children: [
                        Icon(
                          isLecturerView ? Icons.people_outlined : Icons.schedule_outlined,
                          color: accentColor.withOpacity(0.8),
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            isLecturerView
                                ? (assignment['totalStudents'] > 0
                                    ? '${assignment['submittedCount']}/${assignment['totalStudents']} submitted'
                                    : 'No students enrolled')
                                : (dueDateObj != null 
                                    ? '${dueDateObj.day}/${dueDateObj.month} ${dueDateObj.hour}:${dueDateObj.minute.toString().padLeft(2, '0')}'
                                    : 'No due date'),
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            Icons.arrow_forward_ios,
                            color: accentColor,
                            size: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return SizedBox(
      height: 140,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        itemBuilder: (context, index) {
          return Container(
            width: 240,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.grey[200]!,
                width: 1,
              ),
            ),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                ),
              ),
            ),
          );
        },
      ),
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
          height: 140,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF10B981).withOpacity(0.08),
                const Color(0xFF059669).withOpacity(0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
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
                  size: 36,
                  color: Color(0xFF10B981),
                ),
                const SizedBox(height: 8),
                Text(
                  isLecturer ? 'All assignments reviewed!' : 'All caught up!',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF065F46),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isLecturer ? 'No assignments to track' : 'No pending assignments',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF047857),
                  ),
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
      height: 140,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFEF4444).withOpacity(0.08),
            const Color(0xFFDC2626).withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFEF4444).withOpacity(0.15),
          width: 1,
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 36,
              color: Color(0xFFEF4444),
            ),
            SizedBox(height: 8),
            Text(
              'Oops! Something went wrong',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF991B1B),
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Unable to load assignments',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFFB91C1C),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
