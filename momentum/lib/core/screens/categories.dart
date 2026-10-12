import 'package:flutter/material.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.category_outlined),
            SizedBox(width: 8),
            Text('Categories'),
          ],
        ),
      ),
      body: const Center(child: Text('Categories')),
    );
  }
}