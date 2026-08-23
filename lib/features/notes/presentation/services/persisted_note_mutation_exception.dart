/// A mutation committed, but refreshing the in-memory note collection failed.
class PersistedNoteMutationException implements Exception {
  const PersistedNoteMutationException({
    required this.cause,
    required this.causeStackTrace,
  });

  final Object cause;
  final StackTrace causeStackTrace;

  @override
  String toString() => 'PersistedNoteMutationException: $cause';
}
