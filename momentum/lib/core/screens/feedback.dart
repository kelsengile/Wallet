import 'package:flutter/material.dart';

class FeedbackScreen extends StatelessWidget {
  const FeedbackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.feedback_outlined),
            SizedBox(width: 8),
            Text('Feedback'),
          ],
        ),
      ),
      body: const Center(child: Text('Feedback')),
    );
  }
}