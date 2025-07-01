import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:twitterr/models/posts.dart';
import 'package:twitterr/models/user.dart';
import 'package:twitterr/services/user.dart';
import 'package:twitterr/services/posts.dart';
import 'package:twitterr/screens/auth/main/posts/list.dart'; // Import the ListPosts widget

// Define consistent colors
const Color kPrimaryColor = Color(0xFF4A90E2); // Modern blue
const Color kBackgroundColor = Color(0xFFF8F9FA); // Light gray background
const Color kSurfaceColor = Colors.white;
const Color kTextPrimaryColor = Color(0xFF2C3E50); // Dark blue-gray
const Color kTextSecondaryColor = Color(0xFF95A5A6); // Muted gray
const Color kAccentColor = Color(0xFF1ABC9C); // Teal accent
const Color kDividerColor = Color(0xFFECEEF1);

class Profile extends StatefulWidget {
  final String? id;
  const Profile({super.key, this.id});

  @override
  _ProfileState createState() => _ProfileState();
}

class _ProfileState extends State<Profile> {
  final PostService _postService = PostService();
  final UserService _userService = UserService();
  final ScrollController _scrollController = ScrollController();
  bool _showShadow = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.offset > 0 && !_showShadow) {
        setState(() => _showShadow = true);
      } else if (_scrollController.offset <= 0 && _showShadow) {
        setState(() => _showShadow = false);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get ID either from widget.id or from route arguments
    final String uid = widget.id ?? ModalRoute.of(context)!.settings.arguments as String;
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return MultiProvider(
      providers: [
        StreamProvider<UserModel?>.value(
          value: _userService.getUserInfo(uid),
          initialData: null,
        ),
        StreamProvider<List<PostModel>?>.value(
          value: _postService.getPostsByUser(uid),
          initialData: [],
        ),
        StreamProvider<bool?>.value(
          value: _userService.isFollowing(currentUserId ?? '', uid),
          initialData: null,
        ),
      ],
      child: Scaffold(
        backgroundColor: kBackgroundColor,
        body: Stack(
          children: [
            _buildProfileContent(uid, currentUserId),
            Positioned(
              top: 40,
              left: 20,
              child: _buildBackButton(), // Circular Back Button
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileContent(String uid, String? currentUserId) {
    return Consumer<UserModel?>(builder: (context, user, _) {
      return NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, _) {
          return [
            SliverAppBar(
              floating: false,
              pinned: true,
              expandedHeight: 200,
              elevation: _showShadow ? 4 : 0,
              backgroundColor: kSurfaceColor,
              automaticallyImplyLeading: false,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Banner Image with Gradient Overlay
                    Positioned.fill(
                      child: ShaderMask(
                        shaderCallback: (rect) {
                          return LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.5)
                            ],
                          ).createShader(rect);
                        },
                        blendMode: BlendMode.overlay,
                        child: user != null && user.bannerImageUrl.isNotEmpty
                            ? Image.network(
                                user.bannerImageUrl,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      kPrimaryColor.withOpacity(0.7),
                                      kPrimaryColor
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    ),

                    // Profile Picture - Add this positioned element to the banner's Stack
                    Positioned(
                      left: 20,
                      bottom: 10, // Extends below the banner
                      child: Container(
                        
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: kSurfaceColor,
                          child: CircleAvatar(
                            radius: 47,
                            backgroundColor: kPrimaryColor.withOpacity(0.2),
                            child: user != null && user.profileImageUrl.isNotEmpty
                                ? CircleAvatar(
                                    radius: 44,
                                    backgroundImage: NetworkImage(user.profileImageUrl),
                                  )
                                : const Icon(Icons.person, size: 50, color: kPrimaryColor),
                          ),
                        ),
                      ),
                    ),

                    // Action Buttons
                    Positioned(
                      bottom: 20,
                      right: 20,
                      child: Row(
                        children: [
                          if (currentUserId == uid)
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pushNamed(context, '/edit');
                              },
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text("Edit Profile"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kSurfaceColor,
                                foregroundColor: kPrimaryColor,
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                            )
                          else
                            Row(
                              children: [
                                // Chat Button (Left)
                                Container(
                                  decoration: BoxDecoration(
                                    color: kSurfaceColor,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.message_rounded),
                                    color: kPrimaryColor,
                                    onPressed: () {
                                      Navigator.pushNamed(context, '/chat',
                                          arguments: uid);
                                    },
                                  ),
                                ),

                                const SizedBox(width: 12),

                                // Follow/Unfollow Button
                                Consumer<bool?>(
                                  builder: (context, isFollowing, _) {
                                    if (isFollowing == null)
                                      return const SizedBox();
                                    return ElevatedButton.icon(
                                      onPressed: () {
                                        if (isFollowing) {
                                          _userService.unfollowUser(uid);
                                        } else {
                                          _userService.followUser(uid);
                                        }
                                      },
                                      icon: Icon(
                                        isFollowing
                                            ? Icons.person_remove
                                            : Icons.person_add,
                                        size: 16,
                                      ),
                                      label: Text(
                                        isFollowing ? 'Unfollow' : 'Follow',
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isFollowing
                                            ? kSurfaceColor
                                            : kPrimaryColor,
                                        foregroundColor: isFollowing
                                            ? kTextPrimaryColor
                                            : kSurfaceColor,
                                        elevation: 2,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(20),
                                          side: isFollowing
                                              ? BorderSide(color: kTextSecondaryColor)
                                              : BorderSide.none,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                      ),
                                    );
                                  },
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

            // User Info Box with Profile Picture
            SliverToBoxAdapter(
              child: Container(
                color: kSurfaceColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Add padding at the top to accommodate the profile picture that extends from banner
                    const SizedBox(height: 5),
                    
                    // User info below profile picture
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 5, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Display Name
                          if (user?.name != null)
                            Text(
                              user!.name!,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: kTextPrimaryColor,
                              ),
                            ),

                          const SizedBox(height: 8),

                          // Display Role
                          if (user?.role != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: kPrimaryColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                user!.role!.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: kPrimaryColor,
                                ),
                              ),
                            ),

                          const SizedBox(height: 16),

                          // Info row with icons
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: kBackgroundColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                // Display Email
                                if (user?.email != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12, 
                                      vertical: 8
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.email_outlined,
                                            color: kPrimaryColor, size: 20),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            user!.email!,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: kTextPrimaryColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                // Phone number
                                if (user?.phoneNumber != null && user!.phoneNumber!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12, 
                                      vertical: 8
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.phone_outlined,
                                            color: kPrimaryColor, size: 20),
                                        const SizedBox(width: 12),
                                        Text(
                                          user.phoneNumber!,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: kTextPrimaryColor,
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
                  ],
                ),
              ),
            ),

            // Posts Header
            SliverPersistentHeader(
              delegate: _SliverAppBarDelegate(
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: kSurfaceColor,
                    border: Border(
                      bottom: BorderSide(
                        color: kDividerColor,
                        width: 1,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.article_outlined, color: kPrimaryColor, size: 20),
                      SizedBox(width: 8),
                      Text(
                        "Posts",
                        style: TextStyle(
                          color: kTextPrimaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              pinned: true,
            ),
          ];
        },
        body: Consumer<List<PostModel>?>(builder: (context, posts, _) {
          if (posts == null || posts.isEmpty) {
            return _buildEmptyState("No posts yet", Icons.article_outlined);
          }
          return ListPosts();
        }),
      );
    });
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 70,
            color: kTextSecondaryColor.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 18,
              color: kTextSecondaryColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(context),
        customBorder: const CircleBorder(),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kSurfaceColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.arrow_back, color: kPrimaryColor, size: 24),
        ),
      ),
    );
  }
}

// Helper class for SliverPersistentHeader
class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget _widget;

  _SliverAppBarDelegate(this._widget);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return _widget;
  }

  @override
  double get maxExtent => 48.0;

  @override
  double get minExtent => 48.0;

  @override
  bool shouldRebuild(covariant _SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
