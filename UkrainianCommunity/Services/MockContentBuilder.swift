import Foundation

enum MockContentBuilder {
    nonisolated static func notificationDetailFixtures() -> [String: [AppNotification]] {
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing"),
              ProcessInfo.processInfo.environment["UITestNotificationDetails"] == "1" else { return [:] }
        // Mock repositories initialize before the app applies its test language setting.
        let language = ProcessInfo.processInfo.environment["UITestAppLanguage"] ?? "de"
        let bundle = Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        func fixtureText(_ key: String, _ fallback: String) -> String {
            bundle.localizedString(forKey: key, value: fallback, table: nil)
        }
        let userID = currentUser().id
        let message = fixtureText("mock.event.1.details", "An evening for networking, announcements, and practical orientation for families living in Tirol. Tea, children’s corner, and language support will be available.")
        return [userID: [
            AppNotification(id: "detail-info", recipientUserId: userID, type: .systemAnnouncement,
                sourceType: .system, sourceId: "", title: fixtureText("mock.event.1.title", "Ukrainian Community Evening"),
                message: Array(repeating: message, count: 4).joined(separator: "\n\n"),
                actorDisplayName: "Community Team", payload: [:], isRead: false, readAt: nil, createdAt: .now),
            AppNotification(id: "detail-event", recipientUserId: userID, type: .eventUpdated,
                sourceType: .event, sourceId: "event-1", actionType: .openEvent, actionTargetId: "event-1",
                message: message, payload: [:], isRead: false, readAt: nil, createdAt: .now.addingTimeInterval(-60))
        ]]
    }

    @MainActor
    static func userManagementRefreshFixture() -> UserManagementReads? {
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing"),
              ProcessInfo.processInfo.environment["UITestUserRefresh"] == "1" else { return nil }
        var presenceReads = 0
        var userReads = 0
        let failOnce = ProcessInfo.processInfo.environment["UITestUserRefreshFailure"] == "1"
        return UserManagementReads(users: { _ in
            .init(users: [currentUser(), ownerUser()], cursor: nil, hasMore: false)
        }, user: { _ in
            userReads += 1
            try await Task.sleep(for: .milliseconds(700))
            if failOnce && userReads == 1 { throw AppError.network }
            let member = currentUser()
            return AppUser(id: member.id, fullName: member.fullName, displayName: "Olena (updated)",
                city: member.city, email: member.email, bio: member.bio, role: member.role,
                blockState: member.blockState, createdAt: member.createdAt, updatedAt: .now)
        }, organizations: { [] }, securityMetadata: { id in
            ManagedUserSecurityMetadata(response: .init(targetUserId: id, emailVerified: true,
                authDisabled: false, creationTime: nil, lastSignInTime: nil, providerIds: ["password"]))
        }, presence: { id in
            presenceReads += 1
            try await Task.sleep(for: .milliseconds(700))
            if failOnce && presenceReads == 2 { throw AppError.network }
            let now = Date().timeIntervalSince1970 * 1_000
            return ManagedUserPresenceSnapshot(response: .init(targetUserId: id, lastSeenAt: now,
                onlineUntil: presenceReads == 1 ? now + 90_000 : nil, serverTime: now), requestStartedAt: .now)
        })
    }

    nonisolated private static let calendar = Calendar.current

    nonisolated static func currentUser() -> AppUser {
        AppUser(
            id: "user-1",
            fullName: localized("mock.user.name", "Olena Koval"),
            displayName: localized("mock.user.display_name", "Olena"),
            city: localized("mock.city.innsbruck", "Innsbruck"),
            email: "olena@example.com",
            bio: localized("mock.user.bio", "Helping newly arrived families find events, support, and trusted local services in Tirol."),
            telegramUsername: "olena_tirol",
            role: .moderator,
            blockState: .active,
            selectedFederalState: .tirol,
            acceptedTermsAt: calendar.date(byAdding: .month, value: -8, to: .now),
            acceptedPrivacyAt: calendar.date(byAdding: .month, value: -8, to: .now),
            acceptedTermsVersion: AuthService.currentTermsVersion,
            acceptedPrivacyVersion: AuthService.currentPrivacyVersion,
            createdAt: calendar.date(byAdding: .month, value: -8, to: .now) ?? .now,
            updatedAt: calendar.date(byAdding: .day, value: -2, to: .now) ?? .now
        )
    }

    nonisolated static func ownerUser() -> AppUser {
        AppUser(
            id: "owner-1",
            fullName: localized("mock.owner.name", "Platform Owner"),
            displayName: localized("mock.owner.display_name", "Owner"),
            city: localized("mock.city.vienna", "Vienna"),
            email: "owner@example.com",
            bio: localized("mock.owner.bio", "Responsible for platform quality, safety, and community operations."),
            role: .owner,
            globalRole: .owner,
            blockState: .active,
            selectedFederalState: .wien,
            acceptedTermsAt: calendar.date(byAdding: .year, value: -1, to: .now),
            acceptedPrivacyAt: calendar.date(byAdding: .year, value: -1, to: .now),
            acceptedTermsVersion: AuthService.currentTermsVersion,
            acceptedPrivacyVersion: AuthService.currentPrivacyVersion,
            createdAt: calendar.date(byAdding: .year, value: -1, to: .now) ?? .now,
            updatedAt: .now
        )
    }

