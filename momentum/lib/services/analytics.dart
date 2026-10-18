import 'package:flutter/material.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.analytics_outlined),
            SizedBox(width: 8),
            Text('Analytics'),
          ],
        ),
      ),
      body: const Center(child: Text('Analytics')),
    );
  }
}