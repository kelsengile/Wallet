import 'package:flutter/material.dart';

class ConverterScreen extends StatelessWidget {
  const ConverterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline),
            SizedBox(width: 8),
            Text('Converter'),
          ],
        ),
      ),
      body: const Center(child: Text('Converter')),
    );
  }
}