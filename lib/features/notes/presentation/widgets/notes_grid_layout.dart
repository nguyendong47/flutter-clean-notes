int notesGridColumnCount(double viewportWidth) {
  if (viewportWidth < 360) return 1;
  if (viewportWidth < 700) return 2;
  return 3;
}
