import 'package:flutter/material.dart';

import '../constants.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline),
            SizedBox(width: AppConstants.spaceSm),
            Text('Profile'),
          ],
        ),
      ),
      body: const Center(child: Text('Profile')),
    );
  }
}