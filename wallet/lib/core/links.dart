import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';

class Links {
  Links._();

  static Future<bool> _open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openRepository() =>
      _open(Uri.parse(AppConstants.repositoryUrl));

  static Future<bool> composeFeedback() {
    final subject = Uri.encodeComponent('${AppConstants.appName} feedback');
    final body = Uri.encodeComponent(
      'Hi ${AppConstants.developerName},\n\n'
      '(Write your feedback or describe the problem here)\n\n'
      '---\nApp: ${AppConstants.appName} ${AppConstants.appVersion}',
    );
    return _open(
      Uri.parse(
        'mailto:${AppConstants.developerEmail}?subject=$subject&body=$body',
      ),
    );
  }

  static Future<void> copyEmail() =>
      Clipboard.setData(ClipboardData(text: AppConstants.developerEmail));
}
