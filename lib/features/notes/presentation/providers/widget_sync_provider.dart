import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:flutter_clean_notes/features/notes/data/services/home_widget_sync_gateway.dart';
import 'package:flutter_clean_notes/features/notes/domain/services/widget_sync_gateway.dart';
import 'package:flutter_clean_notes/features/notes/domain/services/widget_sync_service.dart';

part 'widget_sync_provider.g.dart';

@Riverpod(keepAlive: true)
WidgetSyncGateway widgetSyncGateway(Ref ref) {
  return const HomeWidgetSyncGateway();
}

@Riverpod(keepAlive: true)
WidgetSyncService widgetSyncService(Ref ref) {
  return WidgetSyncService(gateway: ref.watch(widgetSyncGatewayProvider));
}
