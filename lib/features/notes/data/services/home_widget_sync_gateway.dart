import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/widget_sync_payload.dart';
import 'package:flutter_clean_notes/features/notes/domain/services/widget_sync_gateway.dart';

class HomeWidgetSyncGateway implements WidgetSyncGateway {
  const HomeWidgetSyncGateway({
    this.groupId = 'group.com.cleannotes.app',
    this.quickActionsWidgetName = 'QuickActionsWidget',
    this.pinnedNoteWidgetName = 'PinnedNoteWidget',
  });

  final String groupId;
  final String quickActionsWidgetName;
  final String pinnedNoteWidgetName;

  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<void> syncPayload(WidgetSyncPayload payload) async {
    if (!isSupportedPlatform) return;

    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await HomeWidget.setAppGroupId(groupId);
      }

      await HomeWidget.saveWidgetData<bool>(
        'widget_has_pinned',
        payload.hasPinned,
      );
      await HomeWidget.saveWidgetData<String>(
        'widget_pinned_id',
        payload.noteId?.toString() ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        'widget_pinned_title',
        payload.title,
      );
      await HomeWidget.saveWidgetData<String>(
        'widget_pinned_content',
        payload.contentPreview,
      );
      await HomeWidget.saveWidgetData<String>(
        'widget_pinned_checklist',
        payload.toMap()['checklistJson'] as String,
      );
      await HomeWidget.saveWidgetData<int>(
        'widget_pinned_color',
        payload.colorValue,
      );
      await HomeWidget.saveWidgetData<String>(
        'widget_pinned_updated_at',
        payload.updatedAt?.toIso8601String() ?? '',
      );

      await HomeWidget.updateWidget(
        name: quickActionsWidgetName,
        androidName: quickActionsWidgetName,
        iOSName: quickActionsWidgetName,
      );
      await HomeWidget.updateWidget(
        name: pinnedNoteWidgetName,
        androidName: pinnedNoteWidgetName,
        iOSName: pinnedNoteWidgetName,
      );
    } catch (_) {
      // Platform communication failures do not block core app operations
    }
  }
}
