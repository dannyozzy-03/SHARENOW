import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:twitterr/screens/auth/main/profile/profile.dart';
import 'package:web_socket_channel/io.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:twitterr/services/notification_service.dart';

class PersonalChat extends StatefulWidget {
  final String receiverId;

  const PersonalChat({Key? key, required this.receiverId}) : super(key: key);

  @override
  _PersonalChatState createState() => _PersonalChatState();
}

class _PersonalChatState extends State<PersonalChat> {
  late IOWebSocketChannel channel;
  final TextEditingController messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  late String chatId;

  // Add these variables
  bool isInChat = false;
  bool isInForeground = true;

  @override
  void initState() {
    super.initState();
    chatId = getChatId(currentUserId, widget.receiverId);
    
    // Only mark this specific chat as active
    NotificationService.enterChat(chatId);
    
    // Set user as active in chat
    _updateUserChatStatus(true);
    
    // Mark all unread messages as read when entering chat
    _markAllMessagesAsRead();
    
    connectWebSocket();
  }

  // Add this method to update user's chat status
  void _updateUserChatStatus(bool status) {
    FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .update({
      'activeUsers.$currentUserId': status,
    });
  }

  // Add this new method
  void _markAllMessagesAsRead() {
    FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('sender', isEqualTo: widget.receiverId) // Only other user's messages
        .where('readBy', arrayContains: widget.receiverId) // Messages sent by other user
        .get()
        .then((messages) {
          WriteBatch batch = FirebaseFirestore.instance.batch();
          
          for (var message in messages.docs) {
            if (!(message.data()['readBy'] as List).contains(currentUserId)) {
              batch.update(message.reference, {
                'readBy': FieldValue.arrayUnion([currentUserId])
              });
            }
          }
          
          return batch.commit();
        });
        
    // Update chat document readBy status
    FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .update({
      'readBy.$currentUserId': true
    });
  }

  String getChatId(String user1, String user2) {
    List<String> sortedIds = [user1, user2]..sort();
    return "${sortedIds[0]}_${sortedIds[1]}";
  }

  void connectWebSocket() {
  final String serverUrl = "ws://192.168.0.15:3000";
  
  try {
    channel = IOWebSocketChannel.connect(Uri.parse(serverUrl));
    
    channel.sink.add(jsonEncode({
      "type": "register", 
      "userId": currentUserId,
      "chatId": chatId,
      "isActive": true
    }));

    channel.stream.listen((message) {
      Map<String, dynamic> decodedMessage = jsonDecode(message);
      if (decodedMessage['receiver'] == currentUserId &&
          decodedMessage['sender'] == widget.receiverId) {
        
        String messageId = decodedMessage['messageId'] ?? 
            '${decodedMessage['sender']}_${DateTime.now().millisecondsSinceEpoch}';

        FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .get()
            .then((chatDoc) {
          Map<String, dynamic> activeUsers = 
              chatDoc.data()?['activeUsers'] ?? {};
          
          bool isReceiverActive = activeUsers[currentUserId] ?? false;
          bool isSenderActive = activeUsers[widget.receiverId] ?? false;

          // Add message to messages collection
          FirebaseFirestore.instance
              .collection('chats')
              .doc(chatId)
              .collection('messages')
              .add({
            'sender': decodedMessage['sender'],
            'text': decodedMessage['text'],
            'timestamp': Timestamp.now(),
            'messageId': messageId,
            'readBy': isReceiverActive 
                ? [decodedMessage['sender'], currentUserId]
                : [decodedMessage['sender']],
          });

          // Update chat document
          Map<String, dynamic> readByMap = 
              chatDoc.data()?['readBy'] ?? {};
          
          readByMap[widget.receiverId] = isSenderActive;
          readByMap[currentUserId] = isReceiverActive;

          FirebaseFirestore.instance
              .collection('chats')
              .doc(chatId)
              .update({
            'lastMessage': decodedMessage['text'],
            'lastTimestamp': Timestamp.now(),
            'readBy': readByMap,
          });
        });
      }
    });
  } catch (e) {
    print('Connection Error: $e');
  }
}

