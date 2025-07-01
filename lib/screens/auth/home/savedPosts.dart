import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

final Map<String, Color> universityColors = {
  'primary': Color(0xFF1E3A8A),        // University Navy Blue
  'secondary': Color(0xFF3B82F6),      // Bright Blue
  'accent': Color(0xFF6366F1),         // Indigo
  'success': Color(0xFF10B981),        // Emerald Green
  'warning': Color(0xFFF59E0B),        // Amber
  'error': Color(0xFFEF4444),          // Red
  'background': Color(0xFFF8FAFC),     // Light Gray Blue
  'surface': Color(0xFFFFFFFF),        // Pure White
  'gold': Color(0xFFD97706),           // University Gold
};

class SavedPostsPage extends StatefulWidget {
  const SavedPostsPage({super.key});

  @override
  _SavedPostsPageState createState() => _SavedPostsPageState();
}

class _SavedPostsPageState extends State<SavedPostsPage> with TickerProviderStateMixin {
  List<Map<String, dynamic>> savedPosts = [];
  bool isLoading = true;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Stream<QuerySnapshot>? _savedPostsStream;

  // Define categories for saved posts
  final List<Map<String, dynamic>> _categories = [
    {
      'name': 'All',
      'icon': Icons.bookmark_rounded,
      'color': universityColors['primary'],
      'gradient': [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
    },
    {
      'name': 'Academic',
      'icon': Icons.school_rounded,
      'color': universityColors['accent'],
      'gradient': [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    },
    {
      'name': 'Events',
      'icon': Icons.event_rounded,
      'color': universityColors['success'],
      'gradient': [Color(0xFF10B981), Color(0xFF34D399)],
    },
    {
      'name': 'Important',
      'icon': Icons.priority_high_rounded,
      'color': universityColors['error'],
      'gradient': [Color(0xFFEF4444), Color(0xFFF87171)],
    },
    {
      'name': 'Sports',
      'icon': Icons.sports_basketball_rounded,
      'color': universityColors['warning'],
      'gradient': [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    },
    {
      'name': 'General',
      'icon': Icons.announcement_rounded,
      'color': universityColors['secondary'],
      'gradient': [Color(0xFF3B82F6), Color(0xFF60A5FA)],
    },
  ];

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    
    _initializeStream();
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _initializeStream() {
    User? user = _auth.currentUser;
    if (user != null) {
      _savedPostsStream = FirebaseFirestore.instance
          .collection('saved_posts')
          .where('userId', isEqualTo: user.uid)
          .snapshots();
    }
  }

  List<Map<String, dynamic>> _processSavedPosts(QuerySnapshot snapshot) {
    List<Map<String, dynamic>> posts = [];
    for (QueryDocumentSnapshot doc in snapshot.docs) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      data['docId'] = doc.id; // Store document ID for deletion
      posts.add(data);
    }
    
    // Sort posts by savedAt timestamp (newest first)
    posts.sort((a, b) {
      try {
        Timestamp? aTime = a['savedAt'] as Timestamp?;
        Timestamp? bTime = b['savedAt'] as Timestamp?;
        
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        
        return bTime.compareTo(aTime);
      } catch (e) {
        // Fallback to original timestamp if savedAt is not available
        DateTime aTime = _parseTimestamp(a["timestamp"]);
        DateTime bTime = _parseTimestamp(b["timestamp"]);
        return bTime.compareTo(aTime);
      }
    });
    
    return posts;
  }

  Future<void> _removeSavedPost(Map<String, dynamic> post) async {
    try {
      // Get current user
      User? user = _auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please login to remove saved posts'),
            backgroundColor: universityColors['error'],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        return;
      }

      // Remove from Firebase using document ID
      String docId = post['docId'];
      await FirebaseFirestore.instance
          .collection('saved_posts')
          .doc(docId)
          .delete();
      
      // Update UI
      setState(() {
        savedPosts.removeWhere((savedPost) => savedPost['docId'] == docId);
      });
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Post removed from saved'),
            ],
          ),
          backgroundColor: universityColors['success'],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      print('Error removing saved post: $e');
      
      String errorMessage = 'Failed to remove post';
      if (e.toString().contains('network')) {
        errorMessage = 'Network error. Please check your connection.';
      } else if (e.toString().contains('permission')) {
        errorMessage = 'Permission denied. Please try again.';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(child: Text(errorMessage)),
            ],
          ),
          backgroundColor: universityColors['error'],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _removeSavedPost(post),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: universityColors['background'],
      extendBodyBehindAppBar: true,
      appBar: _buildModernAppBar(),
      body: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                SizedBox(height: kToolbarHeight + MediaQuery.of(context).padding.top - 60),
                _buildSavedHeader(),
                _buildCategoryTabs(),
                Expanded(child: _buildSavedPostsList()),
              ],
            ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildModernAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              universityColors['primary']!,
              universityColors['secondary']!,
            ],
          ),
        ),
      ),
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.bookmark_rounded,
              size: 24,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 12),
          Text(
            "SAVED POSTS",
            style: TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: Colors.white,
              fontSize: 18,
            ),
          ),
        ],
      ),
      centerTitle: true,
    );
  }

  Widget _buildSavedHeader() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            universityColors['background']!.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: universityColors['primary']!.withOpacity(0.1),
            blurRadius: 15,
            offset: Offset(0, 6),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [universityColors['primary']!, universityColors['secondary']!],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: universityColors['primary']!.withOpacity(0.3),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              Icons.bookmark_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "My Saved Posts",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: universityColors['primary'],
                  ),
                ),
                SizedBox(height: 3),
                StreamBuilder<QuerySnapshot>(
                  stream: _savedPostsStream,
                  builder: (context, snapshot) {
                    int count = 0;
                    if (snapshot.hasData) {
                      count = snapshot.data!.docs.length;
                    }
                    return Text(
                      "$count saved announcements",
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: universityColors['primary']!.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: universityColors['primary']!.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.collections_bookmark_rounded,
                  color: universityColors['primary'],
                  size: 14,
                ),
                SizedBox(width: 4),
                Text(
                  "Collection",
                  style: TextStyle(
                    color: universityColors['primary'],
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return Container(
      height: 50,
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = _selectedIndex == index;
          
          return Container(
            margin: EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () => setState(() => _selectedIndex = index),
              child: AnimatedContainer(
                duration: Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: isSelected 
                      ? LinearGradient(colors: category['gradient'])
                      : LinearGradient(colors: [Colors.white, Colors.white]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: category['color'].withOpacity(0.3),
                            blurRadius: 12,
                            offset: Offset(0, 6),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                  border: isSelected
                      ? null
                      : Border.all(
                          color: Colors.grey.withOpacity(0.2),
                          width: 1,
                        ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      category['icon'],
                      size: 16,
                      color: isSelected ? Colors.white : category['color'],
                    ),
                    SizedBox(width: 6),
                    Text(
                      category['name'],
                      style: TextStyle(
                        color: isSelected ? Colors.white : category['color'],
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSavedPostsList() {
    User? user = _auth.currentUser;
    
    if (user == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_outline_rounded,
              size: 80,
              color: universityColors['primary']!.withOpacity(0.5),
            ),
            SizedBox(height: 16),
            Text(
              'Please Login',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: universityColors['primary'],
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Login to view your saved posts',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (_savedPostsStream == null) {
      return _buildLoadingState();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _savedPostsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingState();
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 80,
                  color: universityColors['error']!.withOpacity(0.5),
                ),
                SizedBox(height: 16),
                Text(
                  'Error Loading Posts',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: universityColors['error'],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Please check your connection and try again',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _initializeStream(),
                  child: Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: universityColors['primary'],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        List<Map<String, dynamic>> allPosts = _processSavedPosts(snapshot.data!);
        List<Map<String, dynamic>> filteredPosts = _selectedIndex == 0
            ? allPosts
            : allPosts.where((post) =>
                post["category"]?.toLowerCase() ==
                _categories[_selectedIndex]['name'].toLowerCase()).toList();

        return RefreshIndicator(
          onRefresh: () async {
            // Refresh is automatic with streams, just provide feedback
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Posts updated in real-time'),
                backgroundColor: universityColors['success'],
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 1),
              ),
            );
          },
          color: universityColors['primary'],
          backgroundColor: Colors.white,
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: filteredPosts.length,
            itemBuilder: (context, index) {
              return _buildSavedPostCard(filteredPosts[index]);
            },
          ),
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [universityColors['primary']!, universityColors['secondary']!],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: universityColors['primary']!.withOpacity(0.3),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 3,
              ),
            ),
          ),
          SizedBox(height: 24),
          Text(
            "Loading Saved Posts",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: universityColors['primary'],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  universityColors['primary']!.withOpacity(0.1),
                  universityColors['secondary']!.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Icon(
              Icons.bookmark_border_rounded,
              size: 60,
              color: universityColors['primary'],
            ),
          ),
          SizedBox(height: 24),
          Text(
            'No Saved Posts Yet',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: universityColors['primary'],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Save important announcements to view them here',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSavedPostCard(Map<String, dynamic> post) {
    final hasImage = post["imageUrl"] != null && post["imageUrl"].toString().isNotEmpty;
    DateTime timestamp = _parseTimestamp(post["timestamp"]);
    final formattedTime = DateFormat('MMM d, yyyy • h:mm a').format(timestamp);
    final category = post["category"] ?? "General";
    
    // Get category info
    final categoryInfo = _categories.firstWhere(
      (cat) => cat['name'].toLowerCase() == category.toLowerCase(),
      orElse: () => _categories.last,
    );

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: universityColors['primary']!.withOpacity(0.08),
            blurRadius: 20,
            offset: Offset(0, 6),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with gradient
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: categoryInfo['gradient'],
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    categoryInfo['icon'],
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        formattedTime,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.bookmark_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post["message"],
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Colors.grey[800],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                
                if (hasImage) ...[
                  SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: double.infinity,
                      height: 180,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.grey.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Image.network(
                        post["imageUrl"],
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      (loadingProgress.expectedTotalBytes ?? 1)
                                  : null,
                              valueColor: AlwaysStoppedAnimation<Color>(categoryInfo['color']),
                              strokeWidth: 3,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.image_not_supported_rounded,
                                  color: Colors.grey[400],
                                  size: 40,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  "Image unavailable",
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Action Bar
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                _buildActionButton(
                  icon: Icons.bookmark_remove_rounded,
                  label: "Remove",
                  color: universityColors['error']!,
                  onTap: () => _removeSavedPost(post),
                ),
                SizedBox(width: 12),
                Container(
                  width: 1,
                  height: 20,
                  color: Colors.grey[300],
                ),
                SizedBox(width: 12),
                _buildActionButton(
                  icon: Icons.share_rounded,
                  label: "Share",
                  color: categoryInfo['color'],
                  onTap: () {},
                ),
                Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: categoryInfo['color'].withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bookmark_rounded,
                        size: 16,
                        color: categoryInfo['color'],
                      ),
                      SizedBox(width: 6),
                      Text(
                        "Saved",
                        style: TextStyle(
                          color: categoryInfo['color'],
                          fontWeight: FontWeight.w600,
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
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: color,
            ),
            SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime _parseTimestamp(dynamic ts) {
    if (ts is String) {
      try {
        return DateTime.parse(ts);
      } catch (_) {
        try {
          return DateFormat("MMM d, yyyy 'at' h:mm:ss a 'UTC'Z").parse(ts, true).toLocal();
        } catch (_) {
          return DateTime.now();
        }
      }
    }
    if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts);
    return DateTime.now();
  }
} 