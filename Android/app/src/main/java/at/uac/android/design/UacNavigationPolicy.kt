package at.uac.android.design

/** Measurements use the same labels, font, density and four-column width as the rendered tabs. */
internal fun useLargeTextNavigationGrid(
    fontScale: Float,
    fourColumnLineCounts: List<Int>,
): Boolean {
    if (!fontScale.isFinite() || fontScale <= 1.3f) return false
    if (fourColumnLineCounts.size != 4 || fourColumnLineCounts.any { it < 1 }) return true
    // Material navigation labels should not split inside a word. At large text, move to the
    // existing two-by-two presentation as soon as any four-column label needs another line.
    return fourColumnLineCounts.any { it > 1 }
}
