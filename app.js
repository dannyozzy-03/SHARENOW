const WebSocket = require("ws");
const express = require("express");
const http = require("http");
const cors = require("cors");
const admin = require("firebase-admin");

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// Middleware
app.use(cors());
app.use(express.json());

// Initialize Firebase Admin
try {
    let firebaseConfig;
    
    // Check if we're in production and have environment variables
    if (process.env.NODE_ENV === 'production' && process.env.FIREBASE_PROJECT_ID) {
        console.log('🔥 Initializing Firebase with environment variables');
        console.log('📋 Project ID:', process.env.FIREBASE_PROJECT_ID);
        console.log('📧 Client Email:', process.env.FIREBASE_CLIENT_EMAIL);
        console.log('🔑 Private Key Length:', process.env.FIREBASE_PRIVATE_KEY ? process.env.FIREBASE_PRIVATE_KEY.length : 0);
        
        firebaseConfig = {
            credential: admin.credential.cert({
                projectId: process.env.FIREBASE_PROJECT_ID,
                clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
                privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n')
            })
        };
    } else {
        console.log('🔥 Initializing Firebase with service account file');
        firebaseConfig = {
            credential: admin.credential.cert(require("./serviceAccountKey.json"))
        };
    }
    
    admin.initializeApp(firebaseConfig);
    console.log("✅ Firebase initialized successfully");
} catch (error) {
    console.error("❌ Error initializing Firebase:", error.message);
    console.error("Full error:", error);
    process.exit(1);
}

const firestore = admin.firestore();
const clients = new Map();
let lastSentPostId = null;

