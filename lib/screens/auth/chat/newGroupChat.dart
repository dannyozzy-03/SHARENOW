import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GroupCreationScreen extends StatefulWidget {
  const GroupCreationScreen({super.key});

  @override
  _GroupCreationScreenState createState() => _GroupCreationScreenState();
}

class _GroupCreationScreenState extends State<GroupCreationScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final Set<String> _selectedUserIds = {};
  WebSocketChannel? _channel;
  bool _isLoading = false;
  String? _searchQuery;
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    try {
      _channel = WebSocketChannel.connect(
          Uri.parse("ws://localhost:3000?user=$currentUserId"));
    } catch (e) {
      print("WebSocket connection error: $e");
    }
  }

  void _createGroup() async {
    // Validate inputs
    if (_groupNameController.text.trim().isEmpty) {
      _showErrorSnackBar("Please enter a group name");
      return;
    }

    if (_selectedUserIds.isEmpty) {
      _showErrorSnackBar("Please select at least one member");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Ensure the creator is in the group
      final Set<String> allMembers = {..._selectedUserIds};
      if (currentUserId != null) {
        allMembers.add(currentUserId!);
      }

      // Create group in Firestore
      DocumentReference groupRef =
          await FirebaseFirestore.instance.collection("groupChats").add({
        "groupName": _groupNameController.text.trim(),
        "description": _descriptionController.text.trim(),
        "members": allMembers.toList(),
        "createdBy": currentUserId,
        "createdAt": FieldValue.serverTimestamp(),
        "lastMessage": "Group created",
        "lastMessageSender": "system",
        "lastTimestamp": FieldValue.serverTimestamp(),
        "pinnedMessageId": null,
        "deadlines": {}, // Initialize deadlines as an empty map
      });

      // Send the first system message
      await groupRef.collection("messages").add({
        "text": "Welcome to ${_groupNameController.text.trim()}!",
        "senderId": "system",
        "timestamp": FieldValue.serverTimestamp(),
      });

      // Notify WebSocket server if connection is available
      if (_channel != null) {
        try {
          final groupData = {
            "type": "createGroup",
            "groupId": groupRef.id,
            "groupName": _groupNameController.text.trim(),
            "members": allMembers.toList(),
          };

          _channel!.sink.add(jsonEncode(groupData));
        } catch (e) {
          print("WebSocket send error: $e");
          // Continue even if WebSocket fails
        }
      }

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Group created successfully!"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(12),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      print("Error creating group: $e");
      if (mounted) {
        _showErrorSnackBar("Failed to create group: ${e.toString()}");
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _descriptionController.dispose();
    if (_channel != null) {
      _channel!.sink.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Create New Group"),
        centerTitle: true,
        backgroundColor: Colors.deepPurpleAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.deepPurpleAccent,
              ),
            )
          : Column(
              children: [
                _buildGroupInfoSection(),
                _buildSearchBar(),
                _buildMembersSection(),
                _buildCreateButton(),
              ],
            ),
    );
  }

  Widget _buildGroupInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group icon/avatar at the top
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.deepPurpleAccent.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.group,
                size: 40,
                color: Colors.deepPurpleAccent,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Group name field
          TextField(
            controller: _groupNameController,
            decoration: InputDecoration(
              labelText: "Group Name",
              hintText: "Enter group name",
              prefixIcon:
                  const Icon(Icons.edit, color: Colors.deepPurpleAccent),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.deepPurpleAccent),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          const SizedBox(height: 16),

          // Group description field
          TextField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: "Group Description (Optional)",
              hintText: "Enter group description",
              prefixIcon:
                  const Icon(Icons.description, color: Colors.deepPurpleAccent),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.deepPurpleAccent),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Colors.grey.shade100,
      child: TextField(
        onChanged: (value) {
          setState(() {
            _searchQuery = value.isNotEmpty ? value.toLowerCase() : null;
          });
        },
        decoration: InputDecoration(
          hintText: "Search users",
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: IconButton(
            icon: const Icon(Icons.clear, color: Colors.grey),
            onPressed: () {
              setState(() {
                _searchQuery = null;
              });
            },
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  Widget _buildMembersSection() {
    return Expanded(
      child: Container(
        color: Colors.grey.shade100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 8, bottom: 8),
              child: Row(
                children: [
                  const Text(
                    "Select Members",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurpleAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.deepPurpleAccent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${_selectedUserIds.length} selected",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder(
                // Explicitly get all users without limits
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .orderBy('name') // Sort by name for better UX
                    .snapshots(),
                builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Colors.deepPurpleAccent,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        "Error loading users: ${snapshot.error}",
                        style: TextStyle(
                          color: Colors.red.shade700,
                        ),
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Text(
                        "No users available",
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    );
                  }

                  var allUsers = snapshot.data!.docs;

                  // Filter out current user and apply search filter if needed
                  var filteredUsers = allUsers.where((user) {
                    // Skip current user
                    if (user.id == currentUserId) return false;

                    // Apply search filter if active
                    if (_searchQuery != null && _searchQuery!.isNotEmpty) {
                      String userName = user['name'].toString().toLowerCase();
                      return userName.contains(_searchQuery!.toLowerCase());
                    }

                    return true;
                  }).toList();

                  if (filteredUsers.isEmpty) {
                    return Center(
                      child: Text(
                        _searchQuery != null && _searchQuery!.isNotEmpty
                            ? "No users found matching '$_searchQuery'"
                            : "No users available",
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: filteredUsers.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: Colors.grey.shade300,
                      indent: 70,
                    ),
                    itemBuilder: (context, index) {
                      var user = filteredUsers[index];
                      String userId = user.id;
                      String userName = user['name'] ?? 'Unknown';
                      bool isSelected = _selectedUserIds.contains(userId);

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? Colors.deepPurpleAccent
                              : Colors.grey.shade400,
                          child: Text(
                            userName.isNotEmpty
                                ? userName[0].toUpperCase()
                                : "?",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          userName,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: Checkbox(
                          value: isSelected,
                          activeColor: Colors.deepPurpleAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                _selectedUserIds.add(userId);
                              } else {
                                _selectedUserIds.remove(userId);
                              }
                            });
                          },
                        ),
                        onTap: () {
                          setState(() {
                            if (_selectedUserIds.contains(userId)) {
                              _selectedUserIds.remove(userId);
                            } else {
                              _selectedUserIds.add(userId);
                            }
                          });
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: ElevatedButton(
        onPressed: _createGroup,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurpleAccent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: const Text(
          "CREATE GROUP",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
