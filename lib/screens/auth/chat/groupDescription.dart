import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:twitterr/helper/image_helper.dart';
import 'package:twitterr/screens/auth/chat/chat.dart';
import 'package:twitterr/screens/auth/chat/addUser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:twitterr/screens/auth/chat/editGroupName.dart';
import 'package:table_calendar/table_calendar.dart';

class GroupDescriptionScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupDescriptionScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupDescriptionScreen> createState() => _GroupDescriptionScreenState();
}

class _GroupDescriptionScreenState extends State<GroupDescriptionScreen> {
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _isEditingDescription = false;
  bool _isEditingName = false;
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  File? _selectedImage;
  bool _isUploadingImage = false;
  Map<DateTime, List<String>> _events = {};
  DateTime _selectedDay = DateTime.now();
  List<String> _selectedEvents = [];
  CalendarFormat _calendarFormat = CalendarFormat.month;

  /// Fetch deadlines from Firestore
  void _fetchDeadlines() async {
    DocumentSnapshot groupDoc = await FirebaseFirestore.instance
        .collection("groupChats")
        .doc(widget.groupId)
        .get();

    Map<String, dynamic>? deadlines = groupDoc["deadlines"];
    if (deadlines != null) {
      setState(() {
        _events = deadlines.map((key, value) {
          DateTime date = DateTime.parse(key);
          return MapEntry(date, List<String>.from(value));
        });
      });
    }
  }

  /// Add a new deadline
  void _addDeadline(DateTime date, String event) async {
    String dateKey = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

    await FirebaseFirestore.instance
        .collection("groupChats")
        .doc(widget.groupId)
        .set({
      "deadlines": {
        dateKey: FieldValue.arrayUnion([event])
      }
    }, SetOptions(merge: true));

    _fetchDeadlines();
    _showSuccessSnackBar("Deadline added successfully");
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// **Fetches a real-time stream of the group's data**
  Stream<DocumentSnapshot> _groupStream() {
    return FirebaseFirestore.instance
        .collection("groupChats")
        .doc(widget.groupId)
        .snapshots();
  }

  /// **Fetches user data for given user IDs in real-time**
  Stream<List<DocumentSnapshot>> _fetchUsernames(List<dynamic> userIds) {
    if (userIds.isEmpty) {
      return Stream.value([]);
    }

    return FirebaseFirestore.instance
        .collection("users")
        .where(FieldPath.documentId, whereIn: userIds)
        .snapshots()
        .map((snapshot) => snapshot.docs);
  }

  /// **Save group description**
  void _saveDescription() async {
    await FirebaseFirestore.instance
        .collection("groupChats")
        .doc(widget.groupId)
        .update({
      "description": _descriptionController.text,
    });

    setState(() {
      _isEditingDescription = false;
    });

    _showSuccessSnackBar("Group description updated");
  }

  /// **Save group name**
  void _saveName() async {
    await FirebaseFirestore.instance
        .collection("groupChats")
        .doc(widget.groupId)
        .update({
      "name": _nameController.text,
    });

    setState(() {
      _isEditingName = false;
    });

    _showSuccessSnackBar("Group name updated");
  }

  /// **Change group image**
  Future<void> _changeGroupImage() async {
    final ImagePicker _picker = ImagePicker();
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
        _isUploadingImage = true;
      });

