import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:twitterr/models/user.dart';

class ListUsers extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final users = Provider.of<List<UserModel>?>(context) ?? [];

    if (users.isEmpty) {
      return const Center(
        child: Text('No users found'),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics:
          const NeverScrollableScrollPhysics(), // Prevents nested scrolling issues
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return InkWell(
          onTap: () =>
              Navigator.pushNamed(context, '/profile', arguments: user.id),
          child: Column(
            mainAxisSize: MainAxisSize.min, // Prevents RenderFlex overflow
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    user.profileImageUrl.isNotEmpty
                        ? CircleAvatar(
                            radius: 20,
                            backgroundImage: NetworkImage(user.profileImageUrl),
                          )
                        : const Icon(Icons.person, size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                      // Prevents text overflow
                      child: Text(
                        user.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(thickness: 1),
            ],
          ),
        );
      },
    );
  }
}
