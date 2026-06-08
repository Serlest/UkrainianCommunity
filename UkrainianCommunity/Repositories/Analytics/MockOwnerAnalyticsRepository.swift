import Foundation

struct MockOwnerAnalyticsRepository: OwnerAnalyticsRepository {
    var snapshotsByPeriod: [AnalyticsPeriod: OwnerAnalyticsSnapshot]
    var contentDetailsByKey: [String: AnalyticsContentDetailSnapshot]
    var organizationDetailsByKey: [String: AnalyticsOrganizationDetailSnapshot]

    init(
        snapshotsByPeriod: [AnalyticsPeriod: OwnerAnalyticsSnapshot] = Self.sampleSnapshots,
        contentDetailsByKey: [String: AnalyticsContentDetailSnapshot] = Self.sampleContentDetails,
        organizationDetailsByKey: [String: AnalyticsOrganizationDetailSnapshot] = Self.sampleOrganizationDetails
    ) {
        self.snapshotsByPeriod = snapshotsByPeriod
        self.contentDetailsByKey = contentDetailsByKey
        self.organizationDetailsByKey = organizationDetailsByKey
    }

    func fetchSnapshot(period: AnalyticsPeriod) async throws -> OwnerAnalyticsSnapshot {
        snapshotsByPeriod[period] ?? .empty(period: period)
    }

    func fetchContentDetail(
        period: AnalyticsPeriod,
        contentID: String,
        contentType: AnalyticsContentType
    ) async throws -> AnalyticsContentDetailSnapshot {
        contentDetailsByKey[Self.contentDetailKey(period: period, contentID: contentID, contentType: contentType)]
            ?? .empty(period: period, contentID: contentID, contentType: contentType)
    }

    func fetchOrganizationDetail(
        period: AnalyticsPeriod,
        organizationID: String
    ) async throws -> AnalyticsOrganizationDetailSnapshot {
        organizationDetailsByKey[Self.organizationDetailKey(period: period, organizationID: organizationID)]
            ?? .empty(period: period, organizationID: organizationID)
    }
}

extension MockOwnerAnalyticsRepository {
    static var sampleSnapshots: [AnalyticsPeriod: OwnerAnalyticsSnapshot] {
        Dictionary(uniqueKeysWithValues: AnalyticsPeriod.allCases.map { period in
            (period, sampleSnapshot(for: period))
        })
    }

    static var sampleContentDetails: [String: AnalyticsContentDetailSnapshot] {
        Dictionary(uniqueKeysWithValues: AnalyticsPeriod.allCases.flatMap { period in
            sampleContentDetails(for: period).map { snapshot in
                (contentDetailKey(period: period, contentID: snapshot.contentID, contentType: snapshot.contentType), snapshot)
            }
        })
    }

    static var sampleOrganizationDetails: [String: AnalyticsOrganizationDetailSnapshot] {
        Dictionary(uniqueKeysWithValues: AnalyticsPeriod.allCases.flatMap { period in
            sampleOrganizationDetails(for: period).map { snapshot in
                (organizationDetailKey(period: period, organizationID: snapshot.organizationID), snapshot)
            }
        })
    }

    static func sampleSnapshot(for period: AnalyticsPeriod) -> OwnerAnalyticsSnapshot {
        let totalViews = 428 * period.dayCount
        let newsViews = 134 * period.dayCount
        let eventViews = 96 * period.dayCount
        let organizationViews = 88 * period.dayCount
        let guideArticleViews = 110 * period.dayCount

        return OwnerAnalyticsSnapshot(
            period: period,
            generatedAt: Date(),
            summaryStats: [
                AnalyticsSummaryStats(metricType: .totalViews, value: totalViews, previousValue: max(0, totalViews - 312)),
                AnalyticsSummaryStats(metricType: .newsViews, value: newsViews, previousValue: max(0, newsViews - 74)),
                AnalyticsSummaryStats(metricType: .eventViews, value: eventViews, previousValue: max(0, eventViews - 41)),
                AnalyticsSummaryStats(metricType: .organizationViews, value: organizationViews, previousValue: max(0, organizationViews - 36)),
                AnalyticsSummaryStats(metricType: .guideArticleViews, value: guideArticleViews, previousValue: max(0, guideArticleViews - 58)),
                AnalyticsSummaryStats(metricType: .activeRegions, value: 6, previousValue: 5)
            ],
            dailyStats: sampleDailyStats(period: period),
            topContent: sampleTopContent(period: period),
            regionStats: sampleRegionStats(period: period),
            userStats: sampleUserStats(period: period),
            actionStats: sampleActionStats(period: period)
        )
    }