// ========== WEBSOCKET FUNCTIONALITY ==========
wss.on("connection", (ws, req) => {
    const userId = req.url.split("=")[1];
    console.log(`👤 New WebSocket connection: ${userId}`);
    
    ws.on("message", async (message) => {
        const data = JSON.parse(message);

        if (data.type === "register") {
            clients.set(data.userId, ws);
            ws.userId = data.userId;
            console.log(`📝 User registered: ${data.userId}`);
        }
        
        else if (data.type === "message") {
            try {
                if (!data.sender || !data.receiver) {
                    console.error("Missing sender or receiver ID");
                    return;
                }

                const messageId = `${data.sender}_${Date.now()}`;
                const messageData = { ...data, messageId: messageId };
                
                const receiverWs = clients.get(data.receiver);
                
                // Forward message to connected receiver
                if (receiverWs && receiverWs.readyState === WebSocket.OPEN) {
                    receiverWs.send(JSON.stringify(messageData));
                }
                
                // Send FCM notification if receiver not connected
                if (!receiverWs || receiverWs.readyState !== WebSocket.OPEN) {
                    const receiverDoc = await firestore.collection("users").doc(data.receiver).get();
                    
                    if (receiverDoc.exists) {
                        const fcmToken = receiverDoc.data().fcmToken;
                        
                        if (fcmToken) {
                            const senderDoc = await firestore.collection("users").doc(data.sender).get();
                            const senderName = senderDoc.exists ? senderDoc.data().name : "Unknown";

                            const message = {
                                token: fcmToken,
                                notification: { title: senderName, body: data.text },
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
                                        sound: "default"
                                    }
                                }
                            };

                            try {
                                await admin.messaging().send(message);
                            } catch (notificationError) {
                                if (notificationError.code === 'messaging/registration-token-not-registered') {
                                    await firestore.collection("users").doc(data.receiver).update({
                                        fcmToken: admin.firestore.FieldValue.delete()
                                    });
                                }
                            }
                        }
                    }

                    // Update unread count
                    const chatId = `${[data.sender, data.receiver].sort().join('_')}`;
                    if (chatId) {
                        const chatDoc = await firestore.collection("chats").doc(chatId).get();
                        const activeUsers = chatDoc.exists ? (chatDoc.data()?.activeUsers || {}) : {};
                        const isReceiverActive = activeUsers[data.receiver];

                        if (!isReceiverActive) {
                            await firestore.collection("chats").doc(chatId).update({
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
            const groupRef = await firestore.collection("groupChats").add({
                groupName: data.groupName,
                members: data.members,
                lastMessage: "",
                lastTimestamp: admin.firestore.Timestamp.now(),
            });

            data.members.forEach((memberId) => {
                if (clients.get(memberId)) {
                    clients.get(memberId).send(JSON.stringify({
                        type: "newGroup",
                        groupId: groupRef.id,
                        groupName: data.groupName,
                    }));
                }
            });
        }
        
        else if (data.type === "groupMessage") {
            try {
                if (!data.fcmToken || !data.groupName || !data.senderName) {
                    console.error("Missing required fields:", data);
                    return;
                }

                const message = {
                    token: data.fcmToken,
                    notification: {
                        title: data.groupName,
                        body: `${data.senderName}: ${data.body}`,
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
                            defaultSound: true
                        }
                    }
                };

                await admin.messaging().send(message);
            } catch (error) {
                console.error("Error processing group message:", error);
            }
        }
    });

    ws.on("close", () => {
        if (ws.userId) {
            clients.delete(ws.userId);
            console.log(`👋 User disconnected: ${ws.userId}`);
        }
    });
});

// ========== REST API FUNCTIONALITY ==========

// Notification handling
async function handleClassNotification(notificationDoc) {
    try {
        const notification = notificationDoc.data();
        
        if (!notification.token) {
            console.error('Missing FCM token in notification');
            await notificationDoc.ref.delete();
            return;
        }

        const message = {
            token: notification.token,
            notification: {
                title: notification.notification.title,
                body: notification.notification.body,
            },
            data: notification.data,
            android: {
                notification: {
                    clickAction: 'FLUTTER_NOTIFICATION_CLICK',
                    channelId: 'high_importance_channel',
                    priority: 'high',
                },
                priority: 'high',
            }
        };

        const response = await admin.messaging().send(message);
        await notificationDoc.ref.delete();
        return response;
    } catch (error) {
        console.error('Error in handleClassNotification:', error);
    }
}

// Notification listener
firestore.collection('notifications').onSnapshot((snapshot) => {
    snapshot.docChanges().forEach(async (change) => {
        if (change.type === 'added') {
            try {
                await handleClassNotification(change.doc);
            } catch (error) {
                console.error('Error processing notification:', error);
            }
        }
    });
});

// Server-Sent Events endpoint
app.get("/events", async (req, res) => {
    res.setHeader("Content-Type", "text/event-stream");
    res.setHeader("Cache-Control", "no-cache");
    res.setHeader("Connection", "keep-alive");

    const postsCollection = firestore.collection("admin_posts");

    try {
        const snapshot = await postsCollection.orderBy("timestamp", "desc").get();
        if (!snapshot.empty) {
            snapshot.docs.forEach((doc) => {
                const data = doc.data();
                res.write(`data: ${JSON.stringify({
                    message: data.text,
                    adminEmail: data.email,
                    timestamp: data.timestamp ? data.timestamp.toDate().toISOString() : new Date().toISOString(),
                    imageUrl: data.imageUrl || null,
                    category: data.category || "General"
                })}\n\n`);
            });
            lastSentPostId = snapshot.docs[0].id; 
        }
    } catch (error) {
        console.error("Error fetching initial posts:", error);
    }

    const unsubscribe = postsCollection.orderBy("timestamp", "desc").limit(1).onSnapshot((snapshot) => {
        if (snapshot.empty) return;

        const latestDoc = snapshot.docs[0];
        if (lastSentPostId === latestDoc.id) return; 

        lastSentPostId = latestDoc.id;
        const latestPost = latestDoc.data();
        
        res.write(`data: ${JSON.stringify({
            message: latestPost.text,
            adminEmail: latestPost.email,
            timestamp: latestPost.timestamp ? latestPost.timestamp.toDate().toISOString() : new Date().toISOString(),
            imageUrl: latestPost.imageUrl || null,
            category: latestPost.category || "General"
        })}\n\n`);
    });

    req.on("close", () => {
        unsubscribe();
        res.end();
    });
});

// Admin post endpoint - YOUR MAIN ENDPOINT!
app.post("/admin/post", async (req, res) => {
    try {
        const { text, adminEmail, imageUrl, category } = req.body;

        if (!text || !adminEmail) {
            return res.status(400).json({ error: "Missing text or adminEmail" });
        }

        const newPostRef = await firestore.collection("admin_posts").add({
            text,
            email: adminEmail,
            imageUrl: imageUrl || null,
            category: category || "General",
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`📝 New Admin Post: ${text} from ${adminEmail}`);
        res.status(200).json({ success: true, id: newPostRef.id });

    } catch (error) {
        console.error("Error adding post:", error);
        res.status(500).json({ error: "Failed to add post" });
    }
});

// Health check endpoint
app.get("/health", (req, res) => {
    res.json({ 
        status: "healthy", 
        timestamp: new Date().toISOString(),
        websocket_clients: clients.size,
        service: "Twitter Clone Backend"
    });
});

// Root endpoint
app.get("/", (req, res) => {
    res.json({
        message: "🚀 Twitter Clone Backend is running!",
        endpoints: {
            health: "/health",
            admin_post: "/admin/post",
            events: "/events",
            websocket: "Connect to this same URL with WebSocket"
        }
    });
});

// Start server
const PORT = process.env.PORT || 4000;
console.log('🚀 Starting server...');
console.log('📍 Environment:', process.env.NODE_ENV || 'development');
console.log('🔌 Port:', PORT);
console.log('🌐 Host: 0.0.0.0');

server.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Server running on http://0.0.0.0:${PORT}`);
    console.log(`📡 WebSocket: ws://0.0.0.0:${PORT}`);
    console.log(`🌐 Admin Post: http://0.0.0.0:${PORT}/admin/post`);
    console.log(`📊 Health: http://0.0.0.0:${PORT}/health`);
    console.log(`📡 Events: http://0.0.0.0:${PORT}/events`);
    console.log(`🎯 Ready for Render deployment!`);
}).on('error', (err) => {
    console.error('❌ Server startup error:', err);
    process.exit(1);
}); 