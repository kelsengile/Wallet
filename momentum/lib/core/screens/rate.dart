import 'package:flutter/material.dart';

class RateScreen extends StatelessWidget {
  const RateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_outline),
            SizedBox(width: 8),
            Text('Rate'),
          ],
        ),
      ),
      body: const Center(child: Text('Rate')),
    );
  }
}