import Foundation

enum MockContentBuilder {
    nonisolated private static let calendar = Calendar.current

    nonisolated static func currentUser() -> AppUser {
        AppUser(
            id: "user-1",
            fullName: localized("mock.user.name", "Olena Koval"),
            city: localized("mock.city.innsbruck", "Innsbruck"),
            email: "olena@example.com",
            bio: localized("mock.user.bio", "Helping newly arrived families find events, support, and trusted local services in Tirol."),
            role: .moderator,
            blockState: .active,
            createdAt: calendar.date(byAdding: .month, value: -8, to: .now) ?? .now,
            updatedAt: calendar.date(byAdding: .day, value: -2, to: .now) ?? .now
        )
    }

    nonisolated static func newsPosts() -> [NewsPost] {
        [
            NewsPost(
                id: "news-1",
                title: localized("mock.news.1.title", "Community center opens weekly legal support hours"),
                subtitle: localized("mock.news.1.subtitle", "Free consultations for residence, work, and family questions."),
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
        [
            Event(
                id: "event-1",
                title: localized("mock.event.1.title", "Ukrainian Community Evening"),
                summary: localized("mock.event.1.summary", "Meet neighbors, volunteers, and local organizations in one place."),
                details: localized("mock.event.1.details", "An evening for networking, announcements, and practical orientation for families living in Tirol. Tea, children’s corner, and language support will be available."),
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
                city: localized("mock.city.innsbruck", "Innsbruck"),
                imageURL: nil,
                contactEmail: "hello@example.org",
                website: "https://example.org/ukrainian-house-tirol",
                createdAt: calendar.date(byAdding: .month, value: -10, to: .now) ?? .now,
                moderationStatus: .approved,
                likeCount: 19,
                likeState: .notLiked
            ),
            Organization(
                id: "org-2",
                name: localized("mock.org.2.name", "Tirol Volunteer Network"),
                description: localized("mock.org.2.description", "Volunteer coordination for transport, translation, and everyday help. Connecting volunteers and families quickly for practical, low-friction support across Tirol."),
                city: localized("mock.city.hall", "Hall in Tirol"),
                imageURL: nil,
                contactEmail: "support@example.org",
                website: "https://example.org/volunteer-network",
                createdAt: calendar.date(byAdding: .month, value: -14, to: .now) ?? .now,
                moderationStatus: .approved,
                likeCount: 11,
                likeState: .liked
            )
        ]
    }

    nonisolated static func marketplaceItems() -> [MarketplaceItem] {
        [
            MarketplaceItem(
                id: "market-1",
                title: localized("mock.market.1.title", "Winter jacket for teenager"),
                description: localized("mock.market.1.description", "Warm jacket in very good condition, suitable for ages 13 to 15."),
                price: nil,
                currency: "EUR",
                city: localized("mock.city.innsbruck", "Innsbruck"),
                category: localized("mock.market.category.clothing", "Clothing"),
                imageURL: nil,
                contactEmail: "mariia@example.com",
                expiresAt: calendar.date(byAdding: .day, value: 12, to: .now),
                createdAt: calendar.date(byAdding: .day, value: -1, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .hour, value: -6, to: .now) ?? .now,
                moderationStatus: .approved,
                likeCount: 9,
                likeState: .notLiked
            ),
            MarketplaceItem(
                id: "market-2",
                title: localized("mock.market.2.title", "Child seat"),
                description: localized("mock.market.2.description", "Used child seat with ISOFIX, collected in Worgl."),
                price: 45,
                currency: "EUR",
                city: localized("mock.city.worgl", "Worgl"),
                category: localized("mock.market.category.children", "Children"),
                imageURL: nil,
                contactEmail: "andrii@example.com",
                expiresAt: calendar.date(byAdding: .day, value: 7, to: .now),
                createdAt: calendar.date(byAdding: .day, value: -4, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .day, value: -1, to: .now) ?? .now,
                moderationStatus: .pendingReview,
                likeCount: 6,
                likeState: .liked
            )
        ]
    }

    nonisolated static func infoItems() -> [InfoItem] {
        [
            InfoItem(
                id: "info-1",
                title: localized("info.card.resettlement.title", "Settling in Tirol"),
                body: localized("info.card.resettlement.body", "Use this section later for official links, local procedures, and practical checklists for new arrivals."),
                systemImage: "map"
            ),
            InfoItem(
                id: "info-2",
                title: localized("info.card.services.title", "Support Services"),
                body: localized("info.card.services.body", "Reserve this space for healthcare, education, legal support, and emergency contacts."),
                systemImage: "cross.case"
            ),
            InfoItem(
                id: "info-3",
                title: localized("info.card.community.title", "Community Life"),
                body: localized("info.card.community.body", "Later this can host FAQs, etiquette tips, and recurring local resources for families."),
                systemImage: "person.3"
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
        LocalizationStore.localizedString(key, defaultValue: defaultValue)
    }
}
