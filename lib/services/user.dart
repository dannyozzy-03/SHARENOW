import 'dart:collection';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:twitterr/models/user.dart';
import 'package:twitterr/services/utils.dart';

class UserService {
  final UtilsService _utilsService = UtilsService();

// 🔹 Convert Firestore QuerySnapshot to a list of UserModel objects
  List<UserModel> _userListFromQueryFirebaseSnapshot(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return UserModel(
        id: doc.id,
        name: data['name'] ?? '',
        profileImageUrl: data['profileImageUrl'] ?? '',
        bannerImageUrl: data['bannerImageUrl'] ?? '',
        email: data['email'] ?? '',
        role: data['role'] ?? 'user', // 🔹 Added role with default 'user'
        phoneNumber: data['phoneNumber'],  // Added this field
      );
    }).toList();
  }

// 🔹 Convert Firestore DocumentSnapshot to a UserModel object
  UserModel? _userFromFirebaseSnapshot(DocumentSnapshot snapshot) {
    final data = snapshot.data() as Map<String, dynamic>?;

    if (data != null) {
      return UserModel(
        id: snapshot.id,
        name: data['name'] ?? '',
        profileImageUrl: data['profileImageUrl'] ?? '',
        bannerImageUrl: data['bannerImageUrl'] ?? '',
        email: data['email'] ?? '',
        role: data['role'] ?? 'user', // 🔹 Added role with default 'user'
        phoneNumber: data['phoneNumber'],  // Added this field
      );
    }
    return null;
  }

  // Fetch a user's information from Firestore by uid
  Stream<UserModel?> getUserInfo(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .map(_userFromFirebaseSnapshot);
  }

  Future<void> followUser(String uid) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser?.uid)
        .collection('following')
        .doc(uid)
        .set({});

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('followers')
        .doc(FirebaseAuth.instance.currentUser?.uid)
        .set({});
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    DocumentSnapshot<Map<String, dynamic>> snapshot =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    return snapshot.data() ?? {}; // Return an empty map instead of null
  }

  Future<void> unfollowUser(String uid) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser?.uid)
        .collection('following')
        .doc(uid)
        .delete();

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('followers')
        .doc(FirebaseAuth.instance.currentUser?.uid)
        .delete();
  }

  // Stream to check if the current user is following another user
  Stream<bool?> isFollowing(String uid, String otherId) {
    return FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .collection("following")
        .doc(otherId)
        .snapshots()
        .map((snapshot) {
      return snapshot.exists;
    });
  }

  Future<List<String>> getUserFollowing(uid) async {
    QuerySnapshot querySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('following')
        .get();

    final users = querySnapshot.docs.map((doc) => doc.id).toList();
    return users;
  }

  // Stream to query users by name
  Stream<List<UserModel>> queryByName(String search) {
    String lowerSearch = search.toLowerCase();

    return FirebaseFirestore.instance
        .collection("users")
        .where('lowercaseName', isGreaterThanOrEqualTo: lowerSearch)
        .where('lowercaseName', isLessThan: lowerSearch + '\uf8ff')
        .snapshots()
        .map(_userListFromQueryFirebaseSnapshot);
  }

  List<String> generateSearchKeywords(String name) {
    List<String> keywords = [];
    String lowerName = name.toLowerCase();

    // Generate all possible starting substrings for search
    for (int i = 1; i <= lowerName.length; i++) {
      keywords.add(lowerName.substring(0, i));
    }

    return keywords;
  }

  // Function to update the profile with image uploads
  Future<void> updateProfile(
      String? bannerUrl, String? profileUrl, String name, String? phoneNumber) async {
    Map<String, Object?> data = HashMap();

    if (name.isNotEmpty) {
      data['name'] = name;
      data['lowercaseName'] = name.toLowerCase(); // Store lowercase version
      data['searchKeywords'] = generateSearchKeywords(name);
    }

    if (bannerUrl != null && bannerUrl.isNotEmpty) {
      data['bannerImageUrl'] = bannerUrl;
    }

    if (profileUrl != null && profileUrl.isNotEmpty) {
      data['profileImageUrl'] = profileUrl;
    }
    
    // Add phone number to data map (can be null)
    data['phoneNumber'] = phoneNumber;

    // Update user document in Firestore
    await FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser?.uid)
        .update(data);
  }
}
