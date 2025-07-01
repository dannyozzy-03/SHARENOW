const express = require("express");
const cors = require("cors");
const admin = require("firebase-admin");

const app = express();
app.use(cors());
app.use(express.json());

admin.initializeApp({
    credential: admin.credential.cert(require("./serviceAccountKey.json")),
});

const firestore = admin.firestore();
let lastSentPostId = null;

// Add new notification handling code
async function handleClassNotification(notificationDoc) {
  try {
    const notification = notificationDoc.data();
    console.log('Processing notification document:', notificationDoc.id);
    console.log('Notification data:', notification);

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
      },
      apns: {
        payload: {
          aps: {
            contentAvailable: true,
            priority: 5,
          },
        },
      },
    };

    console.log('Sending FCM message:', message);
    
    try {
      const response = await admin.messaging().send(message);
      console.log('Successfully sent message:', response);
      await notificationDoc.ref.delete();
      return response;
    } catch (error) {
      console.error('Error sending FCM message:', error.code, error.message);
      throw error;
    }
  } catch (error) {
    console.error('Error in handleClassNotification:', error);
    throw error;
  }
}

// Add notification listener
firestore.collection('notifications')
  .onSnapshot((snapshot) => {
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

app.get("/events", async (req, res) => {
    res.setHeader("Content-Type", "text/event-stream");
    res.setHeader("Cache-Control", "no-cache");
    res.setHeader("Connection", "keep-alive");

    const postsCollection = firestore.collection("admin_posts");

    // Send existing posts when user connects
    try {
        const snapshot = await postsCollection.orderBy("timestamp", "desc").get();
        if (!snapshot.empty) {
            snapshot.docs.forEach((doc) => {
                const data = doc.data();                res.write(`data: ${JSON.stringify({
                    message: data.text,
                    adminEmail: data.email,
                    timestamp: data.timestamp ? data.timestamp.toDate().toISOString() : new Date().toISOString(),
                    imageUrl: data.imageUrl || null, // Include image URL if available
                    category: data.category || "General" // Include category information
                })}\n\n`);
            });
            lastSentPostId = snapshot.docs[0].id; 
        }
    } catch (error) {
        console.error("Error fetching initial posts:", error);
    }

    // Live updates: Send new posts only
    const unsubscribe = postsCollection.orderBy("timestamp", "desc").limit(1).onSnapshot((snapshot) => {
        if (snapshot.empty) return;

        const latestDoc = snapshot.docs[0];
        if (lastSentPostId === latestDoc.id) return; 

        lastSentPostId = latestDoc.id;

        const latestPost = latestDoc.data();        res.write(`data: ${JSON.stringify({
            message: latestPost.text,
            adminEmail: latestPost.email,
            timestamp: latestPost.timestamp ? latestPost.timestamp.toDate().toISOString() : new Date().toISOString(),
            imageUrl: latestPost.imageUrl || null, // Send image URL if available
            category: latestPost.category || "General" // Include category information
        })}\n\n`);
    });

    req.on("close", () => {
        unsubscribe();
        res.end();
    });
});

app.post("/admin/post", async (req, res) => {    try {
        const { text, adminEmail, imageUrl, category } = req.body;

        if (!text || !adminEmail) {
            return res.status(400).json({ error: "Missing text or adminEmail" });
        }

        // Save post to Firestore
        const newPostRef = await firestore.collection("admin_posts").add({
            text,
            email: adminEmail,
            imageUrl: imageUrl || null, // Save image URL if available
            category: category || "General", // Use the category from request body or default to "General"
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`New Admin Post: ${text} from ${adminEmail} with image: ${imageUrl || "No Image"}`);

        // Send response
        res.status(200).json({ success: true, id: newPostRef.id });

    } catch (error) {
        console.error("Error adding post:", error);
        res.status(500).json({ error: "Failed to add post" });
    }
});

app.listen(4000, "0.0.0.0", () => console.log("SSE server running on http://localhost:4000"));
