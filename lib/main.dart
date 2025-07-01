import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:twitterr/models/user.dart';
import 'package:twitterr/screens/auth/chat/groupChat.dart';
import 'package:twitterr/screens/auth/chat/personalChat.dart';
import 'package:twitterr/screens/auth/home/search.dart';
import 'package:twitterr/screens/auth/main/home.dart';
import 'package:twitterr/screens/auth/main/posts/add.dart';
import 'package:twitterr/screens/auth/main/profile/edit.dart';
import 'package:twitterr/screens/auth/main/profile/profile.dart';
import 'package:twitterr/screens/auth/submission/class.dart';
import 'package:twitterr/screens/auth/submission/classwork.dart';
import 'package:twitterr/screens/auth/submission/participants.dart';
import 'package:twitterr/screens/auth/submission/submission.dart';
import 'package:twitterr/screens/auth/wrapper.dart';
import 'package:twitterr/services/auth.dart';
import 'package:twitterr/services/login.dart';
import 'package:twitterr/services/register.dart';
import 'package:twitterr/services/user.dart';
import 'package:twitterr/services/auto_logout_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:twitterr/services/notification_service.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> requestNotificationPermissions() async {
  // For Android 13+ (API 33), use flutter_local_notifications' static method
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestPermission();
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Only initialize Firebase if needed
  if (!Firebase.apps.isNotEmpty) {
    await Firebase.initializeApp();
  }
  
  // Let NotificationService handle the notification
  await NotificationService.handleBackgroundMessage(message);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    
    // Set background handler first
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    
    // Initialize notifications
    await NotificationService.initNotifications();

    // Add foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message in the foreground!');
      print('Message data: ${message.data}');
      print('Message notification: ${message.notification}');

      if (message.notification != null) {
        // Show local notification
        NotificationService.showMessageNotification(
          senderId: message.data['senderId'] ?? '',
          message: message.notification!.body ?? '',
          chatId: message.data['classId'] ?? '',
          messageId: message.messageId,
          senderName: message.notification!.title,
        );
      }
    });

    // Request notification permissions
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

  } catch (e) {
    debugPrint("Initialization error: $e");
  }

  runApp(const MyApp());
}

// Add this helper function to show notifications
Future<void> showNotification({
  required String title,
  required String body,
  String? payload,
}) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'messages_channel',
    'Messages',
    channelDescription: 'Notifications for new messages',
    importance: Importance.high,
    priority: Priority.high,
    showWhen: true,
  );

  const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  const NotificationDetails platformDetails = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  await flutterLocalNotificationsPlugin.show(
    0,
    title,
    body,
    platformDetails,
    payload: payload,
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamProvider<UserModel?>.value(
      value: AuthService().user,
      initialData: null,
      catchError: (_, __) => null,
      child: MaterialApp(
        title: 'ShareNow',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const AuthWrapper(),
        routes: {
          '/home': (context) => const Home(),
          '/submission': (context) => const Submission(),
          '/class': (context) {
            final args = ModalRoute.of(context)?.settings.arguments as Map<String, String>?;
            if (args != null && args.containsKey('classId') && args.containsKey('className')) {
              return ClassPage(classId: args['classId']!, className: args['className']!);
            } else {
              return const Scaffold(
                body: Center(child: Text("Invalid class details")),
              );
            }
          },
          '/classwork': (context) {
            final args = ModalRoute.of(context)?.settings.arguments as Map<String, String>?;
            if (args != null && args.containsKey('classId') && args.containsKey('className')) {
              return Classwork(classId: args['classId']!, className: args['className']!);
            } else {
              return const Scaffold(
                body: Center(child: Text("Invalid class details")),
              );
            }
          },
          '/participants': (context) {
            final args = ModalRoute.of(context)?.settings.arguments as Map<String, String>?;
            if (args != null && args.containsKey('classId') && args.containsKey('className')) {
              return Participants(classId: args['classId']!, className: args['className']!);
            } else {
              return const Scaffold(
                body: Center(child: Text("Invalid class details")),
              );
            }
          },
          '/login': (context) => const Login(),
          '/register': (context) => const Register(),
          '/add': (context) => const Add(),
          '/profile': (context) => const Profile(),
          '/edit': (context) => const Edit(),
          '/search': (context) => const Search(),
          '/chat': (context) {
            final args = ModalRoute.of(context)?.settings.arguments;
            if (args is String) {
              return PersonalChat(receiverId: args);
            } else {
              return const Scaffold(
                body: Center(child: Text("Invalid chat user ID")),
              );
            }
          },
          '/groupChat': (context) {
            final args = ModalRoute.of(context)?.settings.arguments;
            if (args is Map<String, dynamic> &&
                args.containsKey('groupId') &&
                args.containsKey('groupName')) {
              return GroupChat(
                groupId: args['groupId'],
                groupName: args['groupName'],
              );
            } else {
              return const Scaffold(
                body: Center(child: Text("Invalid group chat details")),
              );
            }
          },
        },
        onGenerateRoute: (settings) {
          // Handle notification payloads
          if (settings.name == '/fromNotification') {
            final payload = settings.arguments as String?;
            if (payload != null) {
              if (payload.startsWith('personal_chat_')) {
                final userId = payload.substring('personal_chat_'.length);
                return MaterialPageRoute(
                  builder: (_) => PersonalChat(receiverId: userId),
                );
              } else if (payload.startsWith('group_chat_')) {
                final groupId = payload.substring('group_chat_'.length);
                // You'll need to fetch the group name from Firestore
                return MaterialPageRoute(
                  builder: (_) => FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('groupChats')
                        .doc(groupId)
                        .get(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return GroupChat(
                          groupId: groupId,
                          groupName: snapshot.data!['groupName'],
                        );
                      }
                      return const Center(child: CircularProgressIndicator());
                    },
                  ),
                );
              }
            }
          }
          return null;
        },
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  _AuthWrapperState createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return StreamProvider<UserModel?>.value(
            value: UserService().getUserInfo(snapshot.data!.uid),
            initialData: null,
            catchError: (_, __) => null,
            child: const AutoLogoutWrapper(
              child: Home(),
            ),
          );
        } else {
          return const Wrapper();
        }
      },
    );
  }
}
