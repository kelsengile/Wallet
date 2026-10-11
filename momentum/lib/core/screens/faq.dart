import 'package:flutter/material.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.help_outline),
            SizedBox(width: 8),
            Text('FAQ'),
          ],
        ),
      ),
      body: const Center(child: Text('FAQ')),
    );
  }
}