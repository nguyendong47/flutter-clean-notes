enum ReminderCommandOperation { schedule, cancel }

final class ReminderCommand {
  const ReminderCommand({
    required this.generation,
    required this.noteId,
    required this.operation,
    this.scheduledAt,
  });

  final int generation;
  final int noteId;
  final ReminderCommandOperation operation;
  final DateTime? scheduledAt;

  @override
  bool operator ==(Object other) {
    return other is ReminderCommand &&
        other.generation == generation &&
        other.noteId == noteId &&
        other.operation == operation &&
        other.scheduledAt == scheduledAt;
  }

  @override
  int get hashCode => Object.hash(generation, noteId, operation, scheduledAt);
}

final class PendingReminderNotification {
  const PendingReminderNotification.legacy({required this.notificationId})
    : generation = null;

  const PendingReminderNotification.v2({
    required this.notificationId,
    required this.generation,
  }) : assert(generation != null);

  final int notificationId;
  final int? generation;

  bool get isLegacy => generation == null;
}
