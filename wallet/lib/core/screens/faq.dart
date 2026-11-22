import 'package:flutter/material.dart';

import '../constants.dart';

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
            SizedBox(width: AppConstants.spaceSm),
            Text('FAQ'),
          ],
        ),
      ),
      body: const Center(child: Text('FAQ')),
    );
  }
}