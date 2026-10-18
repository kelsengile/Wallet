import 'package:flutter/material.dart';

class DatabaseScreen extends StatelessWidget {
  const DatabaseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline),
            SizedBox(width: 8),
            Text('Database'),
          ],
        ),
      ),
      body: const Center(child: Text('Database')),
    );
  }
}