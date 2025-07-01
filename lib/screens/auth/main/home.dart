import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:twitterr/screens/auth/home/adminPost.dart';
import 'package:twitterr/screens/auth/home/feed.dart';
import 'package:twitterr/screens/auth/home/search.dart';
import 'package:twitterr/screens/auth/chat/chat.dart';
import 'package:twitterr/screens/auth/main/posts/add.dart';
import 'package:twitterr/screens/auth/submission/submission.dart';
import 'package:twitterr/services/auth.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  late AnimationController _navAnimationController;
  late Animation<double> _navSlideAnimation;

  int _currentIndex = 0;
  final List<Widget> _pages = [
    Feed(),
    AdminPostPage(),
    Search(),
    Submission(),
    Chat(),
  ];

  @override
  void initState() {
    super.initState();
    _navAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _navSlideAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _navAnimationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _navAnimationController.dispose();
    super.dispose();
  }

  void onTabPressed(int index) {
    setState(() {
      _currentIndex = index;
    });
    _navAnimationController.forward().then((_) {
      _navAnimationController.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB), // Modern light gray-blue
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8FAFB), // Light blue-gray
              Color(0xFFFBFCFD), // Almost white with blue tint
              Color(0xFFFFFFFF), // Pure white
            ],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                if (_currentIndex == 0)
                  const SizedBox(height: 95), // Space for modern header
                Expanded(child: _pages[_currentIndex]),
              ],
            ),
            if (_currentIndex == 0) ...[
              // Modern header with updated gradient
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 120,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF6366F1), // Softer indigo
                        Color(0xFF8B5CF6), // Muted violet
                        Color(0xFF06B6D4), // Refined cyan
                      ],
                      stops: [0.0, 0.6, 1.0],
                    ),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(28),
                      bottomRight: Radius.circular(28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x126366F1), // More subtle shadow
                        blurRadius: 25,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 55,
                left: 20,
                child: _buildProfileAvatar(uid),
              ),
              Positioned(
                top: 55,
                right: 20,
                child: _buildLogoutButton(),
              ),
              Positioned(
                top: 60,
                left: 100,
                right: 100,
                child: _buildFloatingNavBar(),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _currentIndex,
        onTabPressed: onTabPressed,
        animationController: _navAnimationController,
      ),
      floatingActionButton: _currentIndex == 0
          ? Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)], // Softer gradient
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.25), // Reduced opacity
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: FloatingActionButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => Add()),
                  );
                },
                backgroundColor: Colors.transparent,
                elevation: 0,
                child: const Icon(Icons.add, color: Colors.white, size: 28),
              ),
            )
          : null,
    );
  }

  Widget _buildProfileAvatar(String? uid) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFFFB75E), Color(0xFFED8F03)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const CircleAvatar(
              radius: 25,
              backgroundColor: Colors.transparent,
              child: Icon(Icons.person, color: Colors.white, size: 30),
            ),
          );
        }

        var userData = snapshot.data!.data() as Map<String, dynamic>?;
        String profileImageUrl = userData?['profileImageUrl'] ?? '';

        return GestureDetector(
          onTap: () {
            Navigator.pushNamed(context, '/profile', arguments: uid);
          },
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF6366F1).withOpacity(0.06), // Very subtle border
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 25,
              backgroundColor: const Color(0xFFEEF2FF), // Very light indigo
              backgroundImage: profileImageUrl.isNotEmpty ? NetworkImage(profileImageUrl) : null,
              child: profileImageUrl.isEmpty
                  ? const Icon(Icons.person, size: 30, color: Color(0xFF6366F1))
                  : null,
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogoutButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
      ),
      child: IconButton(
        icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 24),
        onPressed: () => _showLogoutConfirmation(context),
      ),
    );
  }

  Widget _buildFloatingNavBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.08), // More subtle
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
        border: Border.all(
          color: const Color(0xFF6366F1).withOpacity(0.06), // Very subtle border
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: const Text(
        "SHARENOW",
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6366F1), // Softer indigo
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Logout", style: TextStyle(fontWeight: FontWeight.w600)),
          content: const Text("Are you sure you want to log out?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel", style: TextStyle(color: Color(0xFF6366F1))),
            ),
            TextButton(
              onPressed: () async {
                await _authService.signOut();
                Navigator.of(context).pop();
                Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
              },
              child: const Text("Logout", style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
}

class CustomBottomNavBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTabPressed;
  final AnimationController animationController;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabPressed,
    required this.animationController,
  });

  @override
  State<CustomBottomNavBar> createState() => _CustomBottomNavBarState();
}

