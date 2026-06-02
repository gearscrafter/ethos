import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Semantics(
          label: '',
          child: GestureDetector(
            onTap: () {},
            child: const Text('Toggle dark mode'),
          ),
        ),
        Semantics(
          label: 'Sign out of your account',
          child: InkResponse(
            onTap: () {},
            child: const Text('Sign out'),
          ),
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.help),
        ),
      ],
    );
  }
}