    nonisolated static func newsPosts() -> [NewsPost] {
        let organizations = organizations()

        return [
            NewsPost(
                id: "news-1",
                title: localized("mock.news.1.title", "Community center opens weekly legal support hours"),
                subtitle: localized("mock.news.1.subtitle", "Free consultations for residence, work, and family questions."),
                regionScope: .federalState,
                federalState: .tirol,
                city: localized("mock.city.innsbruck", "Innsbruck"),
                source: ContentSourceMetadata(
                    sourceType: .organization,
                    organizationId: organizations[0].id,
                    organizationName: organizations[0].name,
                    organizationImageURL: organizations[0].imageURL
                ),
                body: localized("mock.news.1.body", "Starting this week, volunteer advisors will be available every Thursday evening in Innsbruck. The format is informal and designed for Ukrainian families who need orientation on everyday legal matters."),
                authorName: localized("mock.author.community", "Community Team"),
                publishedAt: calendar.date(byAdding: .day, value: -1, to: .now) ?? .now,
                createdAt: calendar.date(byAdding: .day, value: -3, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .day, value: -1, to: .now) ?? .now,
                comments: sampleComments(),
                moderationStatus: .approved,
                likeCount: 24,
                likeState: .liked
            ),
            NewsPost(
                id: "news-2",
                title: localized("mock.news.2.title", "School enrollment guide for new arrivals updated"),
                subtitle: localized("mock.news.2.subtitle", "A practical overview for primary and secondary education in Tirol."),
                regionScope: .federalState,
                federalState: .tirol,
                city: nil,
                source: ContentSourceMetadata(
                    sourceType: .organization,
                    organizationId: organizations[0].id,
                    organizationName: organizations[0].name,
                    organizationImageURL: organizations[0].imageURL
                ),
                body: localized("mock.news.2.body", "The updated guide includes enrollment steps, language support options, and links to local counseling services. It is intended as a starting point before contacting the school administration directly."),
                authorName: localized("mock.author.education", "Education Desk"),
                publishedAt: calendar.date(byAdding: .day, value: -3, to: .now) ?? .now,
                createdAt: calendar.date(byAdding: .day, value: -5, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .day, value: -3, to: .now) ?? .now,
                comments: Array(sampleComments().prefix(1)),
                moderationStatus: .pendingReview,
                likeCount: 15,
                likeState: .notLiked
            )
        ]
    }

    nonisolated static func events() -> [Event] {
        let organizations = organizations()

        return [
            Event(
                id: "event-1",
                title: localized("mock.event.1.title", "Ukrainian Community Evening"),
                summary: localized("mock.event.1.summary", "Meet neighbors, volunteers, and local organizations in one place."),
                details: localized("mock.event.1.details", "An evening for networking, announcements, and practical orientation for families living in Tirol. Tea, children’s corner, and language support will be available."),
                regionScope: .city,
                federalState: .tirol,
                source: ContentSourceMetadata(
                    sourceType: .organization,
                    organizationId: organizations[0].id,
                    organizationName: organizations[0].name,
                    organizationImageURL: organizations[0].imageURL
                ),
                city: localized("mock.city.innsbruck", "Innsbruck"),
                venue: localized("mock.event.1.venue", "Haus der Begegnung"),
                startDate: calendar.date(byAdding: .day, value: 4, to: .now) ?? .now,
                endDate: calendar.date(byAdding: .day, value: 4, to: .now.addingTimeInterval(7_200)) ?? .now,
                createdAt: calendar.date(byAdding: .day, value: -7, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .day, value: -1, to: .now) ?? .now,
                capacity: 120,
                registeredCount: 78,
                comments: sampleComments(),
                moderationStatus: .approved,
                registrationState: .registered,
                likeCount: 31,
                likeState: .liked
            ),
            Event(
                id: "event-2",
                title: localized("mock.event.2.title", "Career Workshop in Kufstein"),
                summary: localized("mock.event.2.summary", "CV review and Austrian job market basics."),
                details: localized("mock.event.2.details", "Local mentors will review CVs, explain application expectations, and share practical job search tips for Tirol."),
                regionScope: .city,
                federalState: .tirol,
                source: ContentSourceMetadata(sourceType: .app),
                city: localized("mock.city.kufstein", "Kufstein"),
                venue: localized("mock.event.2.venue", "Start Nucleus"),
                startDate: calendar.date(byAdding: .day, value: 10, to: .now) ?? .now,
                endDate: calendar.date(byAdding: .day, value: 10, to: .now.addingTimeInterval(5_400)) ?? .now,
                createdAt: calendar.date(byAdding: .day, value: -2, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .day, value: -2, to: .now) ?? .now,
                capacity: 40,
                registeredCount: 34,
                comments: [],
                moderationStatus: .draft,
                registrationState: .notRegistered,
                likeCount: 12,
                likeState: .notLiked
            )
        ]
    }

