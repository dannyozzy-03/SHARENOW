const WebSocket = require("ws");
const express = require("express");
const http = require("http");
const admin = require("firebase-admin");

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

admin.initializeApp({
    credential: admin.credential.cert(require("./serviceAccountKey.json")),
});

const firestore = admin.firestore();
const clients = new Map(); // Changed from object to Map for better handling

// WebSocket connection
wss.on("connection", (ws, req) => {
    const userId = req.url.split("=")[1]; // Extract user ID from URL
    
    ws.on("message", async (message) => {
        const data = JSON.parse(message);

        if (data.type === "register") {
            clients.set(data.userId, ws);
            ws.userId = data.userId;
        }
        
        // Inside the message handling section
else if (data.type === "message") {
    try {
        // Validate required fields
        if (!data.sender || !data.receiver) {
            console.error("Missing sender or receiver ID");
            return;
        }

        const messageId = `${data.sender}_${Date.now()}`;
        const messageData = {
            ...data,
            messageId: messageId
        };
        
        const receiverWs = clients.get(data.receiver);
        
        // Forward message to connected receiver
        if (receiverWs && receiverWs.readyState === WebSocket.OPEN) {
            receiverWs.send(JSON.stringify(messageData));
        }
        
        // If receiver is not connected or socket isn't open, send FCM notification
        if (!receiverWs || receiverWs.readyState !== WebSocket.OPEN) {
            const receiverDoc = await firestore
                .collection("users")
                .doc(data.receiver)
                .get();
            
            if (receiverDoc.exists) {
                const fcmToken = receiverDoc.data().fcmToken;
                
                if (fcmToken) {
                    const senderDoc = await firestore
                        .collection("users")
                        .doc(data.sender)
                        .get();
                    
                    const senderName = senderDoc.exists 
                        ? senderDoc.data().name 
                        : "Unknown";

                    const message = {
                        token: fcmToken,
                        notification: {
                            title: senderName,
                            body: data.text
                        },
                        data: {
                            senderId: data.sender,
                            chatId: `${[data.sender, data.receiver].sort().join('_')}`,
                            messageId: messageId,
                            messageType: "chat",
                            click_action: "FLUTTER_NOTIFICATION_CLICK"
                        },
                        android: {
                            priority: "high",
                            notification: {
                                channel_id: "messages_channel",
                                priority: "high",
                                sound: "default",
                                default_sound: true,
                                default_vibrate_timings: true,
                            }
                        }
                    };

                    try {
                        await admin.messaging().send(message);
                    } catch (notificationError) {
                        if (notificationError.code === 'messaging/registration-token-not-registered') {
                            console.log(`Invalid FCM token for user ${data.receiver}, removing token...`);
                            await firestore
                                .collection("users")
                                .doc(data.receiver)
                                .update({
                                    fcmToken: admin.firestore.FieldValue.delete()
                                });
                        } else {
                            console.error("Error sending notification:", notificationError);
                        }
                    }
                }
            }

            // Generate chat ID consistently
            const chatId = `${[data.sender, data.receiver].sort().join('_')}`;

            // Update unread count only if chat ID is valid
            if (chatId) {
                const chatDoc = await firestore
                    .collection("chats")
                    .doc(chatId)
                    .get();

                const activeUsers = chatDoc.exists ? (chatDoc.data()?.activeUsers || {}) : {};
                const isReceiverActive = activeUsers[data.receiver];

                if (!isReceiverActive) {
                    await firestore
                        .collection("chats")
                        .doc(chatId)
                        .update({
                            [`unreadCount.${data.receiver}`]: admin.firestore.FieldValue.increment(1)
                        });
                }
            }
        }
    } catch (error) {
        console.error("Error processing personal message:", error);
    }
}
        
        else if (data.type === "createGroup") {
            // Add group to Firestore
            const groupRef = await firestore.collection("groupChats").add({
                groupName: data.groupName,
                members: data.members,
                lastMessage: "",
                lastTimestamp: admin.firestore.Timestamp.now(),
            });

            // Notify all members about new group
            data.members.forEach((memberId) => {
                if (clients.get(memberId)) {
                    clients.get(memberId).send(
                        JSON.stringify({
                            type: "newGroup",
                            groupId: groupRef.id,
                            groupName: data.groupName,
                        })
                    );
                }
            });
        }
        // Inside the message handling section, add this condition
else if (data.type === "groupMessage") {
    try {
        console.log("Processing group message:", data);

        // Validate required fields
        if (!data.fcmToken || !data.groupName || !data.senderName) {
            console.error("Missing required fields:", data);
            return;
        }

        const message = {
            token: data.fcmToken,
            notification: {
                title: data.groupName,           // Group name as title
                body: `${data.senderName}: ${data.body}`,  // Sender and message
            },
            data: {
                senderId: data.senderId,
                groupId: data.groupId,
                messageId: data.messageId,
                messageType: "groupChat",
                groupName: data.groupName,
                senderName: data.senderName,
                messageText: data.body,
                click_action: "FLUTTER_NOTIFICATION_CLICK"
            },
            android: {
                priority: "high",
                notification: {
                    channelId: "group_messages_channel",
                    priority: "high",
                    defaultSound: true,
                    defaultVibrateTimings: true,
                    notificationCount: 1
                }
            },
            apns: {
                headers: {
                    'apns-priority': '10',
                },
                payload: {
                    aps: {
                        alert: {
                            title: data.groupName,
                            body: `${data.senderName}: ${data.body}` // Single format for iOS
                        },
                        sound: 'default',
                        badge: 1,
                        'thread-id': data.groupId
                    }
                }
            }
        };

        try {
            const response = await admin.messaging().send(message);
            console.log("Successfully sent group message notification:", response);
        } catch (notificationError) {
            if (notificationError.code === 'messaging/registration-token-not-registered') {
                console.log(`Invalid FCM token for user ${data.receiverId}, removing token...`);
                if (data.receiverId) {
                    const userRef = firestore.collection("users").doc(data.receiverId);
                    await userRef.update({
                        fcmToken: admin.firestore.FieldValue.delete()
                    });
                }
            } else {
                console.error("Error sending group notification:", notificationError);
            }
        }
    } catch (error) {
        console.error("Error processing group message:", error);
    }
}
    });

    ws.on("close", () => {
        if (ws.userId) {
            clients.delete(ws.userId);
        }
    });
});

// Update the server.listen call
server.listen(3000, '0.0.0.0', () => {
  console.log('WebSocket server running on ws://0.0.0.0:3000');
});
