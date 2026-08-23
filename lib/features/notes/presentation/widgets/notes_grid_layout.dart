int notesGridColumnCount(double viewportWidth) {
  if (viewportWidth < 360) return 1;
  if (viewportWidth < 700) return 2;
  return 3;
}

double notesGridHorizontalInset(double viewportWidth) {
  final gutter = viewportWidth >= 600 ? 24.0 : 16.0;
  return ((viewportWidth - 840) / 2).clamp(gutter, double.infinity).toDouble();
}
