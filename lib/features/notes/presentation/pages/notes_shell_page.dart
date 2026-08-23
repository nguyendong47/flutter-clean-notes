import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_clean_notes/features/notes/presentation/widgets/more_actions_sheet.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/notes_bottom_bar.dart';

/// Hosts the persistent branch navigators and their shared mobile navigation.
class NotesShellPage extends StatelessWidget {
  const NotesShellPage({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NotesBottomBar(
        currentIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          FocusManager.instance.primaryFocus?.unfocus();
          navigationShell.goBranch(index, initialLocation: false);
        },
        onCreate: () => context.push('/note/new'),
        onMore: () {
          final rootContext = Navigator.of(
            context,
            rootNavigator: true,
          ).context;
          MoreActionsSheet.show(rootContext);
        },
      ),
    );
  }
}
