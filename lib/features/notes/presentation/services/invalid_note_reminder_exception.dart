class InvalidNoteReminderException implements Exception {
  const InvalidNoteReminderException();

  @override
  String toString() => 'The reminder must be in the future.';
}
