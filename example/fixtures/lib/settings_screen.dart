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
        Form(
          child: Column(
            children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const TextField(
                decoration: InputDecoration(labelText: 'Password'),
              ),
              ElevatedButton(
                onPressed: () {},
                child: const Text('Sign in'),
              ),
            ],
          ),
        ),
        const Text(
          'Large heading',
          style: TextStyle(
            color: Color(0xFF8C8C8C),
            backgroundColor: Color(0xFFFFFFFF),
            fontSize: 24,
          ),
        ),
        const Text(
          'Normal body text',
          style: TextStyle(
            color: Color(0xFF8C8C8C),
            backgroundColor: Color(0xFFFFFFFF),
          ),
        ),
      ],
    );
  }
}
