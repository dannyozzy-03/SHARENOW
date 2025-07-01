const WebSocket = require("ws");
const express = require("express");
const http = require("http");
const cors = require("cors");
const admin = require("firebase-admin");

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// Middleware
app.use(cors({
    origin: '*', // Allow all origins for development - you can restrict this in production
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'Cache-Control'],
    credentials: false // EventSource doesn't support credentials
}));
app.use(express.json());

// Additional CORS headers for EventSource specifically
app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization, Cache-Control');
    res.header('Access-Control-Expose-Headers', 'Content-Type');
    
    // Handle preflight requests
    if (req.method === 'OPTIONS') {
        res.sendStatus(200);
    } else {
        next();
    }
});

// Helper function to format private key properly
function formatPrivateKey(key) {
    if (!key) return null;
    
    console.log('🔍 Raw key first 100 chars:', key.substring(0, 100));
    console.log('🔍 Raw key last 100 chars:', key.substring(key.length - 100));
    
    // Remove any extra whitespace and quotes
    let cleanKey = key.trim().replace(/^["']|["']$/g, '');
    
    // Replace escaped newlines with actual newlines
    cleanKey = cleanKey.replace(/\\n/g, '\n');
    
    // Also handle case where newlines might be missing entirely
    if (!cleanKey.includes('\n')) {
        // If no newlines found, try to add them at proper positions
        cleanKey = cleanKey.replace(/-----BEGIN PRIVATE KEY-----/, '-----BEGIN PRIVATE KEY-----\n');
        cleanKey = cleanKey.replace(/-----END PRIVATE KEY-----/, '\n-----END PRIVATE KEY-----');
    }
    
    console.log('🔍 After \\n replacement first 100 chars:', cleanKey.substring(0, 100));
    console.log('🔍 After \\n replacement last 100 chars:', cleanKey.substring(cleanKey.length - 100));
    
    // Validate key structure
    if (!cleanKey.includes('-----BEGIN PRIVATE KEY-----')) {
        console.error('❌ Key missing BEGIN marker');
        return null;
    }
    
    if (!cleanKey.includes('-----END PRIVATE KEY-----')) {
        console.error('❌ Key missing END marker');
        return null;
    }
    
    // Extract the key content between markers
    const beginMarker = '-----BEGIN PRIVATE KEY-----';
    const endMarker = '-----END PRIVATE KEY-----';
    
    const beginIndex = cleanKey.indexOf(beginMarker);
    const endIndex = cleanKey.indexOf(endMarker);
    
    if (beginIndex === -1 || endIndex === -1) {
        console.error('❌ Invalid key structure');
        return null;
    }
    
    // Reconstruct the key properly
    const keyContent = cleanKey.substring(beginIndex + beginMarker.length, endIndex).trim();
    const reconstructedKey = `${beginMarker}\n${keyContent}\n${endMarker}`;
    
    console.log('🔍 Reconstructed key first 100 chars:', reconstructedKey.substring(0, 100));
    console.log('🔍 Reconstructed key last 100 chars:', reconstructedKey.substring(reconstructedKey.length - 100));
    
    return reconstructedKey;
}

// Initialize Firebase Admin
async function initializeFirebase() {
    try {
        let firebaseConfig;
        
        console.log('🔥 Initializing Firebase...');
        console.log('📍 Environment:', process.env.NODE_ENV || 'development');
        
                // Use environment variables in production, service account file in development
        if (process.env.NODE_ENV === 'production' && process.env.FIREBASE_PROJECT_ID) {
            console.log('🔧 Using environment variables for production...');
            
            const formattedPrivateKey = formatPrivateKey(process.env.FIREBASE_PRIVATE_KEY);
            if (!formattedPrivateKey || formattedPrivateKey.length < 500) {
                throw new Error(`Invalid private key: too short (${formattedPrivateKey ? formattedPrivateKey.length : 0} chars)`);
            }
            
            firebaseConfig = {
                credential: admin.credential.cert({
                    projectId: process.env.FIREBASE_PROJECT_ID,
                    clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
                    privateKey: formattedPrivateKey
                })
            };
            
            admin.initializeApp(firebaseConfig);
            console.log("✅ Firebase initialized successfully with environment variables");
            
        } else {
            // Fallback to service account file for development
            try {
                console.log('🔧 Using service account file for development...');
                firebaseConfig = {
                    credential: admin.credential.cert(require("./serviceAccountKey.json"))
                };
                
                admin.initializeApp(firebaseConfig);
                console.log("✅ Firebase initialized successfully with service account file");
                
            } catch (serviceAccountError) {
                console.error('❌ Service account file failed:', serviceAccountError.message);
                throw new Error(`Firebase initialization failed: ${serviceAccountError.message}`);
            }
        }
        
        // Test Firestore connection after initialization
        console.log("🧪 Testing Firestore connection...");
        const testSnapshot = await admin.firestore().collection("admin_posts").limit(1).get();
        console.log("✅ Firestore connection test successful");
        
    } catch (error) {
        console.error("❌ Error initializing Firebase:", error.message);
        console.error("Full error:", error);
        
        // Provide helpful debugging information
        console.error("🔧 FIREBASE TROUBLESHOOTING:");
        console.error("1. Ensure serviceAccountKey.json is present and valid");
        console.error("2. If using environment variables, ensure private key is properly formatted");
        console.error("3. Check Firebase project settings and permissions");
        console.error("4. Verify all required dependencies are installed");
        
        process.exit(1);
    }
}

let firestore;
const clients = new Map();
let lastSentPostId = null;

// Initialize Firebase and start server
initializeFirebase().then(() => {
    firestore = admin.firestore();
    console.log("🔧 Firestore instance created successfully");
    
    // Start the server after Firebase is ready
    startServer();
}).catch((error) => {
    console.error("❌ Failed to initialize Firebase:", error);
    process.exit(1);
});

function startServer() {

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

// Notification listener with improved connection management
let notificationListener = null;
let isNotificationListenerActive = false;
let retryCount = 0;
const MAX_RETRY_COUNT = 5;
const BASE_RETRY_DELAY = 5000; // 5 seconds

function getRetryDelay(retryCount) {
    // Exponential backoff: 5s, 10s, 20s, 40s, 80s
    return Math.min(BASE_RETRY_DELAY * Math.pow(2, retryCount), 300000); // Max 5 minutes
}

function startNotificationListener() {
    // Prevent multiple listeners
    if (isNotificationListenerActive) {
        console.log('🔔 Notification listener already active, skipping...');
        return;
    }

    // Check retry limit
    if (retryCount >= MAX_RETRY_COUNT) {
        console.log('🔔 Maximum retry attempts reached, stopping notification listener');
        return;
    }

    try {
        // Clean up existing listener
        if (notificationListener) {
            console.log('🔔 Cleaning up existing notification listener...');
            notificationListener();
            notificationListener = null;
        }
        
        isNotificationListenerActive = true;
        console.log(`🔔 Starting notification listener (attempt ${retryCount + 1}/${MAX_RETRY_COUNT})...`);
        
        notificationListener = firestore.collection('notifications').onSnapshot(
            (snapshot) => {
                // Reset retry count on successful connection
                retryCount = 0;
                
                snapshot.docChanges().forEach(async (change) => {
                    if (change.type === 'added') {
                        try {
                            await handleClassNotification(change.doc);
                        } catch (error) {
                            console.error('🔔 Error processing notification:', error);
                        }
                    }
                });
            },
            (error) => {
                console.error('🔔 Notification listener error:', error.message);
                isNotificationListenerActive = false;
                
                // Clean up current listener
                if (notificationListener) {
                    notificationListener();
                    notificationListener = null;
                }
                
                retryCount++;
                const retryDelay = getRetryDelay(retryCount - 1);
                
                if (retryCount < MAX_RETRY_COUNT) {
                    console.log(`🔄 Retrying notification listener in ${retryDelay / 1000} seconds... (${retryCount}/${MAX_RETRY_COUNT})`);
                    
                    setTimeout(() => {
                        startNotificationListener();
                    }, retryDelay);
                } else {
                    console.log('🔔 Maximum retries reached for notification listener. Will retry in 10 minutes.');
                    // After max retries, wait 10 minutes then reset retry count
                    setTimeout(() => {
                        retryCount = 0;
                        startNotificationListener();
                    }, 600000); // 10 minutes
                }
            }
        );
        
        console.log('✅ Notification listener started successfully');
        
    } catch (error) {
        console.error('🔔 Failed to start notification listener:', error);
        isNotificationListenerActive = false;
        retryCount++;
        
        const retryDelay = getRetryDelay(retryCount - 1);
        
        if (retryCount < MAX_RETRY_COUNT) {
            setTimeout(() => {
                startNotificationListener();
            }, retryDelay);
        } else {
            console.log('🔔 Maximum retries reached. Will retry in 10 minutes.');
            setTimeout(() => {
                retryCount = 0;
                startNotificationListener();
            }, 600000); // 10 minutes
        }
    }
}

// Notification listener will be started after server initialization

// Handle OPTIONS preflight for /events endpoint
app.options("/events", (req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Cache-Control');
    res.setHeader('Access-Control-Max-Age', '86400'); // 24 hours
    res.sendStatus(200);
});

// Server-Sent Events endpoint
app.get("/events", async (req, res) => {
    // Set SSE headers - critical for EventSource compatibility
    res.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Connection': 'keep-alive',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Cache-Control, Content-Type',
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
        'Pragma': 'no-cache',
        'Expires': '0',
        'X-Accel-Buffering': 'no' // Disable nginx buffering
    });

    const postsCollection = firestore.collection("admin_posts");
    let unsubscribe = null;

    console.log('📡 New SSE connection established from:', req.headers['user-agent'] || 'Unknown');

    // Send initial connection confirmation
    res.write(`event: connected\n`);
    res.write(`data: ${JSON.stringify({status: "connected", timestamp: new Date().toISOString()})}\n\n`);

    try {
        // Send initial posts
        const snapshot = await postsCollection.orderBy("timestamp", "desc").limit(10).get();
        if (!snapshot.empty) {
            console.log(`📡 Sending ${snapshot.docs.length} initial posts to client`);
            snapshot.docs.forEach((doc) => {
                const data = doc.data();
                const eventData = JSON.stringify({
                    message: data.text,
                    adminEmail: data.email,
                    timestamp: data.timestamp ? data.timestamp.toDate().toISOString() : new Date().toISOString(),
                    imageUrl: data.imageUrl || null,
                    category: data.category || "General"
                });
                res.write(`data: ${eventData}\n\n`);
            });
            lastSentPostId = snapshot.docs[0].id; 
        } else {
            console.log('📡 No initial posts found');
            res.write(`data: ${JSON.stringify({message: "No announcements yet"})}\n\n`);
        }
        
    } catch (error) {
        console.error("📡 Error fetching initial posts:", error);
        res.write(`data: ${JSON.stringify({error: "Failed to load initial posts", details: error.message})}\n\n`);
    }

    // Set up real-time listener with error handling
    try {
        unsubscribe = postsCollection.orderBy("timestamp", "desc").limit(1).onSnapshot(
            (snapshot) => {
                if (snapshot.empty) return;

                const latestDoc = snapshot.docs[0];
                if (lastSentPostId === latestDoc.id) return; 

                lastSentPostId = latestDoc.id;
                const latestPost = latestDoc.data();
                
                const eventData = JSON.stringify({
                    message: latestPost.text,
                    adminEmail: latestPost.email,
                    timestamp: latestPost.timestamp ? latestPost.timestamp.toDate().toISOString() : new Date().toISOString(),
                    imageUrl: latestPost.imageUrl || null,
                    category: latestPost.category || "General"
                });
                
                res.write(`data: ${eventData}\n\n`);
                console.log('📡 New admin post sent via SSE');
            },
            (error) => {
                console.error("📡 SSE Firestore listener error:", error);
                res.write(`data: ${JSON.stringify({error: "Connection lost, please refresh", details: error.message})}\n\n`);
            }
        );
        
    } catch (error) {
        console.error("📡 Error setting up SSE listener:", error);
        res.write(`data: ${JSON.stringify({error: "Failed to setup real-time updates", details: error.message})}\n\n`);
    }

    // Handle client disconnect
    req.on("close", () => {
        console.log('📡 SSE connection closed by client');
        if (unsubscribe) {
            unsubscribe();
        }
    });
    
    req.on("error", (error) => {
        console.error('📡 SSE connection error:', error);
        if (unsubscribe) {
            unsubscribe();
        }
    });
    
    // Send periodic heartbeat to keep connection alive
    const heartbeatInterval = setInterval(() => {
        if (res.destroyed || res.finished) {
            clearInterval(heartbeatInterval);
            return;
        }
        try {
            res.write(`event: heartbeat\n`);
            res.write(`data: ${JSON.stringify({status: "alive", timestamp: new Date().toISOString()})}\n\n`);
        } catch (error) {
            console.error('📡 Error sending heartbeat:', error);
            clearInterval(heartbeatInterval);
        }
    }, 30000);
    
    req.on("close", () => {
        clearInterval(heartbeatInterval);
        if (unsubscribe) {
            unsubscribe();
        }
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

// Test endpoint for Flutter connectivity debugging
app.get("/test-connection", (req, res) => {
    res.json({
        status: "success",
        message: "Connection test successful",
        timestamp: new Date().toISOString(),
        userAgent: req.headers['user-agent'] || 'Unknown',
        ip: req.ip || req.connection.remoteAddress,
        headers: {
            origin: req.headers.origin,
            referer: req.headers.referer,
            'content-type': req.headers['content-type']
        }
    });
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

// Graceful shutdown handling
process.on('SIGTERM', () => {
    console.log('🔄 SIGTERM received, shutting down gracefully...');
    
    // Close notification listener
    if (notificationListener) {
        notificationListener();
    }
    
    // Close WebSocket server
    wss.close(() => {
        console.log('📡 WebSocket server closed');
    });
    
    // Close HTTP server
    server.close(() => {
        console.log('🚀 HTTP server closed');
        process.exit(0);
    });
});

process.on('SIGINT', () => {
    console.log('🔄 SIGINT received, shutting down gracefully...');
    
    // Close notification listener
    if (notificationListener) {
        notificationListener();
    }
    
    // Close WebSocket server
    wss.close(() => {
        console.log('📡 WebSocket server closed');
    });
    
    // Close HTTP server
    server.close(() => {
        console.log('🚀 HTTP server closed');
        process.exit(0);
    });
});

// Handle unhandled promise rejections (common with Firestore)
process.on('unhandledRejection', (reason, promise) => {
    console.error('⚠️ Unhandled Rejection at:', promise, 'reason:', reason);
    // Don't exit the process, just log the error
});

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
    console.error('💥 Uncaught Exception:', error);
    // For uncaught exceptions, we should exit
    process.exit(1);
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
        
        // Start the notification listener after server is running
        setTimeout(() => {
            console.log('🔔 Initializing notification listener...');
            startNotificationListener();
        }, 5000); // Wait 5 seconds after server startup
        
    }).on('error', (err) => {
        console.error('❌ Server startup error:', err);
        process.exit(1);
    });
}