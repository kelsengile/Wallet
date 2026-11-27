import 'package:material_ui/material_ui.dart';

import '../links.dart';

Future<void> openRepository(BuildContext context) async {
  final ok = await Links.openRepository();
  if (ok || !context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(content: Text('Couldn\'t open GitHub. Try again later.')),
    );
}