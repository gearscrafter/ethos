import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  final String dynamicCta;
  const HomeScreen({super.key, this.dynamicCta = 'Continue'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Column(
        children: [
          Semantics(
            label: 'Open user profile',
            child: GestureDetector(
              onTap: () {},
              child: const Icon(Icons.person),
            ),
          ),
          InkWell(
            onTap: () {},
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.settings),
            ),
          ),
          Semantics(
            label: dynamicCta,
            child: GestureDetector(
              onTap: () {},
              child: const Text('Submit'),
            ),
          ),
          ElevatedButton(
            onPressed: () {},
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
