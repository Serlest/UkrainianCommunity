const retiredGuideAnalyticsValues = new Set([
  "guide",
  "guidearticle",
  "guide_article",
  "guidearticleviews",
  "guide_article_view",
  "guideviews",
  "guide_views",
]);

export function countGuideAnalyticsMarkers(value) {
  if (Array.isArray(value)) {
    return value.reduce((total, item) => total + countGuideAnalyticsMarkers(item), 0);
  }

  if (value && typeof value === "object") {
    return Object.entries(value).reduce(
      (total, [key, item]) => total
        + (isRetiredGuideAnalyticsValue(key) ? 1 : 0)
        + countGuideAnalyticsMarkers(item),
      0
    );
  }

  if (typeof value !== "string") {
    return 0;
  }

  return isRetiredGuideAnalyticsValue(value) ? 1 : 0;
}

function isRetiredGuideAnalyticsValue(value) {
  const normalized = value.trim().toLowerCase();
  return retiredGuideAnalyticsValues.has(normalized)
    || normalized.startsWith("guidearticle_")
    || normalized.startsWith("guide_article_");
}
