import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:twitterr/screens/auth/home/addAdminPost.dart';

class ListSearchPosts extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "All Announcements",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        backgroundColor: Color(0xFF64B5F6), // Light Ocean Blue
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('admin_posts')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.purple),
              ),
            );
          }
          
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.campaign_outlined,
                    size: 70,
                    color: Colors.purple.shade300,
                  ),
                  SizedBox(height: 16),
                  Text(
                    "No announcements yet",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }

          var posts = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              var post = posts[index].data() as Map<String, dynamic>;
              var timestamp = post['timestamp'] as Timestamp?;
              var date = timestamp?.toDate() ?? DateTime.now();
              var formattedTime = timeago.format(date);
              var category = post['category'] ?? "General";
              
              // Extract color and icon from the post data, or use defaults
              Color categoryColor;
              IconData categoryIcon;
              
              try {
                categoryColor = Color(post['categoryColor'] as int? ?? 0xFF9C27B0);
                categoryIcon = IconData(
                  post['categoryIcon'] as int? ?? 0xE24D, 
                  fontFamily: 'MaterialIcons'
                );
              } catch (e) {
                categoryColor = Colors.purple;
                categoryIcon = Icons.campaign;
              }
              
              Color getCategoryColor(String category) {
                switch (category.toLowerCase()) {
                  case 'general':
                    return Color(0xFFB39DDB); // Light Purple
                  case 'academic':
                    return Color(0xFF9575CD); // Medium Purple
                  case 'events':
                    return Color(0xFFA094D8); // Soft Purple
                  case 'sports':
                    return Color(0xFF7E57C2); // Deep Purple
                  case 'important':
                    return Color(0xFF673AB7); // Rich Purple
                  default:
                    return Color(0xFFB39DDB); // Light Purple
                }
              }
              
              // Then use it in your card:
              categoryColor = getCategoryColor(category);
              
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                margin: const EdgeInsets.only(bottom: 16),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: categoryColor,
                        width: 5,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category badge
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: categoryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: categoryColor.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    categoryIcon,
                                    size: 14,
                                    color: categoryColor,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    category,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: categoryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Spacer(),
                            Text(
                              formattedTime,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Header
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.purple.shade100,
                              child: Icon(
                                Icons.school_rounded,
                                color: Colors.purple.shade800,
                                size: 18,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    post['email'] ?? "UiTM Official",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (timestamp != null)
                                    Text(
                                      DateFormat('MMM d, yyyy • h:mm a').format(date),
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.verified,
                              color: Colors.purple.shade600,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                      
                      // Title
                      if (post['title'] != null)
                        Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text(
                            post['title'],
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey[900],
                            ),
                          ),
                        ),
                      
                      // Message
                      Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Text(
                          post['text'] ?? "",
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.4,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                      
                      // Image
                      if (post['imageUrl'] != null && post['imageUrl'].toString().isNotEmpty)
                        Container(
                          width: double.infinity,
                          height: 200,
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: Colors.grey[200]!,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Image.network(
                            post['imageUrl'],
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          (loadingProgress.expectedTotalBytes ?? 1)
                                      : null,
                                  valueColor: AlwaysStoppedAnimation<Color>(categoryColor),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) => Center(
                              child: Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 40,
                              ),
                            ),
                          ),
                        ),
                      
                      // Action buttons
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          border: Border(
                            top: BorderSide(
                              color: Colors.grey[200]!,
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            TextButton.icon(
                              onPressed: () {},
                              icon: Icon(Icons.bookmark_border, size: 18, color: categoryColor),
                              label: Text(
                                "Save",
                                style: TextStyle(
                                  color: categoryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 24,
                              color: Colors.grey[300],
                            ),
                            TextButton.icon(
                              onPressed: () {},
                              icon: Icon(Icons.share_outlined, size: 18, color: categoryColor),
                              label: Text(
                                "Share",
                                style: TextStyle(
                                  color: categoryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
