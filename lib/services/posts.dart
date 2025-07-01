import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:twitterr/models/comment.dart';
import 'package:twitterr/models/posts.dart';
import 'package:twitterr/services/user.dart';
import 'package:rxdart/rxdart.dart'; // Import this for merging streams

class PostService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Convert Firestore QuerySnapshot to List<PostModel>
  List<PostModel> _postListFromSnapshot(QuerySnapshot snapshot) {
    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return PostModel(
        id: doc.id,
        text: data['text'] ?? '',
        creator: data['creator'] ?? '',
        timestamp: data['timestamp'] ?? Timestamp.now(),
        originalPostId: data['originalPostId'],
        originalCreator: data['originalCreator'],
        isRepost: data['isRepost'] ?? false,
        imageUrl: data['imageUrl'],
      );
    }).toList();
  }

  Future savePost(String text, {String? imageUrl}) async {
    User? user = FirebaseAuth.instance.currentUser;
    await _db.collection("posts").add({
      'text': text,
      'creator': user?.uid,
      'timestamp': FieldValue.serverTimestamp(),
      'isRepost': false, // Default for new posts
      'originalPostId': null,
      'originalCreator': null,
      'imageUrl': imageUrl,
    });
  }

  Future deletePost(String postId) async {
    await _db.collection('posts').doc(postId).delete();
  }

  Future repostPost(PostModel post) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Check if the user already reposted this post
    QuerySnapshot reposts = await _db
        .collection("posts")
        .where('creator', isEqualTo: user.uid)
        .where('originalPostId', isEqualTo: post.id)
        .where('isRepost', isEqualTo: true)
        .get();

    if (reposts.docs.isNotEmpty) {
      // If already reposted, remove the repost
      await _db.collection("posts").doc(reposts.docs.first.id).delete();

      // Decrement repost count for the original post
      await _db.collection("posts").doc(post.id).update({
        'repostCount': FieldValue.increment(-1),
      });
    } else {
      // Fetch original creator if it's a reposted post
      String? originalCreator =
          post.isRepost ? post.originalCreator : post.creator;

      // Create a new repost
      await _db.collection("posts").add({
        'text': post.text,
        'creator': user.uid, // User who is reposting
        'timestamp': FieldValue.serverTimestamp(),
        'isRepost': true,
        'originalPostId': post.id, // Reference to the original post
        'originalCreator': originalCreator, // Store original creator
        'imageUrl': post.imageUrl, // Include image from original post
      });

      // Increment repost count for the original post
      await _db.collection("posts").doc(post.id).update({
        'repostCount': FieldValue.increment(1),
      });
    }
  }

  // Stream for real-time repost status for the current user
  Stream<bool> getCurrentUserRepost(PostModel post) {
    return _db
        .collection("posts")
        .where('creator', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
        .where('originalPostId', isEqualTo: post.id)
        .where('isRepost', isEqualTo: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.isNotEmpty);
  }

  // Stream to get repost count
  Stream<int> getPostRepostCount(PostModel post) {
    return _db
        .collection('posts')
        .where('originalPostId', isEqualTo: post.id)
        .where('isRepost', isEqualTo: true)
        .snapshots()
        .map((snapshot) => snapshot.size);
  }

  Future likePost(PostModel post, bool current) async {
    if (current) {
      await _db
          .collection("posts")
          .doc(post.id)
          .collection("likes")
          .doc(FirebaseAuth.instance.currentUser?.uid)
          .delete();
    } else {
      await _db
          .collection("posts")
          .doc(post.id)
          .collection("likes")
          .doc(FirebaseAuth.instance.currentUser?.uid)
          .set({});
    }
  }

  // Stream for like updates
  Stream<bool> getCurrentUserLike(PostModel post) {
    return _db
        .collection("posts")
        .doc(post.id)
        .collection("likes")
        .doc(FirebaseAuth.instance.currentUser?.uid)
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  // Stream to get like count
  Stream<int> getPostLikeCount(PostModel post) {
    return _db
        .collection('posts')
        .doc(post.id)
        .collection('likes')
        .snapshots()
        .map((snapshot) => snapshot.size);
  }

  // Stream to get posts by a specific user (original + reposts they made)
  Stream<List<PostModel>> getPostsByUser(String? uid) {
    if (uid == null) return Stream.value([]);

    final originalPostsStream = _db
        .collection("posts")
        .where("creator", isEqualTo: uid)
        .snapshots()
        .map(_postListFromSnapshot);

    final userRepostsStream = _db
        .collection("posts")
        .where("creator", isEqualTo: uid)
        .where("isRepost", isEqualTo: true)
        .snapshots()
        .map(_postListFromSnapshot);

    return Rx.combineLatest2<List<PostModel>, List<PostModel>, List<PostModel>>(
      originalPostsStream,
      userRepostsStream,
      (originalPosts, reposts) {
        final allPosts = [...originalPosts, ...reposts]
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return allPosts;
      },
    );
  }

  // Get posts for the feed
  Future<List<PostModel>> getFeed() async {
    List<String> usersFollowing = await UserService()
        .getUserFollowing(FirebaseAuth.instance.currentUser?.uid);

    QuerySnapshot querySnapshot = await _db
        .collection('posts')
        .where('creator', whereIn: usersFollowing)
        .orderBy('timestamp', descending: true)
        .get();

    return _postListFromSnapshot(querySnapshot);
  }

  // Get comments for a specific post
  Stream<List<CommentModel>> getPostComments(String postId) {
    return _db
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CommentModel.fromFirestore(doc.data(), doc.id))
            .toList());
  }

  // Add a new comment to a post
  Future<void> addComment(
      String postId, String text, String userId, String userName) async {
    final commentRef =
        _db.collection('posts').doc(postId).collection('comments').doc();

    CommentModel newComment = CommentModel(
      id: commentRef.id,
      postId: postId,
      userId: userId,
      userName: userName,
      text: text,
      timestamp: DateTime.now(),
    );

    await commentRef.set(newComment.toFirestore());
  }

  Stream<PostModel?> getPostById(String postId) {
    return FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .snapshots()
        .map((snapshot) => snapshot.exists ? PostModel.fromFirestore(snapshot) : null);
  }
}
