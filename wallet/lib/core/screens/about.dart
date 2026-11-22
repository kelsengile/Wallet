import 'package:flutter/material.dart';

import '../constants.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline),
            SizedBox(width: AppConstants.spaceSm),
            Text('About'),
          ],
        ),
      ),
      body: const Center(child: Text('About')),
    );
  }
}