class _CustomBottomNavBarState extends State<CustomBottomNavBar>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;

  final List<String> _labels = ["Home", "Announcements", "Search", "Submission", "Chat"];
  final List<IconData> _icons = [
    Icons.home_rounded,
    Icons.school_rounded,
    Icons.search_rounded,
    Icons.assignment_rounded,
    Icons.chat_bubble_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOutBack,
    ));
  }

  @override
  void didUpdateWidget(CustomBottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _slideController.forward().then((_) {
        _slideController.reset();
      });
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.08), // More subtle
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Animated background indicator
          AnimatedBuilder(
            animation: _slideAnimation,
            builder: (context, child) {
              return AnimatedPositioned(
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeInOutCubic,
                left: _calculateIndicatorPosition(),
                top: 8,
                child: Transform.scale(
                  scale: 1.0 + (_slideAnimation.value * 0.15),
                  child: Container(
                    width: _calculateIndicatorWidth(),
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)], // Softer colors
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.3), // Reduced from 0.5
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // Navigation items
          Positioned.fill(
            child: Row(
              children: List.generate(_icons.length, (index) {
                bool isSelected = widget.currentIndex == index;
                return Flexible(
                  flex: isSelected ? 3 : 1, // Selected item gets 3x space, others get 1x
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOutCubic,
                    child: _buildNavItem(_icons[index], _labels[index], index),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  double _calculateIndicatorPosition() {
    final screenWidth = MediaQuery.of(context).size.width;
    final navBarWidth = screenWidth - 20; // Account for horizontal margins (10*2)
    
    // Calculate dynamic positioning based on flex system
    final totalFlex = _icons.length + 2; // 1 + 1 + 1 + 3 + 1 = 7 (when one is selected)
    final unitWidth = navBarWidth / totalFlex;
    
    double position = 0;
    for (int i = 0; i < widget.currentIndex; i++) {
      position += unitWidth; // Each non-selected item takes 1 unit
    }
    
    // Center the indicator within the selected item's expanded space
    final selectedItemWidth = unitWidth * 3; // Selected item takes 3 units
    final indicatorWidth = _calculateIndicatorWidth();
    position += (selectedItemWidth / 2) - (indicatorWidth / 2);
    
    return position.clamp(5.0, navBarWidth - indicatorWidth - 5);
  }

  double _calculateIndicatorWidth() {
    // Calculate width based on text length for selected item
    final text = _labels[widget.currentIndex];
    final fontSize = _getFontSizeForText(text);
    
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    
    // Calculate available width for expanded selected item
    final screenWidth = MediaQuery.of(context).size.width;
    final navBarWidth = screenWidth - 20;
    final totalFlex = _icons.length + 2; // Total flex units
    final unitWidth = navBarWidth / totalFlex;
    final selectedItemWidth = unitWidth * 3; // Selected item width
    
    // Make bubble fit within the expanded space
    return (textPainter.width + 65).clamp(70.0, selectedItemWidth - 10); // More generous padding
  }

  double _getFontSizeForText(String text) {
    // Dynamic font sizing - can be larger now due to expanded space
    if (text.length > 10) {
      return 11.0; // Slightly larger for very long text like "Announcements"
    } else if (text.length > 8) {
      return 11.5; // Medium-large for "Submission"
    } else if (text.length > 5) {
      return 12.0; // Good size for "Search"
    } else {
      return 12.5; // Slightly larger for short text like "Home", "Chat"
    }
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    bool isSelected = widget.currentIndex == index;

    return GestureDetector(
      onTap: () => widget.onTabPressed(index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeInOutCubic,
            child: isSelected 
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedScale(
                      scale: 1.05,
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeInOutBack,
                      child: Icon(
                        icon,
                        size: 21,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: AnimatedOpacity(
                        opacity: 1.0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: _getFontSizeForText(label),
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                )
              : AnimatedScale(
                  scale: 1.0, // Normal size when not selected
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOutBack,
                  child: Icon(
                    icon,
                    size: 24, // Larger size for better visibility
                    color: const Color(0xFF9B9B9B),
                  ),
                ),
          ),
        ),
      ),
    );
  }
}
