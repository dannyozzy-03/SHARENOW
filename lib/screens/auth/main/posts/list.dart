import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:twitterr/models/comment.dart';
import 'package:twitterr/models/posts.dart';
import 'package:twitterr/models/user.dart';
import 'package:twitterr/screens/auth/main/posts/commentScreen.dart';
import 'package:twitterr/services/posts.dart';
import 'package:twitterr/services/user.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ListPosts extends StatefulWidget {
  ListPosts({super.key});

  @override
  _ListPostsState createState() => _ListPostsState();
}

class _ListPostsState extends State<ListPosts> with TickerProviderStateMixin {
  final UserService _userService = UserService();
  final PostService _postService = PostService();
  Map<String, bool> _isHovered = {};
  Map<String, AnimationController> _animationControllers = {};

  @override
  void dispose() {
    for (var controller in _animationControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  AnimationController _getAnimationController(String postId) {
    if (!_animationControllers.containsKey(postId)) {
      _animationControllers[postId] = AnimationController(
        duration: const Duration(milliseconds: 150),
        vsync: this,
      );
    }
    return _animationControllers[postId]!;
  }

  @override
  Widget build(BuildContext context) {
    final posts = Provider.of<List<PostModel>?>(context) ?? [];

    final String? searchedUserId =
        ModalRoute.of(context)?.settings.arguments as String?;
    final isProfilePage = searchedUserId != null &&
        posts.any((post) =>
            post.creator == searchedUserId ||
            post.originalCreator == searchedUserId);

    // Fix duplicate reposts in the profile page
    final seenPostIds = <String>{};
    final filteredPosts = isProfilePage
        ? posts.where((post) {
            final postId =
                post.isRepost ? post.originalPostId ?? post.id : post.id;
            final belongsToUser = post.creator == searchedUserId ||
                post.originalCreator == searchedUserId;
            if (!belongsToUser) return false;
            if (seenPostIds.contains(postId)) return false;
            seenPostIds.add(postId);
            return true;
          }).toList()
        : posts.where((post) => !post.isRepost).toList();

    if (filteredPosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.20),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.forum_rounded, size: 28, color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Text(
              'No posts yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A202C),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Share your first thought!',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF718096),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    final currentRoute = ModalRoute.of(context)?.settings.name;
    final isProfileScreen = searchedUserId != null || currentRoute == '/profile';

    return ListView.builder(
      padding: isProfileScreen 
          ? const EdgeInsets.only(top: 0) 
          : const EdgeInsets.only(top: 16),
      itemCount: filteredPosts.length,
      itemBuilder: (context, index) {
        final post = filteredPosts[index];
        final originalPostId = post.isRepost ? post.originalPostId ?? post.id : post.id;
        
        final customMargin = (isProfileScreen && index == 0)
            ? const EdgeInsets.only(top: 0, bottom: 12, left: 16, right: 16)
            : const EdgeInsets.symmetric(vertical: 6, horizontal: 16);
        
        return StreamBuilder<PostModel?>(
          stream: post.isRepost
              ? _postService.getPostById(originalPostId)
              : Stream.value(post),
          builder: (context, snapshotPost) {
            if (!snapshotPost.hasData) {
              return Container(
                margin: customMargin,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFBFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                    ),
                  ),
                ),
              );
            }

            final originalPost = snapshotPost.data!;
            return StreamBuilder<UserModel?>(
              stream: _userService.getUserInfo(originalPost.creator),
              builder: (BuildContext context, AsyncSnapshot<UserModel?> snapshotUser) {
                if (!snapshotUser.hasData) {
                  return Container(
                    margin: customMargin,
                    height: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFBFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFE2E8F0),
                        width: 1,
                      ),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                        ),
                      ),
                    ),
                  );
                }

                final user = snapshotUser.data;
                final currentUser = FirebaseAuth.instance.currentUser;

                return AnimatedBuilder(
                  animation: _getAnimationController(originalPost.id),
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 1.0 + (_getAnimationController(originalPost.id).value * 0.015),
                      child: GestureDetector(
                        onTapDown: (_) => _getAnimationController(originalPost.id).forward(),
                        onTapUp: (_) => _getAnimationController(originalPost.id).reverse(),
                        onTapCancel: () => _getAnimationController(originalPost.id).reverse(),
                        onTap: () {
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) =>
                                  CommentScreen(post: originalPost),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                return FadeTransition(opacity: animation, child: child);
                              },
                            ),
                          );
                        },
                        child: Container(
                          margin: customMargin,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEFEFF),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6366F1).withOpacity(0.03),
                                blurRadius: 25,
                                offset: const Offset(0, 5),
                              ),
                              BoxShadow(
                                color: Colors.black.withOpacity(0.015),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
                              width: 0.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (post.isRepost)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF6366F1),
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(16),
                                      topRight: Radius.circular(16),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.25),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Icon(
                                          Icons.repeat_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        "Reposted",
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // User Header
                                    Row(
                                      children: [
                                        Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF6366F1).withOpacity(0.12),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: CircleAvatar(
                                            radius: 18,
                                            backgroundColor: const Color(0xFF6366F1),
                                            backgroundImage: user?.profileImageUrl != null &&
                                                    user!.profileImageUrl.isNotEmpty
                                                ? NetworkImage(user.profileImageUrl)
                                                : null,
                                            child: user?.profileImageUrl == null ||
                                                    user!.profileImageUrl.isEmpty
                                                ? const Icon(
                                                    Icons.person_rounded,
                                                    color: Colors.white,
                                                    size: 18,
                                                  )
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                user?.name ?? 'Anonymous',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF1A202C),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                _formatTimestamp(originalPost.timestamp.toDate()),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF718096),
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (currentUser?.uid == originalPost.creator)
                                          GestureDetector(
                                            onTap: () => _showDeleteDialog(context, originalPost),
                                            child: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Colors.red.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Icon(
                                                Icons.delete_outline_rounded,
                                                color: Colors.red,
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    
                                    // Post Content
                                    if (originalPost.text.isNotEmpty)
                                      Text(
                                        originalPost.text,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          height: 1.4,
                                          color: Color(0xFF2D3748),
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    if (originalPost.text.isNotEmpty && originalPost.imageUrl != null)
                                      const SizedBox(height: 12),
                                    
                                    // Post Image
                                    if (originalPost.imageUrl != null)
                                      Container(
                                        width: double.infinity,
                                        constraints: const BoxConstraints(maxHeight: 300),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: const Color(0xFFE2E8F0),
                                            width: 1,
                                          ),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.network(
                                            originalPost.imageUrl!,
                                            fit: BoxFit.cover,
                                            loadingBuilder: (context, child, loadingProgress) {
                                              if (loadingProgress == null) return child;
                                              return Container(
                                                height: 200,
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF1F5F9),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: const Center(
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                                                  ),
                                                ),
                                              );
                                            },
                                            errorBuilder: (context, error, stackTrace) {
                                              return Container(
                                                height: 200,
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF1F5F9),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: const Center(
                                                  child: Icon(
                                                    Icons.broken_image_rounded,
                                                    color: Color(0xFF9CA3AF),
                                                    size: 48,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 16),
                                    
                                    // Action Bar
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                                        children: [
                                          // Like Button
                                          _buildActionButton(
                                            originalPost.id + '_like',
                                            StreamBuilder<bool>(
                                              stream: _postService.getCurrentUserLike(originalPost),
                                              builder: (context, snapshotLike) {
                                                bool isLiked = snapshotLike.data ?? false;
                                                return GestureDetector(
                                                  onTap: () => _postService.likePost(originalPost, isLiked),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                                        color: isLiked ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                                                        size: 18,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      StreamBuilder<int>(
                                                        stream: _postService.getPostLikeCount(originalPost),
                                                        builder: (context, snapshot) {
                                                          return Text(
                                                            '${snapshot.data ?? 0}',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.w600,
                                                              color: isLiked ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          
                                          // Comment Button
                                          _buildActionButton(
                                            originalPost.id + '_comment',
                                            GestureDetector(
                                              onTap: () {
                                                Navigator.push(
                                                  context,
                                                  PageRouteBuilder(
                                                    pageBuilder: (context, animation, secondaryAnimation) =>
                                                        CommentScreen(post: originalPost),
                                                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                                      return FadeTransition(opacity: animation, child: child);
                                                    },
                                                  ),
                                                );
                                              },
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.chat_bubble_outline_rounded,
                                                    color: Color(0xFF6366F1),
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  StreamBuilder<List<CommentModel>>(
                                                    stream: _postService.getPostComments(originalPost.id),
                                                    builder: (context, snapshot) {
                                                      return Text(
                                                        '${snapshot.data?.length ?? 0}',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600,
                                                          color: Color(0xFF6366F1),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          
                                          // Repost Button
                                          _buildActionButton(
                                            originalPost.id + '_repost',
                                            StreamBuilder<bool>(
                                              stream: _postService.getCurrentUserRepost(originalPost),
                                              builder: (context, snapshotRepost) {
                                                bool isReposted = snapshotRepost.data ?? false;
                                                return GestureDetector(
                                                  onTap: () => _postService.repostPost(originalPost),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.repeat_rounded,
                                                        color: isReposted ? const Color(0xFF059669) : const Color(0xFF475569),
                                                        size: 20,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      StreamBuilder<int>(
                                                        stream: _postService.getPostRepostCount(originalPost),
                                                        builder: (context, snapshot) {
                                                          return Text(
                                                            '${snapshot.data ?? 0}',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.w600,
                                                              color: isReposted ? const Color(0xFF059669) : const Color(0xFF475569),
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
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
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d';
    } else {
      return '${timestamp.day}/${timestamp.month}';
    }
  }

  Widget _buildActionButton(String key, Widget child) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered[key] = true),
      onExit: (_) => setState(() => _isHovered[key] = false),
      child: AnimatedScale(
        scale: _isHovered[key] == true ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: child,
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, PostModel post) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text(
            'Delete Post',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          content: const Text(
            'This action cannot be undone.',
            style: TextStyle(fontSize: 14, color: Color(0xFF718096)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w500),
              ),
            ),
            TextButton(
              onPressed: () async {
                await _postService.deletePost(post.id);
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(backgroundColor: Colors.red),
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        );
      },
    );
  }
}
