import 'package:flutter/material.dart';

/// Feedback page — users can choose a type and write a message.
/// Hook [_submit] up to an email/API call as needed.
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  String _type = 'Suggestion';
  final _msgCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _submitted = false;

  static const _types = [
    'Suggestion',
    'Bug Report',
    'General Feedback',
    'Other',
  ];

  @override
  void dispose() {
    _msgCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_msgCtrl.text.trim().isEmpty) return;
    // TODO: integrate with your backend / email service.
    setState(() => _submitted = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Send Feedback')),
      body: _submitted
          ? _SuccessView(theme: theme)
          : _FormView(
              type: _type,
              types: _types,
              msgCtrl: _msgCtrl,
              emailCtrl: _emailCtrl,
              onTypeChanged: (v) => setState(() => _type = v),
              onSubmit: _submit,
              theme: theme,
            ),
    );
  }
}

class _FormView extends StatelessWidget {
  final String type;
  final List<String> types;
  final TextEditingController msgCtrl;
  final TextEditingController emailCtrl;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onSubmit;
  final ThemeData theme;

  const _FormView({
    required this.type,
    required this.types,
    required this.msgCtrl,
    required this.emailCtrl,
    required this.onTypeChanged,
    required this.onSubmit,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'We\'d love to hear from you!',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Share a suggestion, report a bug, or just say hello.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 20),

        // Type
        DropdownButtonFormField<String>(
          value: type,
          decoration: const InputDecoration(
            labelText: 'Feedback type',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.label_outline),
          ),
          items: types
              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
              .toList(),
          onChanged: (v) {
            if (v != null) onTypeChanged(v);
          },
        ),
        const SizedBox(height: 12),

        // Message
        TextField(
          controller: msgCtrl,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Your message',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.message_outlined),
          ),
        ),
        const SizedBox(height: 12),

        // Optional email
        TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Your email (optional)',
            hintText: 'So we can get back to you',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onSubmit,
            icon: const Icon(Icons.send),
            label: const Text('Send Feedback'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  final ThemeData theme;
  const _SuccessView({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.green.shade100,
              child: Icon(Icons.check, color: Colors.green.shade700, size: 40),
            ),
            const SizedBox(height: 16),
            Text('Thank you!',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Your feedback has been received. We appreciate you taking the time!',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
