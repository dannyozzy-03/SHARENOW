import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';

class ImageHelper {
  static Future<File?> compressImage(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath =
        '${dir.absolute.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';

    XFile? compressedXFile = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path, targetPath,
      quality:
          40, // Adjust quality (higher = better quality, lower = smaller size)
    );

    if (compressedXFile == null) return null;

    return File(compressedXFile.path);
  }

  static Future<String?> uploadImageToFirebase(File file) async {
    File? compressedFile = await compressImage(file);
    if (compressedFile == null) return null;

    String fileName = basename(compressedFile.path);
    Reference storageRef =
        FirebaseStorage.instance.ref().child('uploads/$fileName');

    await storageRef.putFile(compressedFile);
    return await storageRef.getDownloadURL();
  }
}
