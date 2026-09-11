import 'package:flutter_clean_notes/features/notes/domain/entities/widget_sync_payload.dart';

abstract interface class WidgetSyncGateway {
  Future<void> syncPayload(WidgetSyncPayload payload);
}
