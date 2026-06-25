import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class IdCard {
  final String id;
  String label;
  String? frontImagePath;
  String? backImagePath;

  IdCard({
    required this.id,
    required this.label,
    this.frontImagePath,
    this.backImagePath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'front': frontImagePath,
        'back': backImagePath,
      };

  factory IdCard.fromJson(Map<String, dynamic> j) => IdCard(
        id: j['id'] as String,
        label: j['label'] as String,
        frontImagePath: j['front'] as String?,
        backImagePath: j['back'] as String?,
      );
}

// ── Page ─────────────────────────────────────────────────────────────────────

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with TickerProviderStateMixin {
  // --- ID cards ---
  List<IdCard> _cards = [];

  // One flip controller per card slot — rebuilt when list changes
  final Map<String, AnimationController> _flipControllers = {};
  final Map<String, Animation<double>> _flipAnimations = {};
  final Map<String, bool> _showingFront = {};

  // --- Notes ---
  List<Map<String, dynamic>> _notes =
      []; // each: {text, bold, italic, underline, fontSize}
  List<TextEditingController> _noteControllers = [];
  List<bool> _noteEditing = [];
  // Per-note formatting state (mirrors _notes list)
  List<bool> _noteBold = [];
  List<bool> _noteItalic = [];
  List<bool> _noteUnderline = [];
  List<double> _noteFontSize = [];

  // ID-1 aspect ratio: 85.6 mm × 54.0 mm  →  ~1.5852
  static const double _cardAspectRatio = 85.6 / 54.0;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  @override
  void dispose() {
    for (final c in _flipControllers.values) {
      c.dispose();
    }
    for (final c in _noteControllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Flip controller helpers ───────────────────────────────────────────────

  AnimationController _controllerFor(String cardId) {
    if (!_flipControllers.containsKey(cardId)) {
      final ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 450),
      );
      _flipControllers[cardId] = ctrl;
      _flipAnimations[cardId] = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: ctrl, curve: Curves.easeInOut),
      );
      _showingFront[cardId] = true;
    }
    return _flipControllers[cardId]!;
  }

  Animation<double> _animationFor(String cardId) {
    _controllerFor(cardId); // ensure created
    return _flipAnimations[cardId]!;
  }

  void _flipCard(String cardId) {
    final ctrl = _controllerFor(cardId);
    if (ctrl.isAnimating) return;
    final front = _showingFront[cardId] ?? true;
    if (front) {
      ctrl.forward();
    } else {
      ctrl.reverse();
    }
    setState(() => _showingFront[cardId] = !front);
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('id_cards');
    if (raw != null) {
      final list = (jsonDecode(raw) as List)
          .map((e) => IdCard.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() => _cards = list);
    }
    // Load notes list
    final notesRaw = prefs.getString('notes_list');
    if (notesRaw != null) {
      final list = (jsonDecode(notesRaw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _notes = list;
        _noteControllers = list
            .map((n) => TextEditingController(text: n['text'] as String? ?? ''))
            .toList();
        _noteEditing = List.generate(list.length, (_) => false);
        _noteBold = list.map((n) => (n['bold'] as bool?) ?? false).toList();
        _noteItalic = list.map((n) => (n['italic'] as bool?) ?? false).toList();
        _noteUnderline =
            list.map((n) => (n['underline'] as bool?) ?? false).toList();
        _noteFontSize = list
            .map((n) => (n['fontSize'] as num?)?.toDouble() ?? 14.0)
            .toList();
      });
    } else {
      // Migrate legacy single note if present
      final legacyText = prefs.getString('note_text');
      if (legacyText != null && legacyText.isNotEmpty) {
        final note = {
          'text': legacyText,
          'bold': prefs.getBool('note_bold') ?? false,
          'italic': prefs.getBool('note_italic') ?? false,
          'underline': prefs.getBool('note_underline') ?? false,
          'fontSize': prefs.getDouble('note_font_size') ?? 14.0,
        };
        setState(() {
          _notes = [note];
          _noteControllers = [TextEditingController(text: legacyText)];
          _noteEditing = [false];
          _noteBold = [note['bold'] as bool];
          _noteItalic = [note['italic'] as bool];
          _noteUnderline = [note['underline'] as bool];
          _noteFontSize = [(note['fontSize'] as double)];
        });
      }
    }
  }

  Future<void> _saveCards() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(
        'id_cards', jsonEncode(_cards.map((c) => c.toJson()).toList()));
  }

  Future<void> _saveNotePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    // Sync controller text back into _notes
    for (int i = 0; i < _noteControllers.length; i++) {
      if (i < _notes.length) {
        _notes[i]['text'] = _noteControllers[i].text;
        _notes[i]['bold'] = _noteBold[i];
        _notes[i]['italic'] = _noteItalic[i];
        _notes[i]['underline'] = _noteUnderline[i];
        _notes[i]['fontSize'] = _noteFontSize[i];
      }
    }
    prefs.setString('notes_list', jsonEncode(_notes));
  }

  void _addNote() {
    setState(() {
      _notes.add({
        'text': '',
        'bold': false,
        'italic': false,
        'underline': false,
        'fontSize': 14.0,
      });
      _noteControllers.add(TextEditingController());
      _noteEditing.add(true); // open new note in edit mode immediately
      _noteBold.add(false);
      _noteItalic.add(false);
      _noteUnderline.add(false);
      _noteFontSize.add(14.0);
    });
    _saveNotePrefs();
  }

  void _deleteNote(int index) {
    setState(() {
      _noteControllers[index].dispose();
      _noteControllers.removeAt(index);
      _notes.removeAt(index);
      _noteEditing.removeAt(index);
      _noteBold.removeAt(index);
      _noteItalic.removeAt(index);
      _noteUnderline.removeAt(index);
      _noteFontSize.removeAt(index);
    });
    _saveNotePrefs();
  }

  // ── ID helpers ────────────────────────────────────────────────────────────

  Future<ImageSource?> _showImageSourceSheet() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(IdCard card, {required bool isFront}) async {
    final source = await _showImageSourceSheet();
    if (source == null) return;
    final picked =
        await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    setState(() {
      if (isFront) {
        card.frontImagePath = picked.path;
      } else {
        card.backImagePath = picked.path;
      }
    });
    _saveCards();
  }

  void _showAddOrEditDialog({IdCard? existing}) {
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    // Local mutable paths for new cards; for existing cards use the card itself
    String? frontPath = existing?.frontImagePath;
    String? backPath = existing?.backImagePath;

    Future<void> pickDialogImage({
      required bool isFront,
      required void Function(String path) onPicked,
    }) async {
      final source = await _showImageSourceSheet();
      if (source == null) return;
      final picked =
          await ImagePicker().pickImage(source: source, imageQuality: 85);
      if (picked == null) return;
      onPicked(picked.path);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Widget photoSlot({
            required String label,
            required String? imagePath,
            required VoidCallback onTap,
          }) {
            return Expanded(
              child: GestureDetector(
                onTap: onTap,
                child: AspectRatio(
                  aspectRatio: 85.6 / 54.0,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Theme.of(ctx)
                          .colorScheme
                          .surfaceVariant
                          .withOpacity(0.5),
                      border: Border.all(
                          color: Theme.of(ctx).colorScheme.outlineVariant),
                      image: imagePath != null
                          ? DecorationImage(
                              image: FileImage(File(imagePath)),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: imagePath == null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_photo_alternate_outlined,
                                  size: 24,
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .onSurfaceVariant),
                              const SizedBox(height: 4),
                              Text(label,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(ctx)
                                          .colorScheme
                                          .onSurfaceVariant)),
                            ],
                          )
                        : Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                padding: const EdgeInsets.all(3),
                                child: const Icon(Icons.edit,
                                    size: 12, color: Colors.white),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            );
          }

          return AlertDialog(
            title: Text(existing == null ? 'Add ID Card' : 'Edit ID Card'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: labelCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: "e.g. Driver's License, Passport…",
                      border: OutlineInputBorder(),
                      labelText: 'Label',
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                  const Text('Photos',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      photoSlot(
                        label: 'Front',
                        imagePath: frontPath,
                        onTap: () => pickDialogImage(
                          isFront: true,
                          onPicked: (p) => setDialogState(() => frontPath = p),
                        ),
                      ),
                      const SizedBox(width: 10),
                      photoSlot(
                        label: 'Back',
                        imagePath: backPath,
                        onTap: () => pickDialogImage(
                          isFront: false,
                          onPicked: (p) => setDialogState(() => backPath = p),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              if (existing != null)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () {
                    setState(() {
                      _flipControllers[existing.id]?.dispose();
                      _flipControllers.remove(existing.id);
                      _flipAnimations.remove(existing.id);
                      _showingFront.remove(existing.id);
                      _cards.remove(existing);
                    });
                    _saveCards();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Delete'),
                ),
              FilledButton(
                onPressed: () {
                  final label = labelCtrl.text.trim();
                  if (label.isEmpty) return;
                  setState(() {
                    if (existing == null) {
                      final newCard = IdCard(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        label: label,
                        frontImagePath: frontPath,
                        backImagePath: backPath,
                      );
                      _cards.add(newCard);
                    } else {
                      existing.label = label;
                      existing.frontImagePath = frontPath;
                      existing.backImagePath = backPath;
                    }
                  });
                  _saveCards();
                  Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      children: [
        // Avatar + title
        Center(
          child: CircleAvatar(
            radius: 40,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(Icons.person,
                size: 40, color: theme.colorScheme.onPrimaryContainer),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'My Wallet',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),

        const SizedBox(height: 32),

        // ── ID Cards ──────────────────────────────────────────────────────
        _buildSectionHeader(
          theme,
          icon: Icons.badge_outlined,
          label: 'ID Cards',
          action: IconButton(
            onPressed: () => _showAddOrEditDialog(),
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'Add ID',
          ),
        ),
        const SizedBox(height: 12),

        if (_cards.isEmpty) _buildEmptyIdState(theme) else _buildIdStack(theme),

        const SizedBox(height: 32),

        // ── Note ──────────────────────────────────────────────────────────
        Row(
          children: [
            Icon(Icons.sticky_note_2_outlined,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              'Notes',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Add note',
              icon: const Icon(Icons.add, size: 20),
              onPressed: _addNote,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_notes.isEmpty)
          Center(
            child: Text(
              'Tap + to add a note',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (int i = 0; i < _notes.length; i++) ...[
            _buildNote(theme, i),
            const SizedBox(height: 12),
          ],

        const SizedBox(height: 32),
      ],
    );
  }

  // ── Section header ────────────────────────────────────────────────────────

  Widget _buildSectionHeader(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required Widget action,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        const Spacer(),
        action,
      ],
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmptyIdState(ThemeData theme) {
    return GestureDetector(
      onTap: () => _showAddOrEditDialog(),
      child: AspectRatio(
        aspectRatio: _cardAspectRatio,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_card,
                  size: 40, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 8),
              Text(
                'Tap to add an ID card',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Stacked list ─────────────────────────────────────────────────────────

  Widget _buildIdStack(ThemeData theme) {
    return Column(
      children: [
        for (int i = 0; i < _cards.length; i++) ...[
          _buildFlipCard(theme, _cards[i]),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  // ── Card options (long-press) ─────────────────────────────────────────────

  void _showCardOptions(IdCard card) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                card.label,
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit label'),
              onTap: () {
                Navigator.pop(ctx);
                _showAddOrEditDialog(existing: card);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Update front photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(card, isFront: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.flip_outlined),
              title: const Text('Update back photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(card, isFront: false);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete card',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _flipControllers[card.id]?.dispose();
                  _flipControllers.remove(card.id);
                  _flipAnimations.remove(card.id);
                  _showingFront.remove(card.id);
                  _cards.remove(card);
                });
                _saveCards();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Flip card ─────────────────────────────────────────────────────────────

  Widget _buildFlipCard(ThemeData theme, IdCard card) {
    // Ensure controllers exist. We can't use SingleTickerProvider for multiple,
    // so we create controllers with a TickerProviderStateMixin workaround by
    // using the Navigator ticker. For simplicity and reliability, we'll use
    // TickerProviderStateMixin on the State class instead.
    final animation = _animationFor(card.id);

    return GestureDetector(
      onTap: () => _flipCard(card.id),
      onLongPress: () => _showCardOptions(card),
      child: AspectRatio(
        aspectRatio: _cardAspectRatio,
        child: AnimatedBuilder(
          animation: animation,
          builder: (_, __) {
            final angle = animation.value * math.pi;
            final isFrontVisible = angle <= math.pi / 2;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(angle),
              child: isFrontVisible
                  ? _buildCardFace(theme, card: card, isFront: true)
                  : Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(math.pi),
                      child: _buildCardFace(theme, card: card, isFront: false),
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCardFace(ThemeData theme,
      {required IdCard card, required bool isFront}) {
    final imagePath = isFront ? card.frontImagePath : card.backImagePath;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: imagePath == null
            ? LinearGradient(
                colors: isFront
                    ? [
                        theme.colorScheme.primary,
                        theme.colorScheme.primaryContainer,
                      ]
                    : [
                        theme.colorScheme.secondary,
                        theme.colorScheme.secondaryContainer,
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        image: imagePath != null
            ? DecorationImage(
                image: FileImage(File(imagePath)),
                fit: BoxFit.cover,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.18),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Scrim so text is readable over photos
          if (imagePath != null)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.5),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                // Placeholder icon when no photo
                if (imagePath == null)
                  Center(
                    child: Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 32,
                      color: _faceTextColor(null, isFront, theme)
                          .withOpacity(0.55),
                    ),
                  ),
                const Spacer(),
                // Label at bottom
                Text(
                  card.label,
                  style: TextStyle(
                    color: _faceTextColor(imagePath, isFront, theme),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    shadows: imagePath != null
                        ? [const Shadow(blurRadius: 4, color: Colors.black54)]
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _faceTextColor(String? imagePath, bool isFront, ThemeData theme) {
    if (imagePath != null) return Colors.white;
    return isFront
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSecondary;
  }

  // ── Note ──────────────────────────────────────────────────────────────────

  Widget _buildNote(ThemeData theme, int index) {
    final isDark = theme.brightness == Brightness.dark;
    final noteBackground =
        isDark ? const Color(0xFF2C2A1E) : const Color(0xFFFFFDE7);
    final noteBorder =
        isDark ? const Color(0xFF4A4730) : const Color(0xFFF9A825);
    final lineColor =
        isDark ? const Color(0xFF3D3B28) : const Color(0xFFE8EAF6);
    final isEditing = _noteEditing[index];

    return Container(
      decoration: BoxDecoration(
        color: noteBackground,
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: noteBorder, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 6,
            offset: const Offset(2, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Per-note toolbar row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: isEditing
                      ? _buildNoteToolbar(theme, lineColor, index)
                      : const SizedBox.shrink(),
                ),
                if (!isEditing) const Spacer(),
                IconButton(
                  tooltip: isEditing ? 'Done' : 'Edit',
                  icon: Icon(isEditing ? Icons.check : Icons.edit, size: 18),
                  onPressed: () {
                    setState(() => _noteEditing[index] = !isEditing);
                    if (isEditing) _saveNotePrefs();
                  },
                ),
                IconButton(
                  tooltip: 'Delete note',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Colors.red.shade300,
                  onPressed: () => _deleteNote(index),
                ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(4)),
            child: CustomPaint(
              painter: _LinedPaperPainter(lineColor: lineColor),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: isEditing
                    ? TextField(
                        controller: _noteControllers[index],
                        maxLines: null,
                        minLines: 6,
                        style: TextStyle(
                          fontSize: _noteFontSize[index],
                          fontWeight: _noteBold[index]
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontStyle: _noteItalic[index]
                              ? FontStyle.italic
                              : FontStyle.normal,
                          decoration: _noteUnderline[index]
                              ? TextDecoration.underline
                              : TextDecoration.none,
                          height: 1.8,
                          color: isDark ? Colors.white : Colors.grey.shade900,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Write a note…',
                          hintStyle: TextStyle(
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey.shade400),
                        ),
                        onChanged: (_) => _saveNotePrefs(),
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 60),
                        child: Text(
                          _noteControllers[index].text.isEmpty
                              ? 'Tap the pencil to add a note…'
                              : _noteControllers[index].text,
                          style: TextStyle(
                            fontSize: _noteFontSize[index],
                            fontWeight: _noteBold[index]
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontStyle: _noteItalic[index]
                                ? FontStyle.italic
                                : FontStyle.normal,
                            decoration: _noteUnderline[index]
                                ? TextDecoration.underline
                                : TextDecoration.none,
                            height: 1.8,
                            color: _noteControllers[index].text.isEmpty
                                ? (isDark
                                    ? Colors.white38
                                    : Colors.grey.shade400)
                                : (isDark
                                    ? Colors.white
                                    : Colors.grey.shade900),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteToolbar(ThemeData theme, Color lineColor, int index) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A3826) : const Color(0xFFFFF9C4),
        border: Border(bottom: BorderSide(color: lineColor, width: 1)),
      ),
      child: Row(
        children: [
          _NoteToolbarBtn(
            icon: Icons.format_bold,
            active: _noteBold[index],
            onTap: () => setState(() {
              _noteBold[index] = !_noteBold[index];
              _saveNotePrefs();
            }),
          ),
          _NoteToolbarBtn(
            icon: Icons.format_italic,
            active: _noteItalic[index],
            onTap: () => setState(() {
              _noteItalic[index] = !_noteItalic[index];
              _saveNotePrefs();
            }),
          ),
          _NoteToolbarBtn(
            icon: Icons.format_underline,
            active: _noteUnderline[index],
            onTap: () => setState(() {
              _noteUnderline[index] = !_noteUnderline[index];
              _saveNotePrefs();
            }),
          ),
          const SizedBox(width: 4),
          Container(width: 1, height: 20, color: lineColor),
          const SizedBox(width: 4),
          _NoteToolbarBtn(
            icon: Icons.text_decrease,
            active: false,
            onTap: () => setState(() {
              if (_noteFontSize[index] > 10) {
                _noteFontSize[index] -= 2;
                _saveNotePrefs();
              }
            }),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '${_noteFontSize[index].toInt()}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          _NoteToolbarBtn(
            icon: Icons.text_increase,
            active: false,
            onTap: () => setState(() {
              if (_noteFontSize[index] < 28) {
                _noteFontSize[index] += 2;
                _saveNotePrefs();
              }
            }),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// ignore: unused_element
class _NavArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _NavArrow(
      {required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.25,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _CardDot extends StatelessWidget {
  final bool active;
  const _CardDot({required this.active});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: active ? 20 : 7,
      height: 6,
      decoration: BoxDecoration(
        color: active ? color : color.withOpacity(0.3),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _NoteToolbarBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _NoteToolbarBtn(
      {required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 18, color: active ? color : Colors.grey),
      ),
    );
  }
}

class _LinedPaperPainter extends CustomPainter {
  final Color lineColor;
  const _LinedPaperPainter({required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.8;
    const lineSpacing = 28.8;
    var y = lineSpacing + 12;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      y += lineSpacing;
    }
  }

  @override
  bool shouldRepaint(_LinedPaperPainter old) => old.lineColor != lineColor;
}
