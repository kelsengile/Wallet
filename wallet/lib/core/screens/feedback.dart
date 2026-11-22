import 'package:flutter/material.dart';

import '../constants.dart';
import '../links.dart';
import 'about.dart';

class FeedbackScreen extends StatelessWidget {
  const FeedbackScreen({super.key});

  void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send(BuildContext context) async {
    final ok = await Links.composeFeedback();
    if (ok || !context.mounted) return;
    await Links.copyEmail();
    if (context.mounted) {
      _say(context, 'No mail app found. The email address was copied.');
    }
  }

  Future<void> _copy(BuildContext context) async {
    await Links.copyEmail();
    if (context.mounted) _say(context, 'Email address copied.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.feedback_outlined),
            SizedBox(width: AppConstants.spaceSm),
            Text('Feedback'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppConstants.spaceXl),
        children: [
          const InfoHero(
            icon: Icons.mail_outline,
            title: 'We\'d love to hear from you',
            subtitle: 'Ideas, bugs, or just a hello',
          ),
          const SizedBox(height: AppConstants.spaceSm),
          const InfoCard(
            icon: Icons.chat_bubble_outline,
            title: 'Share your thoughts',
            child: InfoText(
              'Wallet is made by one person and shaped by the people who use '
              'it. Whether you found a bug, have an idea for a new feature, '
              'or just want to say hi, your message really helps. Every email '
              'is read.',
            ),
          ),
          const InfoCard(
            icon: Icons.bug_report_outlined,
            title: 'Reporting a problem?',
            child: Column(
              children: [
                InfoBullet(icon: Icons.touch_app_outlined, text: 'What you were trying to do'),
                InfoBullet(icon: Icons.error_outline, text: 'What happened instead (a screenshot helps a lot)'),
                InfoBullet(icon: Icons.phone_android, text: 'Your phone model and Android / iOS version'),
              ],
            ),
          ),
          InfoCard(
            icon: Icons.alternate_email,
            title: 'Write to me',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SelectableText(
                  AppConstants.developerEmail,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppConstants.spaceMd),
                FilledButton.icon(
                  onPressed: () => _send(context),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Send email'),
                ),
                const SizedBox(height: AppConstants.spaceSm),
                OutlinedButton.icon(
                  onPressed: () => _copy(context),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy email address'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppConstants.spaceMd),
            child: Text(
              'Thank you for helping make Wallet better!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}