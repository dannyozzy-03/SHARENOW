import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:twitterr/screens/auth/chat/chatSelection.dart';
import 'package:twitterr/screens/auth/chat/groupChat.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'personalChat.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class Chat extends StatefulWidget {
  const Chat({super.key});

  @override
  State<Chat> createState() => _ChatState();
}

class _ChatState extends State<Chat> {
  int _selectedIndex = 0;
  final userId = FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          "Messages",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black54),
            onPressed: () {
              // Implement search functionality
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildChatTabs(),
          Expanded(
            child: _selectedIndex == 0
                ? PersonalChatList(userId: userId!)
                : GroupChatList(userId: userId!),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ChatSelectionScreen()),
        ),
        backgroundColor: Colors.deepPurple,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
      ),
    );
  }

  Widget _buildChatTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabItem("Personal", 0),
          ),
          Expanded(
            child: _buildTabItem("Groups", 1),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem(String label, int index) {
    bool isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.deepPurple : Colors.black54,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class PersonalChatList extends StatefulWidget {
  final String userId;
  const PersonalChatList({super.key, required this.userId});

  @override
  _PersonalChatListState createState() => _PersonalChatListState();
}

class _PersonalChatListState extends State<PersonalChatList> {
  List<Map<String, dynamic>> _personalChats = [];
  List<StreamSubscription> _subscriptions = []; // Add this line to track subscriptions

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchPersonalChats();
    });
  }

  void _fetchPersonalChats() {
    // Store the main chat subscription
    final chatSubscription = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: widget.userId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return; // Check if widget is still mounted

      try {
        if (snapshot.docs.isEmpty) {
          setState(() {
            _personalChats = [];
          });
          return;
        }

        var chats = snapshot.docs;
        for (var chatDoc in chats) {
          String chatId = chatDoc.id;
          List<dynamic> participants = chatDoc['participants'];
          String receiverId =
              participants.firstWhere((id) => id != widget.userId);

          bool isRead = chatDoc.data().containsKey("readBy") &&
              (chatDoc.data()["readBy"] as Map<String, dynamic>?)
                      ?.containsKey(widget.userId) ==
                  true &&
              chatDoc.data()["readBy"][widget.userId] == true;

          // Store the user subscription
          final userSubscription = FirebaseFirestore.instance
              .collection('users')
              .doc(receiverId)
              .snapshots()
              .listen((userSnapshot) {
            if (!mounted) return; // Check if widget is still mounted
            if (!userSnapshot.exists) return;

            var receiverData = userSnapshot.data()!;
            String receiverName = receiverData['name'] ?? 'Unknown';
            String? avatarUrl = receiverData['profileImageUrl'];

            // Store the message subscription
            final messageSubscription = FirebaseFirestore.instance
                .collection('chats')
                .doc(chatId)
                .collection('messages')
                .orderBy('timestamp', descending: true)
                .limit(1)
                .snapshots()
                .listen((messageSnapshot) {
              if (!mounted) return; // Check if widget is still mounted
              if (messageSnapshot.docs.isEmpty) return;

              var lastMessageDoc = messageSnapshot.docs.first;
              String lastMessage = lastMessageDoc['text'];
              Timestamp timestamp = lastMessageDoc['timestamp'];
              DateTime lastTimestamp = timestamp.toDate();

              var lastMessageData = lastMessageDoc.data();
              String senderId = lastMessageData["sender"] ?? "UnknownSender";
              bool isFromCurrentUser = senderId == widget.userId;

              // Find current chat data if it exists
              Map<String, dynamic>? existingChat;
              int existingIndex = _personalChats
                  .indexWhere((chat) => chat["chatId"] == chatId);
              if (existingIndex >= 0) {
                existingChat = _personalChats[existingIndex];
              }

              // Update chat data
              if (mounted) { // Check if widget is still mounted
                setState(() {
                  bool isAllRead = false;
                  if (chatDoc.data().containsKey("readBy")) {
                    Map<String, dynamic> readBy = chatDoc.data()["readBy"] as Map<String, dynamic>;
                    isAllRead = readBy.values.every((value) => value == true);
                  }

                  Map<String, dynamic> chatData = {
                    "chatId": chatId,
                    "receiverId": receiverId,
                    "receiverName": receiverName,
                    "avatarUrl": avatarUrl,
                    "lastMessage": lastMessage,
                    "lastTimestamp": lastTimestamp,
                    "isRead": isFromCurrentUser,
                    "isFromCurrentUser": isFromCurrentUser,
                    "chatIsRead": isAllRead,  // Update this to use isAllRead
                    "lastMessageId": lastMessageDoc.id,
                    "isActive": (chatDoc.data()?['activeUsers']?[receiverId] ?? false), // Add this line
                  };

                  if (existingIndex >= 0) {
                    _personalChats[existingIndex] = chatData;
                  } else {
                    _personalChats.add(chatData);
                  }

                  _personalChats.sort(
                      (a, b) => b["lastTimestamp"].compareTo(a["lastTimestamp"]));
                });
              }
            });
            _subscriptions.add(messageSubscription);
          });
          _subscriptions.add(userSubscription);
        }
      } catch (e) {
        print("Error fetching personal chats: $e");
      }
    });
    _subscriptions.add(chatSubscription);
  }

  @override
  void dispose() {
    // Cancel all subscriptions
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_personalChats.isEmpty) {
      return _buildEmptyChatUI();
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      itemCount: _personalChats.length,
      itemBuilder: (context, index) {
        var chat = _personalChats[index];
        return _buildChatItem(context, chat);
      },
    );
  }

  Widget _buildChatItem(BuildContext context, Map<String, dynamic> chat) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(chat["chatId"])
          .snapshots(),
      builder: (context, snapshot) {
        int unreadCount = 0;
        
        if (snapshot.hasData && snapshot.data!.exists) {
          var chatData = snapshot.data!.data() as Map<String, dynamic>;
          var unreadCounts = chatData['unreadCount'] as Map<String, dynamic>?;
          unreadCount = unreadCounts?[widget.userId] ?? 0;
        }

        String formattedTime = _formatChatTime(chat["lastTimestamp"]);
        bool isRead = chat["isRead"] ?? true;
        bool isFromCurrentUser = chat["isFromCurrentUser"] ?? false;
        bool chatIsRead = chat["chatIsRead"] ?? false;
        bool shouldHighlight = !isRead && !isFromCurrentUser && !chatIsRead;
        bool receiverActive = chat["isActive"] ?? false;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              _openChat(context, chat["receiverId"], chat["receiverName"],
                  chat["chatId"]);
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Stack(
                    children: [
                      chat["avatarUrl"] != null && chat["avatarUrl"].isNotEmpty
                          ? CircleAvatar(
                              radius: 24,
                              backgroundImage: NetworkImage(chat["avatarUrl"]),
                            )
                          : CircleAvatar(
                              radius: 24,
                              backgroundColor: Colors.deepPurple.withOpacity(0.2),
                              child: Text(
                                chat["receiverName"][0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.deepPurple,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                      if (receiverActive)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    chat["receiverName"],
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Row(
                              children: [
                                if (unreadCount > 0)
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    margin: EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      unreadCount.toString(),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                Text(
                                  formattedTime,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: shouldHighlight ? Colors.deepPurple : Colors.grey[500],
                                    fontWeight: shouldHighlight ? FontWeight.w500 : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (isFromCurrentUser)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    chatIsRead ? Icons.done_all : Icons.check,  // Double tick if all read, single if not
                                    size: 16,
                                    color: chatIsRead ? Colors.blue : Colors.grey,  // Blue when all read, grey when not
                                  ),
                                  const SizedBox(width: 4),
                                ],
                              ),
                            Expanded(
                              child: Text(
                                chat["lastMessage"],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: shouldHighlight
                                      ? Colors.black87
                                      : Colors.grey[600],
                                  fontWeight: shouldHighlight
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyChatUI() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            "No conversations yet",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Start chatting with your friends",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  void _openChat(BuildContext context, String receiverId, String receiverName,
      String chatId) {
    // Reset unread count when opening chat
    FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .update({
          "unreadCount.${widget.userId}": 0,
          "readBy.${widget.userId}": true,
          "activeUsers.${widget.userId}": true,
        });

    // Mark the chat as read
    FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .update({
          "readBy.${widget.userId}": true,
          "activeUsers.${widget.userId}": true, // Mark user as active
        });

    // Mark last message as read
    FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get()
        .then((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        var lastMessageDoc = snapshot.docs.first;
        lastMessageDoc.reference.update({
          "readBy": FieldValue.arrayUnion([widget.userId]),
        });
      }
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PersonalChat(receiverId: receiverId),
      ),
    ).then((_) {
      // When returning from chat, mark user as inactive
      FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .update({
            "activeUsers.${widget.userId}": false,
          });
    });
  }

  String _formatChatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDate == today) {
      return DateFormat('HH:mm').format(dateTime); // 24-hour format
    } else if (messageDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM d, HH:mm')
          .format(dateTime); // Adds time to the date
    }
  }
}

class GroupChatList extends StatefulWidget {
  final String userId;
  const GroupChatList({super.key, required this.userId});

  @override
  _GroupChatListState createState() => _GroupChatListState();
}

class _GroupChatListState extends State<GroupChatList> {
  late WebSocketChannel _channel;
  List<Map<String, dynamic>> _groups = [];
  Set<String> _openedChats = {}; // Track opened group chats

  @override
  void initState() {
    super.initState(); 
    _channel = WebSocketChannel.connect(
        Uri.parse("wss://sharenow-ipuj.onrender.com?user=${widget.userId}"));

    _channel.stream.listen((message) {
      final data = jsonDecode(message);
      if (data["type"] == "newGroup") {
        setState(() {
          _groups.add({
            "groupId": data["groupId"],
            "groupName": data["groupName"],
            "lastMessage": "",
            "lastTimestamp": DateTime.now(),
          });
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchGroups();
    });
  }

  void _fetchGroups() {
    FirebaseFirestore.instance
        .collection("groupChats")
        .where("members", arrayContains: widget.userId)
        .snapshots()
        .listen((snapshot) async {
      List<Map<String, dynamic>> updatedGroups = [];

      for (var doc in snapshot.docs) {
        String groupId = doc.id;
        String groupName = doc["groupName"];
        String? groupImageUrl = doc.data().containsKey("groupImageUrl")
            ? doc["groupImageUrl"]
            : null;

        // Get the last message details
        QuerySnapshot messageSnapshot = await FirebaseFirestore.instance
            .collection("groupChats")
            .doc(groupId)
            .collection("messages")
            .orderBy("timestamp", descending: true)
            .limit(1)
            .get();

        String lastMessage = "No messages yet";
        DateTime lastTimestamp = DateTime.now();
        String senderName = "System";

        if (messageSnapshot.docs.isNotEmpty) {
          var lastMessageDoc = messageSnapshot.docs.first;
          lastMessage = lastMessageDoc["text"] ?? "No messages yet";
          Timestamp? timestamp = lastMessageDoc["timestamp"];
          lastTimestamp = timestamp?.toDate() ?? DateTime.now();

          String senderId = lastMessageDoc["senderId"];
          if (senderId != "system") {
            // Fetch sender's name from users collection
            DocumentSnapshot senderDoc = await FirebaseFirestore.instance
                .collection("users")
                .doc(senderId)
                .get();

            if (senderDoc.exists) {
              // Fix: Access the "name" field instead of "lastMessageSender"
              senderName = (senderDoc.data() as Map<String, dynamic>)?["name"] ?? "Unknown";
            }
          }
        }

        Map<String, dynamic> groupData = {
          "groupId": groupId,
          "groupName": groupName,
          "groupImageUrl": groupImageUrl,
          "lastMessage": lastMessage,
          "lastTimestamp": lastTimestamp,
          "senderName": senderName,
          "isRead": true,
          "isOpened": _openedChats.contains(groupId),
        };

        updatedGroups.add(groupData);
      }

      // Sort groups by last message timestamp
      updatedGroups.sort((a, b) => b["lastTimestamp"].compareTo(a["lastTimestamp"]));

      setState(() {
        _groups = updatedGroups;
      });
    });
  }

  @override
  void dispose() {
    _channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _groups.isEmpty
        ? _buildEmptyGroupsUI()
        : ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            itemCount: _groups.length,
            itemBuilder: (context, index) {
              final group = _groups[index];
              return _buildGroupChatItem(context, group);
            },
          );
  }

  Widget _buildGroupChatItem(BuildContext context, Map<String, dynamic> group) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("groupChats")
          .doc(group["groupId"])
          .snapshots(),
      builder: (context, groupSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection("groupChats")
              .doc(group["groupId"])
              .collection("messages")
              .orderBy("timestamp", descending: true)
              .limit(1)
              .snapshots(),
          builder: (context, snapshot) {
            bool showNotificationBadge = false;
            
            if (snapshot.hasData && snapshot.data!.docs.isNotEmpty && 
                groupSnapshot.hasData && groupSnapshot.data!.exists) {
              var lastMessage = snapshot.data!.docs.first.data() as Map<String, dynamic>;
              var groupData = groupSnapshot.data!.data() as Map<String, dynamic>;
              
              // Check readBy status
              var messageReadBy = lastMessage['readBy'];
              var groupReadBy = groupData['readBy'];
              
              bool isMessageRead = false;
              bool isGroupRead = false;

              // Handle both List and Map types for readBy
              if (messageReadBy != null) {
                if (messageReadBy is List) {
                  isMessageRead = messageReadBy.contains(widget.userId);
                } else if (messageReadBy is Map) {
                  isMessageRead = messageReadBy[widget.userId] == true;
                }
              }

              if (groupReadBy != null) {
                if (groupReadBy is List) {
                  isGroupRead = groupReadBy.contains(widget.userId);
                } else if (groupReadBy is Map) {
                  isGroupRead = groupReadBy[widget.userId] == true;
                }
              }
              
              showNotificationBadge = !isMessageRead || !isGroupRead;
            }

            String formattedTime = _formatChatTime(group["lastTimestamp"]);
            
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _openGroupChat(context, group["groupId"], group["groupName"]),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.blueGrey[100],
                        backgroundImage: group["groupImageUrl"] != null &&
                                group["groupImageUrl"].toString().isNotEmpty
                            ? NetworkImage(group["groupImageUrl"])
                            : const AssetImage("assets/images/defaultGroupChat.png")
                                as ImageProvider,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    group["groupName"],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                Text(
                                  formattedTime,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: showNotificationBadge 
                                        ? Colors.deepPurple 
                                        : Colors.grey[500],
                                    fontWeight: showNotificationBadge 
                                        ? FontWeight.w500 
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (showNotificationBadge)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    "${group["senderName"]}: ${group["lastMessage"]}",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: showNotificationBadge
                                          ? Colors.black87
                                          : Colors.grey[600],
                                      fontWeight: showNotificationBadge
                                          ? FontWeight.w500
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyGroupsUI() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.group,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            "No group chats yet",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Create a group to chat with multiple friends",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  void _openGroupChat(BuildContext context, String groupId, String groupName) {
    // Mark chat as read when opening
    FirebaseFirestore.instance
        .collection("groupChats")
        .doc(groupId)
        .update({
          "readBy.${widget.userId}": true,
          "lastRead.${widget.userId}": Timestamp.now(),
        });

    // Mark all messages as read
    FirebaseFirestore.instance
        .collection("groupChats")
        .doc(groupId)
        .collection("messages")
        .where("readBy.${widget.userId}", isEqualTo: false)
        .get()
        .then((snapshot) {
          WriteBatch batch = FirebaseFirestore.instance.batch();
          
          for (var doc in snapshot.docs) {
            batch.update(doc.reference, {
              "readBy.${widget.userId}": true
            });
          }
          
          return batch.commit();
        });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupChat(groupId: groupId, groupName: groupName),
      ),
    );
  }

  String _formatChatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDate == today) {
      return DateFormat('HH:mm').format(dateTime); // 24-hour format
    } else if (messageDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM d, HH:mm')
          .format(dateTime); // Adds time to the date
    }
  }
}
