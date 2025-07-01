import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:twitterr/models/user.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db =
      FirebaseFirestore.instance; // Firestore instance
  final GoogleSignIn _googleSignIn = GoogleSignIn();

// 🔹 Create a user object based on FirebaseUser
  // 🔹 Create a user object based on FirebaseUser
  UserModel? _userFromFirebaseUser(User? firebaseUser) {
    if (firebaseUser == null) return null;

    return UserModel(
      id: firebaseUser.uid,
      bannerImageUrl: '',
      profileImageUrl: '',
      name: '',
      email: firebaseUser.email ?? '',
      role: 'user',
      phoneNumber: null, // Initialize as null
    );
  }

// 🔹 Stream to listen for auth state changes and fetch user data
  Stream<UserModel?> get user {
    return _auth.authStateChanges().asyncMap((User? user) async {
      if (user == null) return null;

      DocumentSnapshot<Map<String, dynamic>> snapshot =
          await _db.collection('users').doc(user.uid).get();

      final data = snapshot.data();

      return UserModel(
        id: user.uid,
        bannerImageUrl: data?['bannerImageUrl'] ?? '',
        profileImageUrl: data?['profileImageUrl'] ?? '',
        name: data?['name'] ?? '',
        email: user.email ?? '',
        role: data?['role'] ?? 'user',
        phoneNumber: data?['phoneNumber'], // Add this field
      );
    });
  }

  // Sign in with email and password
  Future signInWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      User? user = result.user;
      return _userFromFirebaseUser(user);
    } catch (e) {
      return null;
    }
  }

  // Register with email and password
  Future registerWithEmailAndPassword(
      String email, String password, String fullName, String role) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      User? user = result.user;

      // Save user details to Firestore
      await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({
        'fullName': fullName,
        'email': email,
        'role': role,
      });

      return user;
    } catch (e) {
      print(e.toString());
      return null;
    }
  }

  // Sign in with Google - Only for existing users
  Future<UserModel?> signInWithGoogle() async {
    try {
      // Check if Google Play Services is available
      if (!await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut(); // Clear any cached data
      }
      
      // Begin interactive sign in process
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        // User cancelled the sign-in
        return null;
      }

      // Check if user with this email already exists in Firestore BEFORE authenticating
      String email = googleUser.email;
      
      // Query Firestore for existing user with this email
      QuerySnapshot<Map<String, dynamic>> existingUsers = await _db
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (existingUsers.docs.isEmpty) {
        // Email doesn't exist in our database - reject sign-in
        await _googleSignIn.signOut(); // Sign out from Google
        throw Exception('UNREGISTERED_EMAIL');
      }

      // Email exists, proceed with Google authentication
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create a new credential for signing in with Firebase
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with Google credentials
      UserCredential result = await _auth.signInWithCredential(credential);
      User? user = result.user;

      if (user != null) {
        // Get existing user data from Firestore
        DocumentSnapshot<Map<String, dynamic>> existingUserDoc = existingUsers.docs.first;
        String existingUserId = existingUserDoc.id;
        
        // Check if user has custom profile picture (used for both scenarios)
        String? existingProfileUrl = existingUserDoc.data()?['profileImageUrl'];
        bool hasCustomProfilePicture = existingProfileUrl != null && 
            existingProfileUrl.isNotEmpty && 
            !existingProfileUrl.contains('default.png') &&
            !existingProfileUrl.contains('placeholder');
        
        // Determine final profile URL and name
        String finalProfileUrl = existingProfileUrl ?? '';
        String finalName = existingUserDoc.data()?['fullName'] ?? '';
        
        if (!hasCustomProfilePicture && user.photoURL != null && user.photoURL!.isNotEmpty) {
          finalProfileUrl = user.photoURL!;
        }
        
        if (finalName.isEmpty && user.displayName != null && user.displayName!.isNotEmpty) {
          finalName = user.displayName!;
        }
        
        // If the Firebase UID is different from the existing user, 
        // we need to update the existing document or handle the merge
        if (user.uid != existingUserId) {
          // Prepare update data
          Map<String, dynamic> updateData = {
            'lastSignInMethod': 'google',
            'lastSignInAt': FieldValue.serverTimestamp(),
          };
          
          if (!hasCustomProfilePicture && user.photoURL != null && user.photoURL!.isNotEmpty) {
            updateData['profileImageUrl'] = user.photoURL;
          }
          
          if ((existingUserDoc.data()?['fullName'] == null || existingUserDoc.data()?['fullName'].isEmpty) && 
              user.displayName != null && user.displayName!.isNotEmpty) {
            updateData['fullName'] = user.displayName;
          }
          
          // Update the existing user document
          await _db.collection('users').doc(existingUserId).update(updateData);
          
          // Delete the new user document if it was created
          await _db.collection('users').doc(user.uid).delete().catchError((e) => null);
          
          // Return the existing user's data
          return UserModel(
            id: existingUserId,
            bannerImageUrl: existingUserDoc.data()?['bannerImageUrl'] ?? '',
            profileImageUrl: finalProfileUrl,
            name: finalName,
            email: email,
            role: existingUserDoc.data()?['role'] ?? 'user',
            phoneNumber: existingUserDoc.data()?['phoneNumber'],
          );
        } else {
          // Same UID, just update the existing document
          Map<String, dynamic> updateData = {
            'lastSignInMethod': 'google',
            'lastSignInAt': FieldValue.serverTimestamp(),
          };
          
          if (!hasCustomProfilePicture && user.photoURL != null && user.photoURL!.isNotEmpty) {
            updateData['profileImageUrl'] = user.photoURL;
          }
          
          if ((existingUserDoc.data()?['fullName'] == null || existingUserDoc.data()?['fullName'].isEmpty) && 
              user.displayName != null && user.displayName!.isNotEmpty) {
            updateData['fullName'] = user.displayName;
          }
          
          await _db.collection('users').doc(user.uid).update(updateData);
          
          return _userFromFirebaseUser(user);
        }
      }
      
      return null;
    } catch (e) {
      print('Google Sign-In Error: $e');
      
      // Check for specific errors
      if (e.toString().contains('UNREGISTERED_EMAIL')) {
        throw Exception('EMAIL_NOT_REGISTERED');
      }
      
      if (e.toString().contains('channel-error') || 
          e.toString().contains('Unable to establish connection')) {
        throw Exception('Google Sign-In not configured. Please check Firebase Console settings and SHA-1 fingerprint.');
      }
      
      return null;
    }
  }

  // Check if email exists in Firestore
  Future<bool> emailExists(String email) async {
    try {
      QuerySnapshot<Map<String, dynamic>> existingUsers = await _db
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      
      return existingUsers.docs.isNotEmpty;
    } catch (e) {
      print('Error checking email existence: $e');
      return false;
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }
}
