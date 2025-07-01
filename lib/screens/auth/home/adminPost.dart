import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; 
import 'package:twitterr/screens/auth/home/addAdminPost.dart';
import 'package:twitterr/screens/auth/home/savedPosts.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:http/http.dart' as http;

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

class AdminPostPage extends StatefulWidget {
  const AdminPostPage({super.key});

  @override
  _AdminPostPageState createState() => _AdminPostPageState();
}

class _AdminPostPageState extends State<AdminPostPage> with TickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<Map<String, dynamic>> adminPosts = [];
  bool isAdmin = false;
  bool isLoading = true;
  late AnimationController _refreshController;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  int _selectedIndex = 0;
  
  // Define enhanced categories for university environment
  final List<Map<String, dynamic>> _categories = [
    {
      'name': 'All',
      'icon': Icons.dashboard_rounded,
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

  // Add these variables at the top of your class
  Timer? _reconnectTimer;
  StreamSubscription? _streamSubscription;
  bool _isConnecting = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const int _reconnectDelay = 3; // seconds

  @override
  void initState() {
    super.initState();
    _refreshController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    
    _checkIfAdmin();
    _listenToAdminPosts();
    
    // Start animations
    _fadeController.forward();
    _slideController.forward();
  }

  void _checkIfAdmin() {
    User? user = _auth.currentUser;
    String? userEmail = user?.email;

    setState(() {
      isAdmin = userEmail != null && userEmail.endsWith("@admin.uitm.edu.my");
    });
  }

  Future<void> _listenToAdminPosts() async {
    if (_isConnecting) {
      print("Already connecting, skipping...");
      return;
    }

    _isConnecting = true;
    setState(() {
      isLoading = true;
    });

    try {
      await _connectToSSE();
    } catch (e) {
      print("Connection Error: $e");
      _handleConnectionError();
    }
  }

  Future<void> _connectToSSE() async {
    try {
      print("🔄 Attempting SSE connection (attempt ${_reconnectAttempts + 1})...");
      
      final client = http.Client();
      final request = http.Request('GET', Uri.parse("https://sharenow-ipuj.onrender.com/events"));
      
      // Add headers for better compatibility
      request.headers.addAll({
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      });

      final response = await client.send(request);
      
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: Failed to connect to SSE');
      }

      print("✅ SSE connection established successfully");
      _reconnectAttempts = 0; // Reset on successful connection
      _isConnecting = false;

      setState(() {
        isLoading = false;
      });

      // Listen to the stream
      _streamSubscription = response.stream
          .timeout(
            Duration(seconds: 65), // Longer than server heartbeat (30s)
            onTimeout: (sink) {
              print("⏰ SSE connection timeout, reconnecting...");
              sink.close();
              _handleConnectionError();
            },
          )
          .transform(utf8.decoder)
          .transform(LineSplitter())
          .listen(
            (line) {
              _handleSSELine(line);
            },
            onError: (error) {
              print("📡 SSE Stream Error: $error");
              _handleConnectionError();
            },
            onDone: () {
              print("📡 SSE Stream closed");
              _handleConnectionError();
            },
          );

    } catch (e) {
      print("❌ SSE Connection failed: $e");
      _isConnecting = false;
      _handleConnectionError();
    }
  }

  void _handleSSELine(String line) {
    if (line.startsWith('data: ')) {
      String jsonString = line.substring(6).trim();
      
      if (jsonString.isEmpty) return;
      
      try {
        final jsonData = jsonDecode(jsonString);
        
        // Handle connection confirmation
        if (jsonData is Map<String, dynamic> && jsonData.containsKey("status")) {
          if (jsonData["status"] == "connected") {
            print("✅ SSE connection confirmed by server");
            return;
          }
          if (jsonData["status"] == "alive") {
            // Heartbeat received, connection is healthy
            return;
          }
        }
        
        // Handle announcement data
        if (jsonData is Map<String, dynamic> && jsonData.containsKey("message")) {
          setState(() {
            bool isDuplicate = adminPosts.any((post) => 
              post["message"] == jsonData["message"]);

            if (!isDuplicate) {
              adminPosts.insert(0, {
                "message": jsonData["message"].toString(),
                "imageUrl": jsonData["imageUrl"] ?? "",
                "timestamp": jsonData["timestamp"] ?? DateTime.now().toString(),
                "category": jsonData["category"] ?? "General",
              });

              adminPosts.sort((a, b) {
                DateTime aTime = _parseTimestamp(a["timestamp"]);
                DateTime bTime = _parseTimestamp(b["timestamp"]);
                return bTime.compareTo(aTime);
              });
            }
          });
          
          print("📢 New announcement received: ${jsonData["message"]}");
        }
        
      } catch (e) {
        print("JSON Parsing Error: $e | Raw Data: $jsonString");
      }
    }
  }

  void _handleConnectionError() {
    _isConnecting = false;
    
    // Cancel existing subscription
    _streamSubscription?.cancel();
    _streamSubscription = null;
    
    // Cancel existing timer
    _reconnectTimer?.cancel();
    
    if (_reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      int delay = _reconnectDelay * _reconnectAttempts; // Progressive delay
      
      print("🔄 Reconnecting in $delay seconds... (${_reconnectAttempts}/$_maxReconnectAttempts)");
      
      _reconnectTimer = Timer(Duration(seconds: delay), () {
        if (mounted) {
          _listenToAdminPosts();
        }
      });
    } else {
      print("❌ Max reconnection attempts reached");
      setState(() {
        isLoading = false;
      });
      
      // Show user-friendly error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection lost. Pull down to refresh.'),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () {
              _reconnectAttempts = 0;
              _listenToAdminPosts();
            },
          ),
        ),
      );
    }
  }

  void _disconnectEventSource() {
    try {
      _reconnectTimer?.cancel();
      _streamSubscription?.cancel();
      _streamSubscription = null;
      _isConnecting = false;
      _reconnectAttempts = 0;
      print("🔌 SSE connection disconnected");
    } catch (e) {
      print("Error disconnecting SSE: $e");
    }
  }

  Future<void> _refreshAnnouncements() async {
    setState(() {
      isLoading = true;
      adminPosts.clear();
    });

    try {
      _disconnectEventSource();
      _reconnectAttempts = 0; // Reset retry count on manual refresh
      await Future.delayed(Duration(milliseconds: 500));
      await _listenToAdminPosts();
    } catch (e) {
      print("Error refreshing announcements: $e");
      setState(() {
        isLoading = false;
      });
    }
    
    _refreshController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _disconnectEventSource();
    _refreshController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  String getFormattedTimestamp(DateTime timestamp) {
    return DateFormat('MMM d, yyyy • h:mm a').format(timestamp);
  }

  Future<bool> _isPostSaved(Map<String, dynamic> post) async {
    try {
      User? user = _auth.currentUser;
      if (user == null) return false;

      String postId = '${user.uid}_${post["timestamp"]}_${post["message"].hashCode}';
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('saved_posts')
          .doc(postId)
          .get();
      
      return doc.exists;
    } catch (e) {
      print('Error checking if post is saved: $e');
      return false;
    }
  }

  Future<void> _toggleSavePost(Map<String, dynamic> post) async {
    try {
      User? user = _auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please login to save posts'),
            backgroundColor: universityColors['error'],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        return;
      }

      String postId = '${user.uid}_${post["timestamp"]}_${post["message"].hashCode}';
      DocumentReference docRef = FirebaseFirestore.instance
          .collection('saved_posts')
          .doc(postId);
      
      DocumentSnapshot doc = await docRef.get();
      
      if (doc.exists) {
        // Post is saved, so unsave it
        await docRef.delete();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.bookmark_remove_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Post removed from saved'),
              ],
            ),
            backgroundColor: universityColors['warning'],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } else {
        // Post is not saved, so save it
        await docRef.set({
          'userId': user.uid,
          'userEmail': user.email,
          'message': post["message"],
          'imageUrl': post["imageUrl"] ?? "",
          'timestamp': post["timestamp"],
          'category': post["category"] ?? "General",
          'savedAt': FieldValue.serverTimestamp(),
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.bookmark_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Post saved successfully!'),
              ],
            ),
            backgroundColor: universityColors['success'],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SavedPostsPage()),
                );
              },
            ),
          ),
        );
      }
      
      // Trigger a rebuild of the UI to update the save button
      setState(() {});
      
    } catch (e) {
      print('Error toggling save post: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(child: Text('Failed to update save status')),
            ],
          ),
          backgroundColor: universityColors['error'],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      floatingActionButton: _buildFloatingActionButton(),
      body: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Column(
                children: [
                  SizedBox(height: kToolbarHeight + MediaQuery.of(context).padding.top -60),
                  _buildUniversityHeader(),
                  _buildModernCategoryTabs(),
                  Expanded(child: _buildAnnouncementsList()),
                ],
              ),
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
      leading: Container(
        margin: EdgeInsets.only(left: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: IconButton(
          icon: Icon(Icons.bookmark_rounded, color: Colors.white),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => SavedPostsPage()),
            );
          },
        ),
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
              Icons.campaign_rounded,
              size: 24,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 12),
          Text(
            "ANNOUNCEMENTS",
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
      actions: [
        Container(
          margin: EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: RotationTransition(
            turns: Tween(begin: 0.0, end: 1.0).animate(_refreshController),
            child: IconButton(
              icon: Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: _refreshAnnouncements,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUniversityHeader() {
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
              Icons.account_balance_rounded,
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
                  "UiTM Official",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: universityColors['primary'],
                  ),
                ),
                SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      color: universityColors['success'],
                      size: 14,
                    ),
                    SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        "Verified University Account",
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: universityColors['success']!.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: universityColors['success']!.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: universityColors['success'],
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 4),
                Text(
                  "Live",
                  style: TextStyle(
                    color: universityColors['success'],
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

  Widget _buildModernCategoryTabs() {
    return Container(
      height: 50,
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = _selectedIndex == index;
          
          return TweenAnimationBuilder<double>(
            duration: Duration(milliseconds: 200 + (index * 50)),
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(30 * (1 - value), 0),
                child: Opacity(
                  opacity: value,
                  child: Container(
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
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    if (!isAdmin) return Container();
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [universityColors['primary']!, universityColors['secondary']!],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: universityColors['primary']!.withOpacity(0.4),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => PostPage(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1.0, 0.0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                );
              },
            ),
          );

          if (result == true) {
            _refreshAnnouncements();
          }
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        label: Text(
          "Create",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        icon: Icon(
          Icons.add_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildAnnouncementsList() {
    if (isLoading) {
      return _buildModernLoadingState();
    }

    if (adminPosts.isEmpty) {
      return _buildModernEmptyState();
    }

    List<Map<String, dynamic>> filteredPosts = _selectedIndex == 0
        ? adminPosts
        : adminPosts.where((post) =>
            post["category"]?.toLowerCase() ==
            _categories[_selectedIndex]['name'].toLowerCase()).toList();

    return RefreshIndicator(
      onRefresh: _refreshAnnouncements,
      color: universityColors['primary'],
      backgroundColor: Colors.white,
      child: ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: filteredPosts.length,
        itemBuilder: (context, index) {
          return TweenAnimationBuilder<double>(
            duration: Duration(milliseconds: 300 + (index * 100)),
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 30 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: _buildModernAnnouncementCard(filteredPosts[index]),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildModernLoadingState() {
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
            "Loading Announcements",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: universityColors['primary'],
            ),
          ),
          SizedBox(height: 8),
          Text(
            "Fetching the latest updates...",
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernEmptyState() {
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
              Icons.campaign_outlined,
              size: 60,
              color: universityColors['primary'],
            ),
          ),
          SizedBox(height: 24),
          Text(
            'No Announcements Yet',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: universityColors['primary'],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Stay tuned for important updates',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
            ),
          ),
          SizedBox(height: 24),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [universityColors['primary']!, universityColors['secondary']!],
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: universityColors['primary']!.withOpacity(0.3),
                  blurRadius: 15,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Text(
              "Check back soon",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernAnnouncementCard(Map<String, dynamic> post) {
    final hasImage = post["imageUrl"] != null && post["imageUrl"].toString().isNotEmpty;
    DateTime timestamp = _parseTimestamp(post["timestamp"]);
    final formattedTime = getFormattedTimestamp(timestamp);
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
                    Icons.verified_rounded,
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
                FutureBuilder<bool>(
                  future: _isPostSaved(post),
                  builder: (context, snapshot) {
                    bool isSaved = snapshot.data ?? false;
                    return _buildActionButton(
                      icon: isSaved ? Icons.bookmark_rounded : Icons.bookmark_add_rounded,
                      label: isSaved ? "Saved" : "Save",
                      color: isSaved ? universityColors['success']! : categoryInfo['color'],
                      onTap: () => _toggleSavePost(post),
                      isSaved: isSaved,
                    );
                  },
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
                        Icons.visibility_rounded,
                        size: 16,
                        color: categoryInfo['color'],
                      ),
                      SizedBox(width: 6),
                      Text(
                        "View",
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
    bool isSaved = false,
  }) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isHovered = false;
        bool isPressed = false;
        
        return MouseRegion(
          onEnter: (_) => setState(() => isHovered = true),
          onExit: (_) => setState(() => isHovered = false),
          child: GestureDetector(
            onTapDown: (_) => setState(() => isPressed = true),
            onTapUp: (_) => setState(() => isPressed = false),
            onTapCancel: () => setState(() => isPressed = false),
            onTap: onTap,
            child: AnimatedContainer(
              duration: Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isPressed
                    ? color.withOpacity(0.3)
                    : isHovered
                        ? color.withOpacity(0.2)
                        : isSaved
                            ? color.withOpacity(0.15)
                            : color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isHovered
                      ? color.withOpacity(0.6)
                      : isSaved
                          ? color.withOpacity(0.5)
                          : color.withOpacity(0.3),
                  width: isHovered ? 1.5 : isSaved ? 1.2 : 1,
                ),
                boxShadow: (isHovered || isSaved)
                    ? [
                        BoxShadow(
                          color: color.withOpacity(isSaved ? 0.25 : 0.2),
                          blurRadius: isSaved ? 10 : 8,
                          offset: Offset(0, isSaved ? 3 : 2),
                        ),
                      ]
                    : [],
              ),
              transform: Matrix4.identity()
                ..scale(isPressed ? 0.95 : isHovered ? 1.05 : 1.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: Duration(milliseconds: 200),
                    child: Icon(
                      icon,
                      size: isHovered ? 18 : isSaved ? 17 : 16,
                      color: isHovered 
                          ? color 
                          : isSaved 
                              ? color 
                              : color.withOpacity(0.8),
                    ),
                  ),
                  SizedBox(width: 6),
                  AnimatedDefaultTextStyle(
                    duration: Duration(milliseconds: 200),
                    style: TextStyle(
                      color: isHovered 
                          ? color 
                          : isSaved 
                              ? color 
                              : color.withOpacity(0.8),
                      fontWeight: isHovered 
                          ? FontWeight.w700 
                          : isSaved 
                              ? FontWeight.w700 
                              : FontWeight.w600,
                      fontSize: isHovered ? 15 : isSaved ? 14.5 : 14,
                    ),
                    child: Text(label),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  DateTime _parseTimestamp(dynamic ts) {
    if (ts is Timestamp) return ts.toDate();
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