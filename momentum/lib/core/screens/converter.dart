import 'package:flutter/material.dart';

import '../constants.dart';

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
            SizedBox(width: AppConstants.spaceSm),
            Text('Converter'),
          ],
        ),
      ),
      body: const Center(child: Text('Converter')),
    );
  }
}