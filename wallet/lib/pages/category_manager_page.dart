import 'package:flutter/material.dart';
import '../models/transaction_model.dart';

/// Category Manager — lets users view and (in the future) add/edit/hide
/// transaction categories and their icons.
///
/// Currently the category list is hard-coded in [kTransactionCategories].
/// To make this fully dynamic:
///   1. Add a `categories` table to [DatabaseHelper].
///   2. Load/save categories from the DB instead of the constant.
///   3. Pass the category list through to [WalletTransaction.showDialog].
class CategoryManagerPage extends StatefulWidget {
  const CategoryManagerPage({super.key});

  @override
  State<CategoryManagerPage> createState() => _CategoryManagerPageState();
}

class _CategoryManagerPageState extends State<CategoryManagerPage> {
  // Working copy — a future DB-backed version would load these asynchronously.
  final List<String> _categories = List.of(kTransactionCategories);

  void _showAddDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Category'),
        content: TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Category name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty && !_categories.contains(name)) {
                setState(() => _categories.add(name));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _deleteCategory(int index) {
    final cat = _categories[index];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Remove "$cat"? Existing transactions keep this label.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() => _categories.removeAt(index));
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Category Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add category',
            onPressed: _showAddDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Tap and hold to reorder. Swipe left to delete.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _categories.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _categories.removeAt(oldIndex);
                  _categories.insert(newIndex, item);
                });
              },
              itemBuilder: (_, i) {
                final cat = _categories[i];
                final icon =
                    kTransactionCategoryIcons[cat] ?? Icons.label_outline;
                return Dismissible(
                  key: Key('cat_$cat'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) async {
                    _deleteCategory(i);
                    return false; // let our dialog handle it
                  },
                  child: Card(
                    key: ValueKey('card_$cat'),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(icon,
                            color: theme.colorScheme.onPrimaryContainer,
                            size: 20),
                      ),
                      title: Text(cat,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      trailing: const Icon(Icons.drag_handle_outlined,
                          color: Colors.grey),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Category'),
      ),
    );
  }
}
