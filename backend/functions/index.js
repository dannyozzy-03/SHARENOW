const {onRequest} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const { initializeApp } = require("firebase-admin");

const admin = required('firebase-admin');
admin,initializeApp();

const db = admin.firestore();

exports.addLike = functions.firestore.document('/posts/{postId}/likes/{userId}')
.onCreate((snap, context) => {
    return db
    .collection("posts")
    .doc(context.params.postId)
    .update({likesCount: admin.firestore.FieldValue
    .increment(1)})
})

exports.deleteLike = functions.firestore.document('/posts/{postId}/likes/{userId}')
.onDelete((snap, context) => {
    return db
    .collection("posts")
    .doc(context.params.postId)
    .update(
        {likesCount: admin.firestore.FieldValue.increment(-1)})
})