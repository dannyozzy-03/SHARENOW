import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:twitterr/models/comment.dart';
import 'package:twitterr/models/posts.dart';
import 'package:twitterr/models/user.dart';
import 'package:twitterr/services/posts.dart';
import 'package:twitterr/services/user.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CommentScreen extends StatefulWidget {
  final PostModel post;
  CommentScreen({required this.post, Key? key}) : super(key: key);

  @override
  _CommentScreenState createState() => _CommentScreenState();
}

class _CommentScreenState extends State<CommentScreen> with TickerProviderStateMixin {
  final UserService _userService = UserService();
  final PostService _postService = PostService();
  final TextEditingController _commentTextController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  
  bool _isAnonymous = false;
  bool _isLoading = false;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
    );
    
    _fadeController.forward();
    _slideController.forward();
    _scaleController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
    _commentTextController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}';
    }
  }

  Future<void> _addComment() async {
    if (_commentTextController.text.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      try {
        String username = _isAnonymous
            ? 'Anonymous'
            : currentUser.displayName ?? 'User';
        String userId = _isAnonymous ? 'anonymous' : currentUser.uid;

        await _postService.addComment(
          widget.post.id,
          _commentTextController.text.trim(),
          userId,
          username,
        );
        
        _commentTextController.clear();
        _focusNode.unfocus();
        
        // Scroll to bottom to show new comment
        Future.delayed(const Duration(milliseconds: 300), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Comment added successfully!'),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add comment: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('You need to log in to comment.'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Color(0xFF1A202C)),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Text(
            'Comments',
            style: TextStyle(
              color: Color(0xFF1A202C),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        centerTitle: true,
      ),
            body: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Stack(
        children: [
                    // Main content with padding for floating input
                    CustomScrollView(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        // Top spacing for AppBar
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 100),
                        ),
                        
                        // Original Post
                        SliverToBoxAdapter(
                          child: Container(
                            margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF6366F1),
                                  Color(0xFF8B5CF6),
                                  Color(0xFFA855F7),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6366F1).withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: StreamBuilder<UserModel?>(
            stream: _userService.getUserInfo(widget.post.creator),
            builder: (context, snapshot) {
              final user = snapshot.data;
              return Container(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white.withOpacity(0.3),
                                                width: 2,
                                              ),
                  boxShadow: [
                    BoxShadow(
                                                  color: Colors.black.withOpacity(0.2),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                    ),
                  ],
                ),
                                            child: CircleAvatar(
                                              radius: 22,
                                              backgroundColor: Colors.white,
                                              backgroundImage: user?.profileImageUrl != null &&
                            user!.profileImageUrl.isNotEmpty
                                                  ? NetworkImage(user.profileImageUrl) as ImageProvider
                                                  : const AssetImage('assets/images/default.png'),
                                              child: null,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.name ?? 'User',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                Text(
                                                  _formatTimestamp(widget.post.timestamp.toDate()),
                                                  style: TextStyle(
                                                    color: Colors.white.withOpacity(0.8),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                        ],
                      ),
                    ),
                  ],
                                      ),
                                      const SizedBox(height: 16),
                                      if (widget.post.text.isNotEmpty)
                                        Text(
                                          widget.post.text,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            height: 1.5,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      if (widget.post.text.isNotEmpty && widget.post.imageUrl != null)
                                        const SizedBox(height: 12),
                                      if (widget.post.imageUrl != null)
                                        GestureDetector(
                                          onTap: () {
                                            showDialog(
                                              context: context,
                                              barrierColor: Colors.black87,
                                              builder: (context) => Dialog(
                                                backgroundColor: Colors.transparent,
                                                insetPadding: EdgeInsets.zero,
                                                child: Stack(
                                                  children: [
                                                    Center(
                                                      child: InteractiveViewer(
                                                        child: Image.network(
                                                          widget.post.imageUrl!,
                                                          fit: BoxFit.contain,
                                                        ),
                                                      ),
                                                    ),
                                                    Positioned(
                                                      top: 40,
                                                      right: 20,
                                                      child: GestureDetector(
                                                        onTap: () => Navigator.pop(context),
                                                        child: Container(
                                                          width: 40,
                                                          height: 40,
                                                          decoration: BoxDecoration(
                                                            color: Colors.black.withOpacity(0.7),
                                                            shape: BoxShape.circle,
                                                          ),
                                                          child: const Icon(
                                                            Icons.close_rounded,
                                                            color: Colors.white,
                                                            size: 24,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                ),
              );
            },
                                          child: Container(
                                            width: double.infinity,
                                            constraints: const BoxConstraints(
                                              maxHeight: 400,
                                              minHeight: 150,
                                            ),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.2),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Stack(
                                              children: [
                                                ClipRRect(
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: Image.network(
                                                    widget.post.imageUrl!,
                                                    width: double.infinity,
                                                    fit: BoxFit.contain,
                                                    loadingBuilder: (context, child, loadingProgress) {
                                                      if (loadingProgress == null) return child;
                                                      return Container(
                                                        height: 200,
                                                        decoration: BoxDecoration(
                                                          color: Colors.white.withOpacity(0.1),
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: const Center(
                                                          child: CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                    errorBuilder: (context, error, stackTrace) {
                                                      return Container(
                                                        height: 200,
                                                        decoration: BoxDecoration(
                                                          color: Colors.white.withOpacity(0.1),
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: const Center(
                                                          child: Icon(
                                                            Icons.broken_image_rounded,
                                                            color: Colors.white,
                                                            size: 48,
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                                Positioned(
                                                  top: 8,
                                                  right: 8,
                                                  child: Container(
                                                    padding: const EdgeInsets.all(6),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black.withOpacity(0.6),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: const Icon(
                                                      Icons.zoom_in_rounded,
                                                      color: Colors.white,
                                                      size: 16,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                );
              },
            ),
          ),
                        ),

                        // Comments Header
                        SliverToBoxAdapter(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(20),
                                topRight: Radius.circular(20),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x0F6366F1),
                                  blurRadius: 10,
                                  offset: Offset(0, -2),
                                ),
                              ],
                            ),
            child: Row(
              children: [
                                const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: Color(0xFF6366F1),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                StreamBuilder<List<CommentModel>>(
                                  stream: _postService.getPostComments(widget.post.id),
                                  builder: (context, snapshot) {
                                    final comments = snapshot.data ?? [];
                                    return Text(
                                      '${comments.length} ${comments.length == 1 ? 'Comment' : 'Comments'}',
                                      style: const TextStyle(
                                        color: Color(0xFF6366F1),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Comments List
                        StreamBuilder<List<CommentModel>>(
                          stream: _postService.getPostComments(widget.post.id),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const SliverToBoxAdapter(
                                child: SizedBox(
                                  height: 200,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                                    ),
                                  ),
                                ),
                              );
                            }

                            final comments = snapshot.data ?? [];

                            if (comments.isEmpty) {
                              return SliverToBoxAdapter(
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 16),
                                  padding: const EdgeInsets.all(40),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.only(
                                      bottomLeft: Radius.circular(20),
                                      bottomRight: Radius.circular(20),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF6366F1).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: const Icon(
                                          Icons.chat_bubble_outline_rounded,
                                          size: 28,
                                          color: Color(0xFF6366F1),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'No comments yet',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1A202C),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Be the first to comment!',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFF718096),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            return SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final comment = comments[index];
                                  final isLast = index == comments.length - 1;
                                  return Container(
                                    margin: EdgeInsets.only(
                                      left: 16,
                                      right: 16,
                                      bottom: isLast ? 0 : 0,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: isLast 
                                          ? const BorderRadius.only(
                                              bottomLeft: Radius.circular(20),
                                              bottomRight: Radius.circular(20),
                                            )
                                          : BorderRadius.zero,
                                    ),
                                    child: _buildCommentItem(comment, index),
                                  );
                                },
                                childCount: comments.length,
                              ),
                            );
                          },
                        ),

                        // Bottom spacing for floating input
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 120),
                        ),
                      ],
                    ),

                    // Floating Comment Input
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              const Color(0xFFFAFBFC).withOpacity(0.0),
                              const Color(0xFFFAFBFC).withOpacity(0.8),
                              const Color(0xFFFAFBFC),
                            ],
                          ),
                        ),
                        child: Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6366F1).withOpacity(0.15),
                                blurRadius: 25,
                                offset: const Offset(0, -5),
                                spreadRadius: 0,
                              ),
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                            border: Border.all(
                              color: const Color(0xFF6366F1).withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: const Color(0xFFE2E8F0),
                                          width: 1,
                                        ),
                                      ),
                                      child: TextField(
                                        controller: _commentTextController,
                                        focusNode: _focusNode,
                                        maxLines: null,
                                        decoration: const InputDecoration(
                                          hintText: 'Write a reply...',
                                          hintStyle: TextStyle(
                                            color: Color(0xFF9CA3AF),
                                            fontSize: 14,
                                          ),
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                        ),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFF1A202C),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  GestureDetector(
                                    onTap: _isLoading ? null : _addComment,
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: _isLoading 
                                              ? [const Color(0xFF9CA3AF), const Color(0xFF6B7280)]
                                              : [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: (_isLoading ? const Color(0xFF9CA3AF) : const Color(0xFF6366F1)).withOpacity(0.4),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: _isLoading
                                          ? const Center(
                                              child: SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                ),
                                              ),
                                            )
                                          : const Icon(
                                              Icons.send_rounded,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _isAnonymous = !_isAnonymous;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _isAnonymous 
                                            ? const Color(0xFF6366F1).withOpacity(0.1)
                                            : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: _isAnonymous 
                                              ? const Color(0xFF6366F1)
                                              : const Color(0xFFE2E8F0),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _isAnonymous 
                                                ? Icons.check_circle_rounded
                                                : Icons.circle_outlined,
                                            color: _isAnonymous 
                                                ? const Color(0xFF6366F1)
                                                : const Color(0xFF9CA3AF),
                                            size: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Reply anonymously',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: _isAnonymous 
                                                  ? const Color(0xFF6366F1)
                                                  : const Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildCommentItem(CommentModel comment, int index) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 200 + (index * 50)),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFBFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFE2E8F0),
                  width: 0.5,
                ),
              ),
              child: StreamBuilder<UserModel?>(
                stream: comment.userId != 'anonymous'
                    ? _userService.getUserInfo(comment.userId)
                    : Stream.value(null),
                builder: (context, snapshotUser) {
                  final user = snapshotUser.data;
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6366F1).withOpacity(0.1),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                                                     child: CircleAvatar(
                             radius: 18,
                             backgroundColor: const Color(0xFF6366F1),
                             backgroundImage: comment.userId == 'anonymous'
                                 ? const AssetImage('assets/images/default.png')
                                 : (user?.profileImageUrl != null && user!.profileImageUrl.isNotEmpty
                                     ? NetworkImage(user.profileImageUrl) as ImageProvider
                                     : const AssetImage('assets/images/default.png')),
                             child: null,
                           ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                                             Row(
                                 children: [
                                   Flexible(
                                     child: Text(
                                       comment.userId == 'anonymous'
                                           ? 'Anonymous'
                                           : user?.name ?? 'User',
                                       style: const TextStyle(
                                         fontSize: 14,
                                         fontWeight: FontWeight.w600,
                                         color: Color(0xFF1A202C),
                                       ),
                                       overflow: TextOverflow.ellipsis,
                                       maxLines: 1,
                                     ),
                                   ),
                                   const SizedBox(width: 8),
                                   Text(
                                     _formatTimestamp(comment.timestamp),
                                     style: const TextStyle(
                                       fontSize: 12,
                                       color: Color(0xFF9CA3AF),
                                       fontWeight: FontWeight.w400,
                                     ),
                                   ),
                                 ],
                               ),
                              const SizedBox(height: 6),
                              Text(
                                comment.text,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: Color(0xFF374151),
                                ),
                              ),
              ],
            ),
          ),
        ],
      ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
