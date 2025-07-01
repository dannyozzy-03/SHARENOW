import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'personalChat.dart';

class NewChatPage extends StatelessWidget {
  const NewChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Start New Chat")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var users = snapshot.data!.docs;

          if (users.isEmpty) {
            return const Center(child: Text("No users available."));
          }

          // Safely access 'name' field and sort
          users.sort((a, b) {
            String nameA = (a.data() as Map<String, dynamic>)['name']?.toString() ?? '';
            String nameB = (b.data() as Map<String, dynamic>)['name']?.toString() ?? '';
            return nameA.compareTo(nameB);
          });

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              var userData = users[index].data() as Map<String, dynamic>;
              String userId = users[index].id;
              String userName = userData['name']?.toString() ?? 'Unknown User';

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blueGrey[100],
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: Colors.blueGrey[800],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(userName),
                onTap: () => _startChat(context, userId),
              );
            },
          );
        },
      ),
    );
  }

  void _startChat(BuildContext context, String receiverId) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => PersonalChat(receiverId: receiverId)),
    );
  }
}