    private static func sampleDailyStats(period: AnalyticsPeriod) -> [AnalyticsDailyStats] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<period.dayCount).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let index = period.dayCount - offset
            return AnalyticsDailyStats(
                date: date,
                metrics: [
                    .newsViews: 112 + index * 6,
                    .eventViews: 74 + index * 4,
                    .organizationViews: 63 + index * 3,
                    .guideArticleViews: 91 + index * 5,
                    .totalViews: 340 + index * 18,
                    .activeRegions: min(6, 3 + index % 4),
                    .totalLikes: 18 + index * 2,
                    .totalBookmarks: 12 + index,
                    .eventRegistrations: 9 + index,
                    .cancelledEventRegistrations: max(1, index / 2),
                    .organizationFollows: 7 + index,
                    .organizationUnfollows: max(1, index / 3)
                ]
            )
        }
    }

    private static func sampleTopContent(period: AnalyticsPeriod) -> [AnalyticsTopContentItem] {
        let multiplier = max(1, period.dayCount)
        return [
            AnalyticsTopContentItem(
                contentID: "guide-anmeldung-first-steps",
                contentType: .guideArticle,
                title: "First steps after arriving in Austria",
                category: GuideCategory.firstSteps.rawValue,
                regionScope: .federalState,
                federalState: .wien,
                viewCount: 86 * multiplier,
                rank: 1
            ),
            AnalyticsTopContentItem(
                contentID: "event-community-consultation-tirol",
                contentType: .event,
                title: "Community consultation evening in Innsbruck",
                category: EventCategory.meetups.rawValue,
                organizationID: "org-ukrainian-help-tirol",
                organizationName: "Ukrainian Help Tirol",
                regionScope: .federalState,
                federalState: .tirol,
                viewCount: 64 * multiplier,
                rank: 2
            ),
            AnalyticsTopContentItem(
                contentID: "news-language-courses-update",
                contentType: .news,
                title: "New German language course dates",
                category: NewsCategory.education.rawValue,
                organizationID: "org-ukrainian-center-vienna",
                organizationName: "Ukrainian Community Center Vienna",
                regionScope: .federalState,
                federalState: .wien,
                viewCount: 58 * multiplier,
                rank: 3
            ),
            AnalyticsTopContentItem(
                contentID: "org-ukrainian-center-vienna",
                contentType: .organization,
                title: "Ukrainian Community Center Vienna",
                category: nil,
                organizationID: "org-ukrainian-center-vienna",
                organizationName: "Ukrainian Community Center Vienna",
                regionScope: .federalState,
                federalState: .wien,
                viewCount: 47 * multiplier,
                rank: 4
            ),
            AnalyticsTopContentItem(
                contentID: "news-volunteer-network-linz",
                contentType: .news,
                title: "Volunteer network expands in Linz",
                category: "community",
                organizationID: "org-linz-help",
                organizationName: "Linz Help Hub",
                regionScope: .federalState,
                federalState: .oberoesterreich,
                viewCount: 42 * multiplier,
                rank: 5
            ),
            AnalyticsTopContentItem(
                contentID: "8CF5A7D2-5E42-4C88-A1B0-7B7B5F5F5C11",
                contentType: .news,
                title: "8CF5A7D2-5E42-4C88-A1B0-7B7B5F5F5C11",
                category: "other",
                regionScope: .federalState,
                federalState: .steiermark,
                viewCount: 39 * multiplier,
                rank: 6
            ),
            AnalyticsTopContentItem(
                contentID: "event-family-day-salzburg",
                contentType: .event,
                title: "Family support day in Salzburg",
                category: "family",
                organizationID: "org-salzburg-community",
                organizationName: "Salzburg Ukrainian Community",
                regionScope: .federalState,
                federalState: .salzburg,
                viewCount: 36 * multiplier,
                rank: 7
            ),
            AnalyticsTopContentItem(
                contentID: "org-graz-culture-club",
                contentType: .organization,
                title: "Graz Culture Club",
                category: nil,
                organizationID: "org-graz-culture-club",
                organizationName: "Graz Culture Club",
                regionScope: .federalState,
                federalState: .steiermark,
                viewCount: 34 * multiplier,
                rank: 8
            ),
            AnalyticsTopContentItem(
                contentID: "guide-school-enrollment",
                contentType: .guideArticle,
                title: "School enrollment checklist",
                category: GuideCategory.education.rawValue,
                regionScope: .austria,
                federalState: nil,
                viewCount: 31 * multiplier,
                rank: 9
            )
        ]
    }

    private static func sampleRegionStats(period: AnalyticsPeriod) -> [AnalyticsRegionStats] {
        let multiplier = max(1, period.dayCount)
        return [
            AnalyticsRegionStats(regionScope: .federalState, federalState: .wien, viewCount: 118 * multiplier, contentCount: 18, metrics: [.newsViews: 42 * multiplier, .eventViews: 22 * multiplier, .organizationViews: 18 * multiplier, .guideArticleViews: 36 * multiplier]),
            AnalyticsRegionStats(regionScope: .federalState, federalState: .tirol, viewCount: 92 * multiplier, contentCount: 14, metrics: [.newsViews: 24 * multiplier, .eventViews: 28 * multiplier, .organizationViews: 16 * multiplier, .guideArticleViews: 24 * multiplier]),
            AnalyticsRegionStats(regionScope: .federalState, federalState: .niederoesterreich, viewCount: 76 * multiplier, contentCount: 10, metrics: [.newsViews: 20 * multiplier, .eventViews: 18 * multiplier, .organizationViews: 14 * multiplier, .guideArticleViews: 24 * multiplier]),
            AnalyticsRegionStats(regionScope: .federalState, federalState: .oberoesterreich, viewCount: 61 * multiplier, contentCount: 9, metrics: [.newsViews: 16 * multiplier, .eventViews: 13 * multiplier, .organizationViews: 12 * multiplier, .guideArticleViews: 20 * multiplier]),
            AnalyticsRegionStats(regionScope: .austria, federalState: nil, viewCount: 54 * multiplier, contentCount: 12, metrics: [.newsViews: 18 * multiplier, .eventViews: 10 * multiplier, .organizationViews: 8 * multiplier, .guideArticleViews: 18 * multiplier]),
            AnalyticsRegionStats(regionScope: .federalState, federalState: .steiermark, viewCount: 48 * multiplier, contentCount: 8, metrics: [.newsViews: 14 * multiplier, .eventViews: 9 * multiplier, .organizationViews: 10 * multiplier, .guideArticleViews: 15 * multiplier]),
            AnalyticsRegionStats(regionScope: .federalState, federalState: .salzburg, viewCount: 37 * multiplier, contentCount: 7, metrics: [.newsViews: 10 * multiplier, .eventViews: 12 * multiplier, .organizationViews: 5 * multiplier, .guideArticleViews: 10 * multiplier]),
            AnalyticsRegionStats(regionScope: .federalState, federalState: .kaernten, viewCount: 26 * multiplier, contentCount: 5, metrics: [.newsViews: 7 * multiplier, .eventViews: 6 * multiplier, .guideArticleViews: 13 * multiplier]),
            AnalyticsRegionStats(regionScope: .federalState, federalState: .vorarlberg, viewCount: 18 * multiplier, contentCount: 4, metrics: [.newsViews: 5 * multiplier, .organizationViews: 4 * multiplier, .guideArticleViews: 9 * multiplier]),
            AnalyticsRegionStats(regionScope: .federalState, federalState: .burgenland, viewCount: 12 * multiplier, contentCount: 3, metrics: [.newsViews: 4 * multiplier, .eventViews: 3 * multiplier, .guideArticleViews: 5 * multiplier])
        ]
    }

    private static func sampleActionStats(period: AnalyticsPeriod) -> AnalyticsActionStats {
        let dailyStats = sampleDailyStats(period: period)
        return AnalyticsActionStats(
            totalLikes: dailyStats.map { $0.value(for: .totalLikes) }.reduce(0, +),
            totalBookmarks: dailyStats.map { $0.value(for: .totalBookmarks) }.reduce(0, +),
            eventRegistrations: dailyStats.map { $0.value(for: .eventRegistrations) }.reduce(0, +),
            cancelledEventRegistrations: dailyStats.map { $0.value(for: .cancelledEventRegistrations) }.reduce(0, +),
            organizationFollows: dailyStats.map { $0.value(for: .organizationFollows) }.reduce(0, +),
            organizationUnfollows: dailyStats.map { $0.value(for: .organizationUnfollows) }.reduce(0, +)
        )
    }

    private static func sampleUserStats(period: AnalyticsPeriod) -> AnalyticsUserStats {
        let multiplier = max(1, period.dayCount)
        return AnalyticsUserStats(
            totalUsers: 1840,
            newRegistrations: 18 * multiplier,
            deletedAccounts: max(1, multiplier / 4),
            blockedUsers: 12,
            deactivatedUsers: 21,
            activeUsersToday: 142,
            activeUsersSevenDays: 486,
            activeUsersThirtyDays: 1048,
            usersByFederalState: [
                .wien: 620,
                .tirol: 280,
                .niederoesterreich: 248,
                .oberoesterreich: 214,
                .steiermark: 174
            ]
        )
    }

    private static func sampleContentDetails(for period: AnalyticsPeriod) -> [AnalyticsContentDetailSnapshot] {
        let multiplier = max(1, period.dayCount)
        return [
            AnalyticsContentDetailSnapshot(
                period: period,
                contentID: "news-language-courses-update",
                contentType: .news,
                title: "New German language course dates",
                organizationID: "org-ukrainian-center-vienna",
                organizationName: "Ukrainian Community Center Vienna",
                category: NewsCategory.education.rawValue,
                federalState: .wien,
                regionScope: .federalState,
                metrics: AnalyticsContentDetailMetrics(
                    views: 58 * multiplier,
                    likes: 17 * multiplier,
                    bookmarks: 11 * multiplier,
                    registrations: 0,
                    cancelledRegistrations: 0,
                    follows: 0,
                    unfollows: 0
                ),
                regions: sampleDetailRegions(multiplier: multiplier),
                updatedAt: Date()
            ),
            AnalyticsContentDetailSnapshot(
                period: period,
                contentID: "event-community-consultation-tirol",
                contentType: .event,
                title: "Community consultation evening in Innsbruck",
                organizationID: "org-ukrainian-help-tirol",
                organizationName: "Ukrainian Help Tirol",
                category: EventCategory.meetups.rawValue,
                federalState: .tirol,
                regionScope: .federalState,
                metrics: AnalyticsContentDetailMetrics(
                    views: 64 * multiplier,
                    likes: 0,
                    bookmarks: 8 * multiplier,
                    registrations: 24 * multiplier,
                    cancelledRegistrations: 3 * multiplier,
                    follows: 0,
                    unfollows: 0
                ),
                regions: [
                    AnalyticsDetailRegionStats(regionScope: .federalState, federalState: .tirol, metrics: ["views": 42 * multiplier, "registrations": 18 * multiplier]),
                    AnalyticsDetailRegionStats(regionScope: .federalState, federalState: .wien, metrics: ["views": 14 * multiplier, "registrations": 4 * multiplier])
                ],
                updatedAt: Date()
            ),
            AnalyticsContentDetailSnapshot(
                period: period,
                contentID: "8CF5A7D2-5E42-4C88-A1B0-7B7B5F5F5C11",
                contentType: .news,
                title: "",
                organizationID: nil,
                organizationName: nil,
                category: "other",
                federalState: .steiermark,
                regionScope: .federalState,
                metrics: AnalyticsContentDetailMetrics(
                    views: 39 * multiplier,
                    likes: 3 * multiplier,
                    bookmarks: 2 * multiplier,
                    registrations: 0,
                    cancelledRegistrations: 0,
                    follows: 0,
                    unfollows: 0
                ),
                regions: [
                    AnalyticsDetailRegionStats(regionScope: .federalState, federalState: .steiermark, metrics: ["views": 39 * multiplier])
                ],
                updatedAt: Date()
            )
        ]
    }

    private static func sampleOrganizationDetails(for period: AnalyticsPeriod) -> [AnalyticsOrganizationDetailSnapshot] {
        let multiplier = max(1, period.dayCount)
        return [
            AnalyticsOrganizationDetailSnapshot(
                period: period,
                organizationID: "org-ukrainian-center-vienna",
                organizationName: "Ukrainian Community Center Vienna",
                federalState: .wien,
                regionScope: .federalState,
                metrics: AnalyticsOrganizationDetailMetrics(
                    profileViews: 47 * multiplier,
                    follows: 12 * multiplier,
                    unfollows: max(1, multiplier / 2),
                    bookmarks: 9 * multiplier,
                    newsViews: 86 * multiplier,
                    eventViews: 31 * multiplier,
                    eventRegistrations: 14 * multiplier
                ),
                topNews: [
                    AnalyticsOrganizationTopContentItem(
                        contentID: "news-language-courses-update",
                        contentType: .news,
                        title: "New German language course dates",
                        category: NewsCategory.education.rawValue,
                        federalState: .wien,
                        regionScope: .federalState,
                        metrics: ["views": 58 * multiplier, "likes": 17 * multiplier, "bookmarks": 11 * multiplier]
                    ),
                    AnalyticsOrganizationTopContentItem(
                        contentID: "news-community-office-hours",
                        contentType: .news,
                        title: "Community office hours this week",
                        category: NewsCategory.news.rawValue,
                        federalState: .wien,
                        regionScope: .federalState,
                        metrics: ["views": 28 * multiplier, "bookmarks": 5 * multiplier]
                    )
                ],
                topEvents: [
                    AnalyticsOrganizationTopContentItem(
                        contentID: "event-vienna-language-night",
                        contentType: .event,
                        title: "Language practice evening",
                        category: EventCategory.meetups.rawValue,
                        federalState: .wien,
                        regionScope: .federalState,
                        metrics: ["views": 31 * multiplier, "registrations": 14 * multiplier]
                    )
                ],
                regions: sampleDetailRegions(multiplier: multiplier),
                updatedAt: Date()
            )
        ]
    }

    private static func sampleDetailRegions(multiplier: Int) -> [AnalyticsDetailRegionStats] {
        [
            AnalyticsDetailRegionStats(regionScope: .federalState, federalState: .wien, metrics: ["views": 44 * multiplier, "likes": 12 * multiplier, "bookmarks": 8 * multiplier]),
            AnalyticsDetailRegionStats(regionScope: .federalState, federalState: .tirol, metrics: ["views": 16 * multiplier, "likes": 4 * multiplier]),
            AnalyticsDetailRegionStats(regionScope: .federalState, federalState: .oberoesterreich, metrics: ["views": 9 * multiplier, "bookmarks": 3 * multiplier])
        ]
    }

    private static func contentDetailKey(
        period: AnalyticsPeriod,
        contentID: String,
        contentType: AnalyticsContentType
    ) -> String {
        "\(period.rawValue):\(contentType.rawValue):\(contentID)"
    }

    private static func organizationDetailKey(period: AnalyticsPeriod, organizationID: String) -> String {
        "\(period.rawValue):\(organizationID)"
    }
}
