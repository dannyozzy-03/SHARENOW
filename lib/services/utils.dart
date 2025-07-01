import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class UtilsService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Upload a file to Firebase Storage and return the download URL
  Future<String?> uploadFile(File image, String path) async {
    Reference storageReference = _storage.ref(path);
    UploadTask uploadTask = storageReference.putFile(image);
    await uploadTask.whenComplete(() => null);
    return await storageReference.getDownloadURL();
  }

  // Delete a file from Firebase Storage
  Future<void> deleteFile(String fileUrl) async {
    try {
      Reference ref = _storage.refFromURL(fileUrl); // Get file reference
      await ref.delete(); // Delete the file from Firebase Storage
      print("File deleted successfully: $fileUrl");
    } catch (e) {
      print("Error deleting file: $e");
    }
  }
}
