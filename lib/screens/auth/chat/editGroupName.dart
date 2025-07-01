import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditGroupNameScreen extends StatefulWidget {
  final String groupId;
  final String initialName;

  const EditGroupNameScreen({
    Key? key,
    required this.groupId,
    required this.initialName,
  }) : super(key: key);

  @override
  State<EditGroupNameScreen> createState() => _EditGroupNameScreenState();
}

class _EditGroupNameScreenState extends State<EditGroupNameScreen> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _saveName() async {
    await FirebaseFirestore.instance
        .collection("groupChats")
        .doc(widget.groupId)
        .update({
      "groupName": _nameController.text,
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Group name updated"),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF4E8BF0),
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Edit Group Name"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.blueGrey[800],
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Group Name",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.blueGrey[600],
              ),
            ),
            SizedBox(height: 8),
            TextField(
              controller: _nameController,
              style: TextStyle(
                fontSize: 18,
                color: Colors.blueGrey[800],
              ),
              decoration: InputDecoration(
                hintText: "Enter group name",
                filled: true,
                fillColor: Colors.blueGrey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.all(16),
              ),
            ),
            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveName,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF4E8BF0),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  "Save",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
