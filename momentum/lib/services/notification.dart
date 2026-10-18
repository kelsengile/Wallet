import 'package:flutter/material.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_outlined),
            SizedBox(width: 8),
            Text('Notifications'),
          ],
        ),
      ),
      body: const Center(child: Text('Notifications')),
    );
  }
}