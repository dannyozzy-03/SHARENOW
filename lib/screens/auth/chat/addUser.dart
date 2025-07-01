import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AddUserScreen extends StatefulWidget {
  final String groupId;

  const AddUserScreen({super.key, required this.groupId});

  @override
  State<AddUserScreen> createState() => _AddUserScreenState();
}

class _AddUserScreenState extends State<AddUserScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<DocumentSnapshot> _searchResults = [];
  Set<String> _groupMembers = {}; // Store group members
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchGroupMembers(); // Fetch group members when screen loads
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// **Fetch Group Members**
  void _fetchGroupMembers() async {
    try {
      DocumentSnapshot groupDoc = await FirebaseFirestore.instance
          .collection("groupChats")
          .doc(widget.groupId)
          .get();

      if (groupDoc.exists) {
        List<dynamic> members = groupDoc["members"] ?? [];
        setState(() {
          _groupMembers = members.cast<String>().toSet();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error fetching group members: $e")),
      );
    }
  }

  /// **Search Users by Name Using `searchKeywords`**
  void _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isLoading = true);

    try {
      QuerySnapshot usersSnapshot = await FirebaseFirestore.instance
          .collection("users")
          .where("searchKeywords", arrayContains: query.toLowerCase())
          .limit(10) // Limit results
          .get();

      setState(() {
        _searchResults = usersSnapshot.docs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error searching users: $e")),
      );
    }
  }

  /// **Add User to Group**
  void _addUser(String userId, String username) async {
    try {
      await FirebaseFirestore.instance
          .collection("groupChats")
          .doc(widget.groupId)
          .update({
        "members": FieldValue.arrayUnion([userId]),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$username added successfully!")),
      );

      _fetchGroupMembers(); // Refresh member list after adding
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error adding user: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add User to Group")),
      body: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [
            // Search Bar
            TextField(
              controller: _searchController,
              onChanged: _searchUsers,
              decoration: InputDecoration(
                labelText: "Search by Username",
                border: OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchResults = []);
                        },
                      )
                    : null,
              ),
            ),

            const SizedBox(height: 15),

            // Loading Indicator
            if (_isLoading) const Center(child: CircularProgressIndicator()),

            // Search Results
            Expanded(
              child: _searchResults.isEmpty
                  ? const Center(child: Text("No users found."))
                  : ListView.builder(
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        var userDoc = _searchResults[index];
                        String username = userDoc["name"] ?? "Unknown User";
                        String userId = userDoc.id;

                        bool isAlreadyInGroup = _groupMembers.contains(userId);

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blueAccent,
                            child: Text(
                              username.substring(0, 1).toUpperCase(),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(username),
                          trailing: isAlreadyInGroup
                              ? const Text(
                                  "Already in the group",
                                  style: TextStyle(color: Colors.grey),
                                )
                              : ElevatedButton(
                                  onPressed: () => _addUser(userId, username),
                                  child: const Text("Add"),
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
