package at.uac.android.design

/** Measurements use the same labels, font, density and four-column width as the rendered tabs. */
internal fun useLargeTextNavigationGrid(
    fontScale: Float,
    fourColumnLineCounts: List<Int>,
): Boolean {
    if (!fontScale.isFinite() || fontScale <= 1.3f) return false
    if (fourColumnLineCounts.size != 4 || fourColumnLineCounts.any { it < 1 }) return true
    // The long organization name may occupy two lines; short tab names must remain whole.
    return fourColumnLineCounts[0] > 1 ||
        fourColumnLineCounts[1] > 1 ||
        fourColumnLineCounts[2] > 2 ||
        fourColumnLineCounts[3] > 1
}