  void sendMessage() {
    if (messageController.text.isNotEmpty) {
      String text = messageController.text.trim();
      messageController.clear();

      Map<String, dynamic> messageData = {
        'type': 'message',
        'sender': currentUserId,
        'receiver': widget.receiverId,
        'text': text,
        'timestamp': Timestamp.now().toDate().toIso8601String(),
      };

      channel.sink.add(jsonEncode(messageData));

      // Check active users before sending message
      FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .get()
          .then((chatDoc) {
        Map<String, dynamic> activeUsers = 
            chatDoc.data()?['activeUsers'] ?? {};
        
        bool isSenderActive = activeUsers[currentUserId] ?? false;
        bool isReceiverActive = activeUsers[widget.receiverId] ?? false;

        // Add message with appropriate readBy status
        FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .add({
          'sender': currentUserId,
          'text': text,
          'timestamp': Timestamp.now(),
          'readBy': isReceiverActive 
              ? [currentUserId, widget.receiverId]
              : [currentUserId],
        });

        // Update chat document with readBy status based on activeUsers
        Map<String, dynamic> readByMap = 
            chatDoc.data()?['readBy'] ?? {};
        
        readByMap[currentUserId] = isSenderActive; // Sender's read status
        readByMap[widget.receiverId] = isReceiverActive; // Receiver's read status

        FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .set({
          'participants': [currentUserId, widget.receiverId],
          'lastMessage': text,
          'lastTimestamp': Timestamp.now(),
          'readBy': readByMap,
        }, SetOptions(merge: true));
      });

      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.minScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    // Reset unread count when leaving chat
    FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .update({
          "unreadCount.$currentUserId": 0,
          "activeUsers.$currentUserId": false,
        });

    NotificationService.leaveChat(chatId);
    channel.sink.close();
    messageController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Color(0xFFF5F7FB),
        appBar: _buildAppBar(),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: _buildChatMessages()),
              _buildMessageInput(),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
  return AppBar(
    title: FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.receiverId)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Text("Loading...");
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Text("Unknown User");
        }
        var userData = snapshot.data!.data() as Map<String, dynamic>;

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => Profile(id: widget.receiverId),
              ),
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                backgroundColor: Colors.blueGrey[100],
                radius: 18,
                child: userData['profileImageUrl'] != null
                    ? ClipOval(
                        child: Image.network(
                          userData['profileImageUrl'],
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Text(
                              (userData['name'] ?? "?")[0].toUpperCase(),
                              style: TextStyle(
                                color: Colors.blueGrey[800],
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                      )
                    : Text(
                        (userData['name'] ?? "?")[0].toUpperCase(),
                        style: TextStyle(
                          color: Colors.blueGrey[800],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  userData['name'] ?? "Unknown User",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.blueGrey[800],
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        );
      },
    ),
    actions: [
      IconButton(
        icon: Icon(Icons.call, color: Colors.blueGrey[700]),
        onPressed: () {},
      ),
    ],
    centerTitle: false,
    elevation: 0,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        bottom: Radius.circular(16),
      ),
    ),
  );
}

  Widget _buildChatMessages() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
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

        List<QueryDocumentSnapshot> docs = snapshot.data!.docs;

        return ListView.builder(
          controller: _scrollController,
          reverse: true,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final message = docs[index];
            bool isMe = message['sender'] == currentUserId;
            bool isLastMessage = index == 0; // Check if this is the last message

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(chatId)
                  .get(),
              builder: (context, chatSnapshot) {
                bool receiverReadStatus = false;
                if (chatSnapshot.hasData && chatSnapshot.data!.exists) {
                  var readByMap = chatSnapshot.data!.get('readBy') as Map<String, dynamic>?;
                  receiverReadStatus = readByMap?[widget.receiverId] ?? false;
                }

                Timestamp timestamp = message['timestamp'];
                String formattedTime =
                    DateFormat('hh:mm a').format(timestamp.toDate());

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Align(
                        alignment:
                            isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isMe ? Color(0xFF4E8BF0) : Colors.white,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(18),
                                topRight: Radius.circular(18),
                                bottomLeft:
                                    isMe ? Radius.circular(18) : Radius.circular(4),
                                bottomRight:
                                    isMe ? Radius.circular(4) : Radius.circular(18),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                )
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: isMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message['text'],
                                  style: TextStyle(
                                    color:
                                        isMe ? Colors.white : Colors.blueGrey[800],
                                    fontSize: 16,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      formattedTime,
                                      style: TextStyle(
                                        color: isMe
                                            ? Colors.white.withOpacity(0.8)
                                            : Colors.blueGrey[400],
                                        fontSize: 11,
                                      ),
                                    ),
                                    if (isMe) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        // Check readBy array for each message
                                        (message['readBy'] as List).contains(widget.receiverId)
                                            ? Icons.done_all  // Double blue tick when message is read
                                            : Icons.check,    // Single grey tick when message is unread
                                        size: 14,
                                        color: (message['readBy'] as List).contains(widget.receiverId)
                                            ? Colors.blue[300]           // Blue for read messages
                                            : Colors.white.withOpacity(0.6), // Grey for unread
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
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
                controller: messageController,
                focusNode: _focusNode,
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
                onSubmitted: (_) => sendMessage(),
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
              onPressed: sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
