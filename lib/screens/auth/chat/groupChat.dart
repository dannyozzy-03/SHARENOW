import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:web_socket_channel/io.dart';
import 'groupDescription.dart';

class GroupChat extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupChat({super.key, required this.groupId, required this.groupName});

  @override
  State<GroupChat> createState() => _GroupChatState();
}

class _GroupChatState extends State<GroupChat> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;

  String? groupImageUrl;
  String? pinnedMessageId;
  String? pinnedMessageText;
  String? pinnedMessageSenderName;
  String? upcomingDeadlineText;
  DateTime? upcomingDeadlineDate;

  String? chatId;

  // Add these fields to _GroupChatState class
  bool isInChat = false;
  late IOWebSocketChannel channel;

  @override
  void initState() {
    super.initState();
    chatId = widget.groupId;
    isInChat = true;

    try {
      // Connect to WebSocket with proper URL format and error handling
      final String serverUrl = "ws://192.168.0.15:3000?userId=$currentUserId";
      channel = IOWebSocketChannel.connect(
        Uri.parse(serverUrl),
        pingInterval: Duration(seconds: 30),
      );
      
      // Register user with WebSocket
      channel.sink.add(jsonEncode({
        "type": "register",
        "userId": currentUserId,
        "groupId": widget.groupId,
        "isActive": true
      }));

      // Add WebSocket error handling
      channel.stream.handleError((error) {
        print("WebSocket error: $error");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connection error. Messages may be delayed.'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
    } catch (e) {
      print("Error connecting to WebSocket: $e");
    }

    _updateUserStatus(true);
    _loadGroupImage();
    _loadPinnedMessage();
    _checkUpcomingDeadline();
    _setupMessageListener();

    // Add listener to scroll to bottom when keyboard appears
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  void _setupMessageListener() {
    FirebaseFirestore.instance
        .collection('groupChats')
        .doc(widget.groupId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (!isInChat) return;
      if (snapshot.docs.isEmpty) return;

      var lastMessage = snapshot.docs.first;
      if (lastMessage.exists) {
        // Update readBy status for new messages if user is active
        FirebaseFirestore.instance
            .collection('groupChats')
            .doc(widget.groupId)
            .get()
            .then((groupDoc) {
          if (groupDoc.exists) {
            Map<String, dynamic> activeUsers = groupDoc.get('activeUsers') ?? {};
            if (activeUsers[currentUserId] == true) {
              lastMessage.reference.update({
                'readBy.$currentUserId': true
              });
            }
          }
        });
      }
    });
  }

  Stream<DocumentSnapshot> _groupStream() {
    return FirebaseFirestore.instance
        .collection("groupChats")
        .doc(widget.groupId)
        .snapshots();
  }

  Future<void> _checkUpcomingDeadline() async {
    try {
      DocumentSnapshot groupDoc = await FirebaseFirestore.instance
          .collection("groupChats")
          .doc(widget.groupId)
          .get();

      if (groupDoc.exists && groupDoc.data() is Map<String, dynamic>) {
        Map<String, dynamic> data = groupDoc.data() as Map<String, dynamic>;
        Map<String, dynamic>? deadlines = data["deadlines"] as Map<String, dynamic>?;

        _processDeadlines(deadlines);
      }
    } catch (e) {
      print("Error checking upcoming deadlines: $e");
    }
  }

  void _processDeadlines(Map<String, dynamic>? deadlines) {
    if (deadlines != null) {
      DateTime now = DateTime.now();
      DateTime normalizedNow = DateTime(now.year, now.month, now.day);
      DateTime? closestDeadline;
      String? closestDeadlineText;

      deadlines.forEach((key, value) {
        DateTime deadlineDate = DateTime.parse(key);
        DateTime normalizedDeadlineDate = DateTime(
          deadlineDate.year,
          deadlineDate.month,
          deadlineDate.day,
        );

        if (!normalizedDeadlineDate.isBefore(normalizedNow) &&
            normalizedDeadlineDate.difference(normalizedNow).inDays <= 3) {
          if (closestDeadline == null ||
              normalizedDeadlineDate.isBefore(closestDeadline!)) {
            closestDeadline = normalizedDeadlineDate;
            closestDeadlineText = (value as List<dynamic>).join(", ");
          }
        }
      });

      setState(() {
        upcomingDeadlineDate = closestDeadline;
        upcomingDeadlineText = closestDeadlineText;
      });
    } else {
      setState(() {
        upcomingDeadlineDate = null;
        upcomingDeadlineText = null;
      });
    }
  }

  Future<void> _loadGroupImage() async {
    try {
      DocumentSnapshot groupDoc = await FirebaseFirestore.instance
          .collection("groupChats")
          .doc(widget.groupId)
          .get();

      if (groupDoc.exists) {
        setState(() {
          groupImageUrl =
              (groupDoc.data() as Map<String, dynamic>)["groupImageUrl"];
        });
      }
    } catch (e) {
      print("Error loading group image: $e");
    }
  }

  Future<void> _loadPinnedMessage() async {
    try {
      DocumentSnapshot groupDoc = await FirebaseFirestore.instance
          .collection("groupChats")
          .doc(widget.groupId)
          .get();

      if (groupDoc.exists && groupDoc.data() is Map<String, dynamic>) {
        Map<String, dynamic> data = groupDoc.data() as Map<String, dynamic>;
        if (data.containsKey('pinnedMessageId')) {
          setState(() {
            pinnedMessageId = data['pinnedMessageId'];
          });

          if (pinnedMessageId != null) {
            DocumentSnapshot messageDoc = await FirebaseFirestore.instance
                .collection("groupChats")
                .doc(widget.groupId)
                .collection("messages")
                .doc(pinnedMessageId)
                .get();

            if (messageDoc.exists) {
              Map<String, dynamic> messageData =
                  messageDoc.data() as Map<String, dynamic>;
              String senderId = messageData['senderId'];

              if (senderId == "system") {
                setState(() {
                  pinnedMessageText = messageData['text'];
                  pinnedMessageSenderName = "System";
                });
              } else {
                DocumentSnapshot userDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(senderId)
                    .get();

                if (userDoc.exists) {
                  setState(() {
                    pinnedMessageText = messageData['text'];
                    pinnedMessageSenderName = userDoc['name'];
                  });
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print("Error loading pinned message: $e");
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Color(0xFFF5F7FB),
        appBar: _buildAppBar(),
        body: SafeArea(
          child: StreamBuilder<DocumentSnapshot>(
            stream: _groupStream(),
            builder: (context, snapshot) {
              DateTime? closestDeadline;
              String? closestDeadlineText;

              if (snapshot.hasData && snapshot.data!.data() is Map<String, dynamic>) {
                Map<String, dynamic> data = snapshot.data!.data() as Map<String, dynamic>;
                Map<String, dynamic>? deadlines = data["deadlines"] as Map<String, dynamic>?;

                if (deadlines != null) {
                  DateTime now = DateTime.now();
                  DateTime normalizedNow = DateTime(now.year, now.month, now.day);

                  deadlines.forEach((key, value) {
                    DateTime deadlineDate = DateTime.parse(key);
                    DateTime normalizedDeadlineDate = DateTime(
                      deadlineDate.year,
                      deadlineDate.month,
                      deadlineDate.day,
                    );

                    if (!normalizedDeadlineDate.isBefore(normalizedNow) &&
                        normalizedDeadlineDate.difference(normalizedNow).inDays <= 3) {
                      if (closestDeadline == null ||
                          normalizedDeadlineDate.isBefore(closestDeadline!)) {
                        closestDeadline = normalizedDeadlineDate;
                        closestDeadlineText = (value as List<dynamic>).join(", ");
                      }
                    }
                  });
                }
              }

              return Column(
                children: [
                  if (closestDeadline != null)
                    _buildDeadlineCountdownBanner(closestDeadline!, closestDeadlineText),
                  if (pinnedMessageId != null) _buildPinnedMessageBanner(),
                  Expanded(
                    child: _buildMessageList(),
                  ),
                  _buildMessageInput(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: Colors.blueGrey[800],
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: Colors.blueGrey[700]),
        onPressed: () => Navigator.pop(context),
      ),
      title: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GroupDescriptionScreen(
              groupId: widget.groupId,
              groupName: widget.groupName,
            ),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.blueGrey[100],
              backgroundImage: groupImageUrl != null && groupImageUrl!.isNotEmpty
                  ? NetworkImage(groupImageUrl!) as ImageProvider
                  : const AssetImage("assets/images/defaultGroupChat.png"),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, // Add this
                children: [
                  Text(
                    widget.groupName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueGrey[800],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    "Tap for group info",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blueGrey[400],
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('groupChats')
              .doc(widget.groupId)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const SizedBox();
            }

            Map<String, dynamic> data = snapshot.data!.data() as Map<String, dynamic>;
            Map<String, dynamic> activeUsers = data['activeUsers'] as Map<String, dynamic>? ?? {};
            int activeCount = activeUsers.values.where((v) => v == true).length;

            return Row(
              mainAxisSize: MainAxisSize.min, // Add this
              children: [
                if (activeCount > 0)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min, // Add this
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          '$activeCount active',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                IconButton(
                  icon: Icon(Icons.more_vert, color: Colors.blueGrey[700]),
                  onPressed: () {},
                ),
              ],
            );
          },
        ),
      ],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(16),
        ),
      ),
    );
  }

  Widget _buildPinnedMessageBanner() {
    return Container(
      margin: EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.amber.withOpacity(0.5), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.push_pin, size: 16, color: Colors.amber[700]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pinnedMessageSenderName ?? "Unknown",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber[800],
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  pinnedMessageText ?? "Pinned message",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blueGrey[700],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: Colors.blueGrey[400]),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection("groupChats")
                  .doc(widget.groupId)
                  .update({
                'pinnedMessageId': FieldValue.delete(),
              });
              setState(() {
                pinnedMessageId = null;
                pinnedMessageText = null;
                pinnedMessageSenderName = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDeadlineCountdownBanner(DateTime deadline, String? text) {
    DateTime now = DateTime.now();
    DateTime normalizedNow = DateTime(now.year, now.month, now.day);
    DateTime normalizedDeadline = DateTime(
      deadline.year,
      deadline.month,
      deadline.day,
    );

    int daysLeft = normalizedDeadline.difference(normalizedNow).inDays;

    return Container(
      margin: EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.red.withOpacity(0.5), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.event, size: 16, color: Colors.red[700]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Upcoming Deadline",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[800],
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  "$text (in $daysLeft days)",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blueGrey[700],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: Colors.blueGrey[400]),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              // Handle dismissing the deadline banner
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("groupChats")
          .doc(widget.groupId)
          .collection("messages")
          .orderBy("timestamp", descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(
            child: CircularProgressIndicator(
              color: Colors.blueGrey[400],
              strokeWidth: 3,
            ),
          );
        }

        var messages = snapshot.data!.docs.reversed.toList();

        if (messages.isEmpty) {
          return Center(
            child: Text(
              "No messages yet",
              style: TextStyle(
                color: Colors.blueGrey[400],
                fontSize: 16,
              ),
            ),
          );
        }

        // Add this line to scroll to bottom after building the list
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        return ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          itemCount: messages.length,
          reverse: false,  // Change this to false
          itemBuilder: (context, index) {
            var message = messages[index];
            return _buildMessageItem(message);
          },
        );
      },
    );
  }


  void _showMessageOptions(BuildContext context, String messageId,
      String messageText, String senderName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 40,
                  height: 4,
                  margin: EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    messageId == pinnedMessageId
                        ? Icons.push_pin_outlined
                        : Icons.push_pin,
                    color: Colors.amber[700],
                  ),
                  title: Text(
                    messageId == pinnedMessageId
                        ? 'Unpin message'
                        : 'Pin message',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.blueGrey[800],
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);

                    if (messageId == pinnedMessageId) {
                      await FirebaseFirestore.instance
                          .collection("groupChats")
                          .doc(widget.groupId)
                          .update({
                        'pinnedMessageId': FieldValue.delete(),
                      });
                      setState(() {
                        pinnedMessageId = null;
                        pinnedMessageText = null;
                        pinnedMessageSenderName = null;
                      });
                    } else {
                      await FirebaseFirestore.instance
                          .collection("groupChats")
                          .doc(widget.groupId)
                          .update({
                        'pinnedMessageId': messageId,
                      });
                      setState(() {
                        pinnedMessageId = messageId;
                        pinnedMessageText = messageText;
                        pinnedMessageSenderName = senderName;
                      });
                    }
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.content_copy,
                    color: Colors.blueGrey[600],
                  ),
                  title: Text(
                    'Copy message',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.blueGrey[800],
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Message copied to clipboard'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        backgroundColor: Colors.blueGrey[700],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.attach_file_rounded,
                color: Colors.blueGrey[500], size: 24),
            onPressed: () {},
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blueGrey[50],
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: "Type your message...",
                  hintStyle: TextStyle(
                    color: Colors.blueGrey[400],
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.blueGrey[800],
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: Color(0xFF4E8BF0),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF4E8BF0).withOpacity(0.4),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: IconButton(
              icon:
                  const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final String messageText = _messageController.text.trim();
    _messageController.clear();

    try {
      // Get sender's info
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .get();

      String senderName = "Unknown";
      if (userDoc.exists) {
        var userData = userDoc.data() as Map<String, dynamic>;
        senderName = userData['name'] ?? "Unknown";
      }

      // Create message document first
      DocumentReference messageRef = await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.groupId)
          .collection('messages')
          .add({
      'text': messageText,
      'senderId': currentUserId,
      'senderName': senderName,
      'timestamp': FieldValue.serverTimestamp(),
      'readBy': {currentUserId: true},
    });

      // Update group document
      await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.groupId)
          .update({
      'lastMessage': messageText,
      'lastMessageSender': senderName,
      'lastTimestamp': FieldValue.serverTimestamp(),
      'readBy.$currentUserId': true,
      'lastRead.$currentUserId': FieldValue.serverTimestamp(),
    });

      // Get group members and send notifications
      DocumentSnapshot groupDoc = await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.groupId)
          .get();

      if (groupDoc.exists) {
        Map<String, dynamic> groupData = groupDoc.data() as Map<String, dynamic>;
        List<String> members = List<String>.from(groupData['members'] ?? []);
        Map<String, dynamic> activeUsers = groupData['activeUsers'] ?? {};

        // Send notifications to inactive members
        for (String memberId in members) {
          if (memberId != currentUserId && !(activeUsers[memberId] ?? false)) {
            try {
              DocumentSnapshot memberDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(memberId)
                  .get();

              if (memberDoc.exists) {
                Map<String, dynamic> memberData = memberDoc.data() as Map<String, dynamic>;
                String? fcmToken = memberData['fcmToken'] as String?;

                if (fcmToken != null && fcmToken.isNotEmpty) {
                  // Inside the _sendMessage method, update the notification data
                  Map<String, dynamic> notificationData = {
                   'type': 'groupMessage',
                    'groupName': widget.groupName,
                    'senderName': senderName,
                    'body': messageText,         
                    'senderId': currentUserId,
                    'receiverId': memberId,
                    'groupId': widget.groupId,
                    'messageId': messageRef.id,
                    'fcmToken': fcmToken,
                  };

                  try {
                    channel.sink.add(jsonEncode(notificationData));
                  } catch (wsError) {
                    print("WebSocket error: $wsError");
                  }
                }
              }
            } catch (memberError) {
              print("Error processing member $memberId: $memberError");
            }
          }
        }
      }

      _scrollToBottom();
    } catch (e) {
      print("Error sending message: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message. Please try again.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  void _updateUserStatus(bool isActive) async {
    // Update user's active status and read status in group chat
    await FirebaseFirestore.instance
        .collection('groupChats')
        .doc(widget.groupId)
        .update({
          'activeUsers.${currentUserId}': isActive,
          'readBy.${currentUserId}': true,
          'lastRead.${currentUserId}': Timestamp.now(),
        });

    // If user is active, mark all unread messages as read
    if (isActive) {
      QuerySnapshot unreadMessages = await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.groupId)
          .collection('messages')
          .where('readBy.$currentUserId', isEqualTo: false)
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var doc in unreadMessages.docs) {
        batch.update(doc.reference, {
          'readBy.$currentUserId': true
        });
      }
      await batch.commit();
    }
  }

  void _updateUserChatStatus(bool status) {
    FirebaseFirestore.instance
        .collection('groupChats')
        .doc(widget.groupId)
        .update({
      'readBy.$currentUserId': status,
    });
  }

  void _markMessagesAsRead() async {
    final Timestamp now = Timestamp.now();

    // Get the last message and update its readBy status
    QuerySnapshot lastMessageSnapshot = await FirebaseFirestore.instance
        .collection('groupChats')
        .doc(widget.groupId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (lastMessageSnapshot.docs.isNotEmpty) {
      await lastMessageSnapshot.docs.first.reference.update({
        'readBy.$currentUserId': true
      });
    }

    // Update group document
    await FirebaseFirestore.instance
        .collection('groupChats')
        .doc(widget.groupId)
        .update({
          'readBy.$currentUserId': true,
          'lastRead.$currentUserId': now,
        });
  }

  // Add this method inside _GroupChatState class
  Widget _buildMessageItem(DocumentSnapshot message) {
    Map<String, dynamic> data = message.data() as Map<String, dynamic>;
    String senderId = data['senderId'] ?? '';
    String messageText = data['text'] ?? '';
    Timestamp timestamp = data['timestamp'] ?? Timestamp.now();
    bool isMe = senderId == currentUserId;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(senderId).get(),
      builder: (context, snapshot) {
        String senderName = "Unknown";
        if (snapshot.hasData && snapshot.data!.exists) {
          senderName = (snapshot.data!.data() as Map<String, dynamic>)['name'] ?? "Unknown";
        }

        return GestureDetector(
          onLongPress: () => _showMessageOptions(
            context,
            message.id,
            messageText,
            senderName,
          ),
          child: Container(
            margin: EdgeInsets.only(
              bottom: 12,
              left: isMe ? 50 : 0,
              right: isMe ? 0 : 50,
            ),
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe) 
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Text(
                      senderName,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? Color(0xFF4E8BF0) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        messageText,
                        style: TextStyle(
                          color: isMe ? Colors.white : Colors.blueGrey[800],
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        DateFormat('HH:mm').format(timestamp.toDate()),
                        style: TextStyle(
                          fontSize: 11,
                          color: isMe 
                              ? Colors.white.withOpacity(0.8)
                              : Colors.blueGrey[400],
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
  }

  @override
  void dispose() {
    isInChat = false;
    _updateUserStatus(false); // Mark user as inactive when leaving chat
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
