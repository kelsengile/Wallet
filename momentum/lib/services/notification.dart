import 'package:flutter/material.dart';

import '../core/constants.dart';

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
            SizedBox(width: AppConstants.spaceSm),
            Text('Notifications'),
          ],
        ),
      ),
      body: const Center(child: Text('Notifications')),
    );
  }
}