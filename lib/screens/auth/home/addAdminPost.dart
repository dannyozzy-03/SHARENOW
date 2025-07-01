import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:twitterr/helper/image_helper.dart';

class Category {
  final String name;
  final IconData icon;
  final Color color;

  Category({required this.name, required this.icon, required this.color});
}

class PostPage extends StatefulWidget {
  @override
  _PostPageState createState() => _PostPageState();
}

class _PostPageState extends State<PostPage> {
  final TextEditingController _postController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  File? _selectedImage;
  bool _isUploading = false;

  // Update the categories list
  final List<Category> categories = [
    Category(name: "General", icon: Icons.announcement, color: Colors.teal),
    Category(name: "Academic", icon: Icons.school, color: Colors.blue),
    Category(name: "Event", icon: Icons.event, color: Colors.orange),
    Category(name: "Important", icon: Icons.warning, color: Colors.red),
    Category(name: "Sports", icon: Icons.sports, color: Colors.green),
  ];

  // Add selected category
  Category? _selectedCategory;

  // Select image
  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  // Upload post with text and optional image
  void _submitPost() async {
    if (_isUploading) return;

    User? user = _auth.currentUser;
    if (user == null || user.email == null) return;

    String email = user.email!;
    bool isAdmin = email.endsWith("@admin.uitm.edu.my");

    if (_postController.text.isNotEmpty && isAdmin) {
      setState(() => _isUploading = true);
      String message = _postController.text;
      String? imageUrl;

      // If an image is selected, upload it first
      if (_selectedImage != null) {
        imageUrl = await ImageHelper.uploadImageToFirebase(_selectedImage!);
      }

      final uri = Uri.parse("http://192.168.0.31:4000/admin/post");
      final response = await http.post(
        uri,
        body: jsonEncode({
          "text": message,
          "adminEmail": email,
          "imageUrl": imageUrl,
          "category": _selectedCategory?.name ?? "General", // Include category
        }),
        headers: {"Content-Type": "application/json"},
      );

      setState(() => _isUploading = false);

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Post added successfully')),
        );
        Navigator.pop(context, true);
      } else {
        print("Failed to send post: ${response.body}");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Create Post")),
      resizeToAvoidBottomInset: true, // Add this line
      body: SingleChildScrollView(    // Wrap with SingleChildScrollView
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Category Selection
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Select Category",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: categories.map((category) {
                        bool isSelected = _selectedCategory?.name == category.name;
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedCategory = category;
                            });
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? category.color.withOpacity(0.2)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? category.color
                                    : Colors.grey.shade400,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  category.icon,
                                  size: 16,
                                  color: isSelected
                                      ? category.color
                                      : Colors.grey.shade700,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  category.name,
                                  style: TextStyle(
                                    color: isSelected
                                        ? category.color
                                        : Colors.grey.shade700,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              // Existing widgets...
              TextField(
                controller: _postController,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: "Enter your post...",
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              if (_selectedImage != null)
                Image.file(_selectedImage!, height: 150)
              else
                Text("No image selected"),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: Icon(Icons.image),
                    label: Text("Pick Image"),
                  ),
                  ElevatedButton(
                    onPressed: _isUploading ? null : _submitPost,
                    child: _isUploading
                        ? CircularProgressIndicator()
                        : Text("Post"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