      try {
        // 🔹 Compress the image before uploading
        File? compressedImage =
            await ImageHelper.compressImage(_selectedImage!);

        if (compressedImage == null) {
          throw Exception("Image compression failed");
        }

        // 🔹 Upload to Firebase Storage
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('group_images')
            .child('${widget.groupId}.jpg');

        await storageRef.putFile(compressedImage);
        final imageUrl = await storageRef.getDownloadURL();

        // 🔹 Update Firestore with the new image URL
        await FirebaseFirestore.instance
            .collection("groupChats")
            .doc(widget.groupId)
            .update({
          "groupImageUrl": imageUrl,
        });

        _showSuccessSnackBar("Group image updated");
      } catch (e) {
        _showErrorSnackBar("Failed to update image: $e");
      } finally {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF4E8BF0),
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red[400],
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  /// **Leave Group Function**
  void _leaveGroup() async {
    if (currentUserId.isEmpty) return;

    bool confirmLeave = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          "Leave Group",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.blueGrey[800],
          ),
        ),
        content: Text(
          "Are you sure you want to leave this group?",
          style: TextStyle(color: Colors.blueGrey[700]),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: Colors.white,
        elevation: 8,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              "Cancel",
              style: TextStyle(color: Colors.blueGrey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[400],
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text("Leave"),
          ),
        ],
      ),
    );

    if (confirmLeave == true) {
      await FirebaseFirestore.instance
          .collection("groupChats")
          .doc(widget.groupId)
          .update({
        "members": FieldValue.arrayRemove([currentUserId])
      });

      if (!mounted) return;

      // Add a system message about leaving
      await FirebaseFirestore.instance
          .collection("groupChats")
          .doc(widget.groupId)
          .collection("messages")
          .add({
        "text": "A user has left the group",
        "senderId": "system",
        "timestamp": FieldValue.serverTimestamp(),
      });

      _showSuccessSnackBar("You have left the group");

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => Chat()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Color(0xFFF5F7FB),
        body: SafeArea(
          child: StreamBuilder<DocumentSnapshot>(
            stream: _groupStream(),
            builder: (context, groupSnapshot) {
              if (!groupSnapshot.hasData || !groupSnapshot.data!.exists) {
                return Center(
                  child: CircularProgressIndicator(
                    color: Colors.blueGrey[400],
                    strokeWidth: 3,
                  ),
                );
              }

              var groupData =
                  groupSnapshot.data!.data() as Map<String, dynamic>? ?? {};

              String groupDescription = groupData.containsKey("description")
                  ? groupData["description"]
                  : "No description available";

              String groupName = groupData.containsKey("name")
                  ? groupData["name"]
                  : widget.groupName;

              String? groupImageUrl = groupData["groupImageUrl"];

              List<dynamic> members =
                  groupData.containsKey("members") ? groupData["members"] : [];

              if (!_isEditingDescription) {
                _descriptionController.text = groupDescription;
              }

              if (!_isEditingName) {
                _nameController.text = groupName;
              }

              return Stack(
                children: [
                  // Column ensures the app bar stays fixed at the top
                  Column(
                    children: [
                      // Custom App Bar (Fixed at the top)
                      Container(
                        height: 25,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Back button
                            IconButton(
                              icon: Icon(Icons.arrow_back,
                                  color: Colors.blueGrey[700]),
                              onPressed: () => Navigator.pop(context),
                            ),
                            // Create/Edit button
                            IconButton(
                              icon: Icon(Icons.more_vert,
                                  color: Colors.blueGrey[700]),
                              onPressed: () => _showOptionsMenu(context),
                            ),
                          ],
                        ),
                      ),
                      // Expanded ListView (scrollable content)
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          children: [
                            _buildGroupAvatar(groupImageUrl),
                            const SizedBox(height: 16),
                            _buildEditableName(groupName),
                            const SizedBox(height: 24),

                            // Add the Calendar Widget
                            _buildCalendar(),

                            const SizedBox(height: 16),
                            _buildSectionCard(
                              title: "About this group",
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "Description",
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.blueGrey[500],
                                        ),
                                      ),
                                      if (!_isEditingDescription)
                                        IconButton(
                                          icon: Icon(Icons.edit_outlined,
                                              size: 18,
                                              color: Color(0xFF4E8BF0)),
                                          onPressed: () => setState(() =>
                                              _isEditingDescription = true),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (_isEditingDescription)
                                    _buildDescriptionEditor(groupDescription)
                                  else
                                    Text(
                                      groupDescription,
                                      style: TextStyle(
                                        fontSize: 15,
                                        height: 1.5,
                                        color: Colors.blueGrey[800],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            _buildParticipantsList(members),
                            const SizedBox(height: 24),
                            _buildGroupInfoCard(groupData),
                            const SizedBox(height: 16),
                            _buildLeaveGroupButton(),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Loading overlay
                  if (_isUploadingImage)
                    Container(
                      color: Colors.black.withOpacity(0.5),
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildGroupAvatar(String? imageUrl) {
    return Center(
      child: Stack(
        children: [
          Hero(
            tag: 'group-${widget.groupId}',
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
                image: DecorationImage(
                  image: imageUrl != null
                      ? NetworkImage(imageUrl) as ImageProvider
                      : AssetImage("assets/images/defaultGroupChat.png"),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: InkWell(
              onTap: _changeGroupImage,
              child: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color(0xFF4E8BF0),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableName(String groupName) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Group Name (Auto-wraps if too long)
          Text(
            groupName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey[800],
            ),
            maxLines: 2, // Allows wrapping
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _showOptionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.edit, color: Color(0xFF4E8BF0)),
                title: Text('Edit Group Name'),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToEditNameScreen();
                },
              ),
              // You can add more options here
            ],
          ),
        );
      },
    );
  }

  void _navigateToEditNameScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditGroupNameScreen(
          groupId: widget.groupId,
          initialName: _nameController.text,
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }

  Widget _buildDescriptionEditor(String originalDescription) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.blueGrey[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: "Enter group description...",
              hintStyle: TextStyle(color: Colors.blueGrey[400]),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(12),
            ),
            style: TextStyle(
              fontSize: 15,
              color: Colors.blueGrey[800],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isEditingDescription = false;
                      _descriptionController.text = originalDescription;
                    });
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blueGrey[600],
                  ),
                  child: const Text("Cancel"),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saveDescription,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF4E8BF0),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text("Save"),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddButton() {
    return ElevatedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddUserScreen(groupId: widget.groupId),
          ),
        );
      },
      icon: const Icon(Icons.person_add, size: 16),
      label: const Text("Add"),
      style: ElevatedButton.styleFrom(
        backgroundColor: Color(0xFF4E8BF0),
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _buildParticipantsList(List<dynamic> members) {
    return StreamBuilder<List<DocumentSnapshot>>(
      stream: _fetchUsernames(members),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF4E8BF0),
              ),
            ),
          );
        }

        List<DocumentSnapshot> users = userSnapshot.data!;
        if (users.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "No participants found",
                style: TextStyle(
                  color: Colors.blueGrey[400],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Participants (${users.length})",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.blueGrey[800],
                      ),
                    ),
                    _buildAddButton(),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.blueGrey[50]),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: users.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: Colors.blueGrey[50],
                  indent: 70,
                ),
                itemBuilder: (context, index) {
                  var userDoc = users[index];
                  String username = userDoc["name"] ?? "Unknown User";
                  String userId = userDoc.id;
                  bool isCurrentUser = userId == currentUserId;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          isCurrentUser ? Color(0xFF4E8BF0) : Colors.blueGrey[100],
                      child: Text(
                        username.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      username,
                      style: TextStyle(
                        fontWeight:
                            isCurrentUser ? FontWeight.bold : FontWeight.normal,
                        color: Colors.blueGrey[800],
                      ),
                    ),
                    subtitle: isCurrentUser
                        ? Text(
                            "You",
                            style: TextStyle(
                              color: Color(0xFF4E8BF0),
                              fontSize: 12,
                            ),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGroupInfoCard(Map<String, dynamic> groupData) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Colors.blueGrey[400],
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Group created on",
                  style: TextStyle(
                    color: Colors.blueGrey[500],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  groupData.containsKey("createdAt") &&
                          groupData["createdAt"] != null
                      ? _formatTimestamp(groupData["createdAt"])
                      : "Unknown date",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.blueGrey[800],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveGroupButton() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ElevatedButton.icon(
        onPressed: _leaveGroup,
        icon: const Icon(Icons.exit_to_app, size: 18),
        label: const Text("Leave Group"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red[400],
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) {
      DateTime dateTime = timestamp.toDate();
      return "${dateTime.day}/${dateTime.month}/${dateTime.year}";
    } else {
      return "Unknown date";
    }
  }

  Future<Map<DateTime, List<String>>> fetchDeadlines() async {
    try {
      DocumentSnapshot groupDoc = await FirebaseFirestore.instance
          .collection("groupChats")
          .doc(widget.groupId)
          .get();

      if (groupDoc.exists) {
        Map<String, dynamic>? deadlines = groupDoc["deadlines"];
        if (deadlines != null) {
          // Convert Firestore's string keys to DateTime and map values to List<String>
          return deadlines.map((key, value) {
            DateTime date = DateTime.parse(key);
            return MapEntry(date, List<String>.from(value));
          });
        }
      }
    } catch (e) {
      print("Error fetching deadlines: $e");
    }
    return {};
  }

  @override
  void initState() {
    super.initState();
    _descriptionController.text = widget.groupName;
    _nameController.text = widget.groupName;
    _fetchDeadlines(); // Initialize deadlines when screen loads
  }

  Widget _buildCalendar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Deadlines",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey[800],
              ),
            ),
            const SizedBox(height: 16),
            TableCalendar(
              focusedDay: _selectedDay,
              firstDay: DateTime(2000),
              lastDay: DateTime(2100),
              calendarFormat: CalendarFormat.month,
              availableCalendarFormats: const {
                CalendarFormat.month: 'Month',
              },
              eventLoader: (day) => _events[day] ?? [], // Load events for the day
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay; // Update the selected day
                  _selectedEvents = _events[selectedDay] ?? [];
                });
              },
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: Colors.blueGrey[200],
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: Color(0xFF4E8BF0),
                  shape: BoxShape.circle,
                ),
                markerDecoration: BoxDecoration(
                  color: Colors.blueGrey[400],
                  shape: BoxShape.circle,
                ),
                // Highlight days with deadlines
                defaultDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                ),
                outsideDaysVisible: false,
                weekendTextStyle: TextStyle(
                  color: Colors.red[400],
                ),
                defaultTextStyle: TextStyle(
                  color: Colors.blueGrey[800],
                ),
              ),
              calendarBuilders: CalendarBuilders(
                // Custom builder for days with events
                singleMarkerBuilder: (context, date, _) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.red[400], // Color for days with deadlines
                      shape: BoxShape.circle,
                    ),
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  );
                },
                defaultBuilder: (context, date, _) {
                  if (_events[date]?.isNotEmpty ?? false) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.green[300], // Color for days with deadlines
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${date.day}',
                        style: TextStyle(color: Colors.white),
                      ),
                    );
                  }
                  return null; // Use default rendering for other days
                },
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _showAddDeadlineDialog,
              child: const Text("Add Deadline"),
            ),
            const SizedBox(height: 16),
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("groupChats")
                  .doc(widget.groupId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                if (!snapshot.data!.exists) {
                  return _buildEmptyDeadlineMessage();
                }

                Map<String, dynamic>? deadlines =
                    (snapshot.data!.data() as Map<String, dynamic>?)?["deadlines"] as Map<String, dynamic>?;

                if (deadlines == null || deadlines.isEmpty) {
                  return _buildEmptyDeadlineMessage();
                }

                String dateKey =
                    "${_selectedDay.year}-${_selectedDay.month.toString().padLeft(2, '0')}-${_selectedDay.day.toString().padLeft(2, '0')}";

                List<String>? existingDeadlines =
                    deadlines[dateKey]?.cast<String>();

                if (existingDeadlines == null || existingDeadlines.isEmpty) {
                  return _buildEmptyDeadlineMessage();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: existingDeadlines.asMap().entries.map((entry) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.shade100,
                            offset: const Offset(0, 1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.checklist_rounded,
                            size: 16,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              entry.value,
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => _deleteDeadline(_selectedDay, entry.value),
                            child: Icon(
                              Icons.close,
                              size: 18,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddDeadlineDialog() {
    final TextEditingController _eventController = TextEditingController();
    final dateFormat = DateFormat('MMMM d, y'); // More elegant date format

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20), // More rounded corners
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        title: Row(
          children: [
            Icon(Icons.event, color: Theme.of(context).primaryColor),
            const SizedBox(width: 12),
            Text(
              "Add Deadline",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        content: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Selected Date Card
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 18,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        dateFormat.format(_selectedDay),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Event Name Input
              TextField(
                controller: _eventController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: "Event Name",
                  hintText: "Enter event name",
                  prefixIcon: Icon(Icons.edit_calendar, color: Theme.of(context).primaryColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
              const SizedBox(height: 24),

              // Existing Deadlines Section
              Text(
                "Existing Deadlines",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),

              // Real-Time Display of Existing Deadlines
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                padding: const EdgeInsets.all(12),
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection("groupChats")
                      .doc(widget.groupId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }

                    if (!snapshot.data!.exists) {
                      return _buildEmptyDeadlineMessage();
                    }

                    Map<String, dynamic>? deadlines =
                        snapshot.data!["deadlines"] as Map<String, dynamic>?;

                    if (deadlines == null || deadlines.isEmpty) {
                      return _buildEmptyDeadlineMessage();
                    }

                    String dateKey =
                        "${_selectedDay.year}-${_selectedDay.month.toString().padLeft(2, '0')}-${_selectedDay.day.toString().padLeft(2, '0')}";

                    List<String>? existingDeadlines =
                        deadlines[dateKey]?.cast<String>();

                    if (existingDeadlines == null || existingDeadlines.isEmpty) {
                      return _buildEmptyDeadlineMessage();
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: existingDeadlines.asMap().entries.map((entry) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.shade100,
                                offset: const Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.checklist_rounded,
                                size: 16,
                                color: Theme.of(context).primaryColor,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  entry.value,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => _deleteDeadline(_selectedDay, entry.value),
                                child: Icon(
                                  Icons.delete,
                                  size: 18,
                                  color: Colors.red.shade400,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () {
              if (_eventController.text.isNotEmpty) {
                _addDeadline(_selectedDay, _eventController.text);
                Navigator.pop(context);
              } else {
                // Show error animation on the input field
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Please enter an event name"),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Colors.redAccent,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text("ADD"),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDeadlineMessage() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.event_available,
            size: 30,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 8),
          Text(
            "No deadlines for this date",
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  // Add this function to handle deadline deletion
  void _deleteDeadline(DateTime date, String eventName) async {
    try {
      final dateKey = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

      // Get current deadlines
      final docSnapshot = await FirebaseFirestore.instance
          .collection("groupChats")
          .doc(widget.groupId)
          .get();

      Map<String, dynamic> deadlines =
          (docSnapshot.data()?["deadlines"] as Map<String, dynamic>?) ?? {};

      // Remove the deadline
      if (deadlines.containsKey(dateKey)) {
        List<String> dateDeadlines = List<String>.from(deadlines[dateKey]);
        dateDeadlines.remove(eventName);

        if (dateDeadlines.isEmpty) {
          deadlines.remove(dateKey);
        } else {
          deadlines[dateKey] = dateDeadlines;
        }

        // Update Firestore
        await FirebaseFirestore.instance
            .collection("groupChats")
            .doc(widget.groupId)
            .update({"deadlines": deadlines});
      }
    } catch (e) {
      print("Error deleting deadline: $e");
    }
  }
}
