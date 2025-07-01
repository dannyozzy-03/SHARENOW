import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Add a Set to track processed message IDs
  static final Set<String> _processedMessageIds = {};
  // Add static set to track active chats
  static final Set<String> activeChats = {};

  // Initialize FCM and request permissions
  static Future<void> initNotifications() async {
    // Initialize local notifications
    const AndroidInitializationSettings androidSettings = 
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications.initialize(initSettings,
        onDidReceiveNotificationResponse: (details) {
          if (details.payload != null) {
            final String payload = details.payload!;
            if (payload.startsWith('group_chat_')) {
              final String groupId = payload.substring('group_chat_'.length);
              // Navigate to group chat
            }
          }
        },
    );

    try {
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        String? token = await _messaging.getToken();
        if (token != null) {
          print("FCM Token: $token");
          await saveFcmToken(token);
        }

        _messaging.onTokenRefresh.listen((newToken) {
          saveFcmToken(newToken);
        });

        // Handle foreground messages
        FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
          print("Foreground: Received message: ${message.messageId}");
          
          String chatId = message.data['chatId'] ?? '';
          String messageId = message.messageId ?? 
              '${message.data['senderId']}_${DateTime.now().millisecondsSinceEpoch}';
          
          // Show notification even when app is in foreground
          await showMessageNotification(
            senderId: message.data['senderId'] ?? '',
            message: message.notification?.body ?? '',
            chatId: chatId,
            messageId: messageId,
          );
        });
      }
    } catch (e) {
      print("Error initializing notifications: $e");
    }

    // Create group messages channel
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'group_messages_channel',
            'Group Messages',
            description: 'Notifications for group messages',
            importance: Importance.high,
            enableVibration: true,
            playSound: true,
          ),
        );

    // Create high importance channel for class notifications
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'high_importance_channel',
            'High Importance Notifications',
            description: 'Used for important notifications.',
            importance: Importance.max,
            enableVibration: true,
            playSound: true,
            showBadge: true,
          ),
        );
  }

  // Save FCM token to Firestore
  static Future<void> saveFcmToken(String token) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).update({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      });
    }
  }

  // Add methods to manage active chats
  static void enterChat(String chatId) {
    activeChats.add(chatId);
  }

  static void leaveChat(String chatId) {
    activeChats.remove(chatId);
  }

  // Add this new method
  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    String messageId = message.messageId ?? 
        '${message.data['senderId']}_${DateTime.now().millisecondsSinceEpoch}';
    
    // Check if message was already processed
    if (_isMessageProcessed(messageId)) {
      print("Background: Skipping duplicate message: $messageId");
      return;
    }

    String chatId = message.data['chatId'] ?? '';
    
    // Don't show notification if chat is active
    if (activeChats.contains(chatId)) {
      print("Background: Skipping notification for active chat: $chatId");
      return;
    }

    await showMessageNotification(
      senderId: message.data['senderId'] ?? '',
      message: message.notification?.body ?? '',
      chatId: chatId,
      messageId: messageId,
    );
  }

  static bool _isMessageProcessed(String messageId) {
    if (_processedMessageIds.contains(messageId)) {
      print("Message already processed: $messageId");
      return true;
    }
    print("Processing new message: $messageId");
    _processedMessageIds.add(messageId);
    
    // Clean up old message IDs after 1 minute (reduced from 5 minutes)
    Future.delayed(const Duration(minutes: 1), () {
      _processedMessageIds.remove(messageId);
      print("Removed message ID from tracking: $messageId");
    });
    
    return false;
  }

  // Update the showMessageNotification method
  static Future<void> showMessageNotification({
    required String senderId,
    required String message,
    required String chatId,
    String? messageId,
    bool isGroupChat = false,
    String? groupName,
    String? senderName,
  }) async {
    final String actualMessageId = messageId ?? 
        '${senderId}_${DateTime.now().millisecondsSinceEpoch}';

    if (_isMessageProcessed(actualMessageId)) return;
    if (activeChats.contains(chatId)) return;

    try {
      // Only fetch sender name if not provided
      if (senderName == null) {
        DocumentSnapshot senderDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(senderId)
            .get();

        if (senderDoc.exists) {
          senderName = (senderDoc.data() as Map<String, dynamic>)['name'] ?? 'Unknown';
        }
      }

      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        isGroupChat ? 'group_messages_channel' : 'messages_channel',
        isGroupChat ? 'Group Messages' : 'Messages',
        channelDescription: isGroupChat 
            ? 'Notifications for group messages' 
            : 'Notifications for new messages',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        groupKey: chatId,
        setAsGroupSummary: false,
      );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: chatId,
      );

      final NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Format title and body consistently
      String title = isGroupChat ? (groupName ?? 'Group Chat') : (senderName ?? 'New Message');
      String body = '$senderName: $message';  // Single format for message body

      String payload = isGroupChat ? 'group_chat_$chatId' : 'personal_chat_$senderId';

      await _notifications.show(
        actualMessageId.hashCode,
        title,
        body,
        platformDetails,
        payload: payload,
      );
    } catch (e) {
      print("Error showing notification: $e");
    }
  }

  // Add this static method outside the class
  @pragma('vm:entry-point')
  static Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    // Initialize Firebase if needed
    await Firebase.initializeApp();
    
    await showMessageNotification(
      senderId: message.data['senderId'] ?? '',
      message: message.notification?.body ?? '',
      chatId: message.data['chatId'] ?? '',
    );
  }

  // Add this static method to the NotificationService class
  static Future<void> sendNotification({
    required String token,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'token': token,
        'notification': {
          'title': title,
          'body': body,
        },
        'data': data,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error sending notification: $e');
    }
  }

  // Add this method to NotificationService class
  static Future<void> showClassNotification({
    required String title,
    required String body,
    required String classId,
  }) async {
    try {
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'high_importance_channel',
        'High Importance Notifications',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        channelShowBadge: true,
      );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        DateTime.now().millisecond,
        title,
        body,
        platformDetails,
        payload: 'class_$classId',
      );
    } catch (e) {
      print('Error showing class notification: $e');
    }
  }
}