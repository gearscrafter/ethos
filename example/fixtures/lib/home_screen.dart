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
          const Text(
            'High contrast text',
            style: TextStyle(
              color: Color(0xFF000000),
              backgroundColor: Color(0xFFFFFFFF),
            ),
          ),
          const Text(
            'Low contrast text',
            style: TextStyle(
              color: Color(0xFFCCCCCC),
              backgroundColor: Color(0xFFFFFFFF),
            ),
          ),
          const Text(
            'Design system text',
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: GestureDetector(
              onTap: () {},
              child: const Icon(Icons.add),
            ),
          ),
          SizedBox(
            width: 32,
            height: 32,
            child: GestureDetector(
              onTap: () {},
              child: const Icon(Icons.remove),
            ),
          ),
        ],
      ),
    );
  }
}
