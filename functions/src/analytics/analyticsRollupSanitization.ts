export function hasActiveRegionAnalytics(
  viewCount: number,
  contentKeyCount: number,
): boolean {
  return viewCount > 0 || contentKeyCount > 0;
}