    nonisolated static func organizations() -> [Organization] {
        [
            Organization(
                id: "org-1",
                name: localized("mock.org.1.name", "Ukrainian House Tirol"),
                description: localized("mock.org.1.description", "Community support, language exchange, and cultural events. Building a stable support network for Ukrainians in Tirol through information, cultural continuity, and local partnerships."),
                regionScope: .city,
                federalState: .tirol,
                city: localized("mock.city.innsbruck", "Innsbruck"),
                imageURL: nil,
                contactEmail: "hello@example.org",
                phone: "+43 512 123456",
                website: "Support-URL: https://example.org/ukrainian-house-tirol",
                address: "Museumstraße 1",
                organizationType: "culture",
                directoryProfile: OrganizationDirectoryProfile(
                    profileKind: .community, secondaryCategories: ["education", "support"],
                    serviceModes: [.inStore, .online], serviceArea: "Tirol / Österreich",
                    regularHours: ["monday": "09:00-18:00", "sunday": "closed"],
                    specialHoursNote: "Termine nach Vereinbarung",
                    services: ["Sprachberatung", "Kulturveranstaltungen"],
                    orderURL: "https://example.org/order", bookingURL: "https://example.org/booking",
                    currentOfferDetails: "Kostenlose Erstberatung ohne Angebotstitel",
                    currentOfferURL: "https://example.org/offer",
                    currentOfferValidUntil: calendar.date(byAdding: .day, value: 30, to: .now)
                ),
                foundedYear: 2026,
                foundedMonth: 5,
                languages: ["Українська", "Deutsch"],
                telegramURL: "https://t.me/ukrainian_house",
                donationURL: "https://example.org/support",
                facebookURL: "https://facebook.com/ukrainian_house",
                instagramURL: "https://instagram.com/ukrainian_house",
                whatsappURL: "https://wa.me/43512123456",
                youtubeURL: "https://youtube.com/@ukrainian_house",
                linkedinURL: "https://linkedin.com/company/ukrainian-house",
                missionStatement: "Gemeinschaft und gegenseitige Unterstützung",
                contactPerson: "Community Team",
                createdAt: calendar.date(byAdding: .month, value: -10, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .day, value: -5, to: .now) ?? .now,
                moderationStatus: .approved,
                likeCount: 19,
                likeState: .notLiked
            ),
            Organization(
                id: "org-2",
                name: localized("mock.org.2.name", "Tirol Volunteer Network"),
                description: localized("mock.org.2.description", "Volunteer coordination for transport, translation, and everyday help. Connecting volunteers and families quickly for practical, low-friction support across Tirol."),
                regionScope: .city,
                federalState: .tirol,
                city: localized("mock.city.hall", "Hall in Tirol"),
                imageURL: nil,
                contactEmail: "support@example.org",
                website: "https://example.org/volunteer-network",
                foundedYear: 2025,
                foundedMonth: 9,
                createdAt: calendar.date(byAdding: .month, value: -14, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .day, value: -8, to: .now) ?? .now,
                moderationStatus: .approved,
                likeCount: 11,
                likeState: .liked
            )
        ]
    }

    nonisolated private static func sampleComments() -> [Comment] {
        [
            Comment(
                id: "comment-1",
                authorName: localized("mock.comment.1.author", "Natalia"),
                body: localized("mock.comment.1.body", "This is exactly the kind of practical update our families need."),
                createdAt: calendar.date(byAdding: .hour, value: -18, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .hour, value: -18, to: .now) ?? .now
            ),
            Comment(
                id: "comment-2",
                authorName: localized("mock.comment.2.author", "Petro"),
                body: localized("mock.comment.2.body", "Please keep sharing more events outside Innsbruck as well."),
                createdAt: calendar.date(byAdding: .hour, value: -8, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .hour, value: -8, to: .now) ?? .now
            )
        ]
    }

    nonisolated private static func localized(_ key: String, _ defaultValue: String) -> String {
        // Mock repositories are constructed before LocalizationStore applies the
        // launch language. Resolve UI-test fixtures from the requested bundle so
        // their content never mixes languages during the first render.
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           let language = ProcessInfo.processInfo.environment["UITestAppLanguage"],
           let bundlePath = Bundle.main.path(forResource: language, ofType: "lproj"),
           let bundle = Bundle(path: bundlePath) {
            return bundle.localizedString(forKey: key, value: defaultValue, table: nil)
        }
        return LocalizationStore.localizedString(key, defaultValue: defaultValue)
    }
}
