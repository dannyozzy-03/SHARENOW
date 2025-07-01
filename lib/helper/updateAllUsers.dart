import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> updateAllUsers() async {
  QuerySnapshot querySnapshot =
      await FirebaseFirestore.instance.collection('users').get();

  for (var doc in querySnapshot.docs) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    String name = data['name'] ?? '';

    if (name.isNotEmpty) {
      await doc.reference.update({
        'lowercaseName': name.toLowerCase(),
        'searchKeywords': generateSearchKeywords(name),
      });
    }
  }

  print("✅ All users updated successfully!");
}

List<String> generateSearchKeywords(String name) {
  List<String> keywords = [];
  String lowerName = name.toLowerCase();

  for (int i = 1; i <= lowerName.length; i++) {
    keywords.add(lowerName.substring(0, i));
  }

  return keywords;
}
