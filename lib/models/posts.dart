import 'package:cloud_firestore/cloud_firestore.dart';

class PostModel {
  final String id;
  final String text;
  final String creator;
  final Timestamp timestamp;
  final String? originalPostId; // ID of the original post (if it's a repost)
  final String? originalCreator; // Creator of the original post
  final bool isRepost; // Flag to check if it's a repost
  final int repostCount; // Count of reposts
  final String? imageUrl; // URL of the post image

  PostModel({
    required this.id,
    required this.text,
    required this.creator,
    required this.timestamp,
    this.originalPostId,
    this.originalCreator,
    this.isRepost = false,
    this.repostCount = 0, // Default to 0
    this.imageUrl,
  });

  // Convert Firestore document to PostModel
  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return PostModel(
      id: doc.id,
      text: data['text'] ?? '',
      creator: data['creator'] ?? '',
      timestamp: data['timestamp'] ?? Timestamp.now(),
      originalPostId: data['originalPostId'],
      originalCreator: data['originalCreator'],
      isRepost: data['isRepost'] ?? false,
      repostCount: data['repostCount'] ?? 0, // Default to 0 if not present
      imageUrl: data['imageUrl'],
    );
  }

  // Convert PostModel to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'text': text,
      'creator': creator,
      'timestamp': timestamp,
      'originalPostId': originalPostId,
      'originalCreator': originalCreator,
      'isRepost': isRepost,
      'repostCount': repostCount,
      'imageUrl': imageUrl,
    };
  }
}
