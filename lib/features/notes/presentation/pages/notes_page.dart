import 'package:flutter/material.dart';

import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_home_page.dart';

/// Compatibility entry point for callers that still import [NotesPage].
///
/// The mobile shell owns navigation and global actions; the modern home page
/// remains the single implementation of the active-notes experience.
class NotesPage extends StatelessWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context) => const NotesHomePage();
}
