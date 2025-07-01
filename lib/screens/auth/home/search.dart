import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:twitterr/models/user.dart';
import 'package:twitterr/screens/auth/main/profile/list.dart';
import 'package:twitterr/services/user.dart';

class Search extends StatefulWidget {
  const Search({super.key});

  @override
  _SearchState createState() => _SearchState();
}

class _SearchState extends State<Search> {
  final UserService _userService = UserService();
  String search = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 35), // Added space above the search bar
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(
            onChanged: (text) {
              setState(() {
                search =
                    text.trim().toLowerCase(); // Make search case-insensitive
              });
            },
            decoration: InputDecoration(
              hintText: 'Search...',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.search),
            ),
          ),
        ),
        if (search.isNotEmpty)
          StreamProvider<List<UserModel>>.value(
            value: _userService.queryByName(search),
            initialData: const [],
            catchError: (_, __) => [],
            child: Expanded(child: ListUsers()),
          )
        else
          const Expanded(
            child: Center(child: Text('Enter a name to search')),
          ),
      ],
    );
  }
}