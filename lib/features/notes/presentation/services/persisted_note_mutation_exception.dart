enum PersistedNoteMutationFailureKind { refresh, reminderCancellation }

/// A mutation committed, but a post-commit side effect or refresh failed.
class PersistedNoteMutationException implements Exception {
  const PersistedNoteMutationException({
    required this.cause,
    required this.causeStackTrace,
    this.kind = PersistedNoteMutationFailureKind.refresh,
  });

  final Object cause;
  final StackTrace causeStackTrace;
  final PersistedNoteMutationFailureKind kind;

  @override
  String toString() => 'PersistedNoteMutationException: $cause';
}
