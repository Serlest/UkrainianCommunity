import Foundation

enum MockContentBuilder {
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
            createdAt: calendar.date(byAdding: .month, value: -8, to: .now) ?? .now,
            updatedAt: calendar.date(byAdding: .day, value: -2, to: .now) ?? .now
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
                website: "https://example.org/ukrainian-house-tirol",
                foundedYear: 2026,
                foundedMonth: 5,
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

    nonisolated static func infoItems() -> [InfoItem] {
        [
            InfoItem(
                id: "info-1",
                title: localized("info.card.resettlement.title", "Settling in Tirol"),
                body: localized("info.card.resettlement.body", "Use this section later for official links, local procedures, and practical checklists for new arrivals."),
                systemImage: "map",
                regionScope: .austria
            ),
            InfoItem(
                id: "info-2",
                title: localized("info.card.services.title", "Support Services"),
                body: localized("info.card.services.body", "Reserve this space for healthcare, education, legal support, and emergency contacts."),
                systemImage: "cross.case",
                regionScope: .austria
            ),
            InfoItem(
                id: "info-3",
                title: localized("info.card.community.title", "Community Life"),
                body: localized("info.card.community.body", "Later this can host FAQs, etiquette tips, and recurring local resources for families."),
                systemImage: "person.3",
                regionScope: .austria
            )
        ]
    }

    nonisolated static func guideArticles() -> [GuideArticle] {
        [
            GuideArticle(
                id: "guide-1",
                title: localized("guide.mock.documents.title", "Residence documents after arrival"),
                summary: localized("guide.mock.documents.summary", "A short checklist for keeping identity, residence, and insurance documents in order in Tirol."),
                body: localized("guide.mock.documents.body", "Keep passports, residence papers, insurance confirmation, and registration extracts together in one folder. Make phone photos of each document, store copies securely, and bring originals to appointments only when required."),
                category: .documents,
                regionScope: .federalState,
                federalState: .tirol,
                officialSourceURL: "https://www.oesterreich.gv.at/",
                sourceName: "oesterreich.gv.at",
                isPinned: true,
                createdAt: calendar.date(byAdding: .month, value: -2, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .day, value: -2, to: .now) ?? .now
            ),
            GuideArticle(
                id: "guide-2",
                title: localized("guide.mock.anmeldung.title", "Anmeldung in Tirol: what to bring"),
                summary: localized("guide.mock.anmeldung.summary", "What families usually need before visiting the local registration office."),
                body: localized("guide.mock.anmeldung.body", "Bring identification, proof of address from the landlord or host, and any local forms requested by your municipality. Requirements can differ slightly by city, so check the municipal website before your visit."),
                category: .anmeldung,
                regionScope: .federalState,
                federalState: .tirol,
                officialSourceURL: "https://www.innsbruck.gv.at/",
                sourceName: "Stadt Innsbruck",
                isPinned: true,
                createdAt: calendar.date(byAdding: .month, value: -1, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .day, value: -6, to: .now) ?? .now
            ),
            GuideArticle(
                id: "guide-3",
                title: localized("guide.mock.work.title", "Starting work in Austria"),
                summary: localized("guide.mock.work.summary", "A practical starting point for contracts, tax number expectations, and where to ask questions."),
                body: localized("guide.mock.work.body", "Before accepting a job, read the contract carefully, clarify weekly hours, and ask who handles social insurance registration. Keep payslips and any written communication from the employer."),
                category: .work,
                regionScope: .austria,
                officialSourceURL: "https://www.arbeiterkammer.at/",
                sourceName: "Arbeiterkammer",
                createdAt: calendar.date(byAdding: .day, value: -16, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .day, value: -10, to: .now) ?? .now
            ),
            GuideArticle(
                id: "guide-4",
                title: localized("guide.mock.ams.title", "AMS appointments and job support"),
                summary: localized("guide.mock.ams.summary", "How to prepare for an AMS visit and what information is usually useful."),
                body: localized("guide.mock.ams.body", "Bring identification, your residence information, any previous CV, and notes about the kind of work you are seeking. If you need language support, ask in advance whether interpretation or translated materials are available."),
                category: .ams,
                regionScope: .austria,
                officialSourceURL: "https://www.ams.at/",
                sourceName: "AMS",
                createdAt: calendar.date(byAdding: .day, value: -14, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .day, value: -9, to: .now) ?? .now
            ),
            GuideArticle(
                id: "guide-5",
                title: localized("guide.mock.housing.title", "Housing search basics in Tirol"),
                summary: localized("guide.mock.housing.summary", "Key checks before agreeing to rent, deposit, or utilities."),
                body: localized("guide.mock.housing.body", "Ask whether utilities are included, what deposit is expected, and how long the rental term lasts. Never hand over money without a written agreement or clear receipt."),
                category: .housing,
                regionScope: .federalState,
                federalState: .tirol,
                createdAt: calendar.date(byAdding: .day, value: -12, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .day, value: -8, to: .now) ?? .now
            ),
            GuideArticle(
                id: "guide-6",
                title: localized("guide.mock.medicine.title", "Healthcare first steps"),
                summary: localized("guide.mock.medicine.summary", "How to prepare for a doctor visit and what documents are useful to keep nearby."),
                body: localized("guide.mock.medicine.body", "Keep medication lists, allergies, and previous diagnoses written down in one place. If possible, bring insurance confirmation and any referrals to each appointment."),
                category: .medicine,
                regionScope: .austria,
                officialSourceURL: "https://www.gesundheit.gv.at/",
                sourceName: "gesundheit.gv.at",
                createdAt: calendar.date(byAdding: .day, value: -11, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .day, value: -5, to: .now) ?? .now
            ),
            GuideArticle(
                id: "guide-7",
                title: localized("guide.mock.education.title", "School enrollment support"),
                summary: localized("guide.mock.education.summary", "A calm overview of what schools may ask for when enrolling children."),
                body: localized("guide.mock.education.body", "Schools may ask for identification, address registration, previous school information, and vaccination records where available. If documents are missing, contact the school administration early and explain the situation."),
                category: .education,
                regionScope: .federalState,
                federalState: .tirol,
                createdAt: calendar.date(byAdding: .day, value: -9, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .day, value: -4, to: .now) ?? .now
            ),
            GuideArticle(
                id: "guide-8",
                title: localized("guide.mock.contacts.title", "Trusted help lines and contact habits"),
                summary: localized("guide.mock.contacts.summary", "Keep official phone numbers and response channels organized for everyday issues."),
                body: localized("guide.mock.contacts.body", "Save official contacts in your phone with clear labels and keep a paper backup of the most important numbers. For urgent matters, use official service lines rather than social media messages."),
                category: .contacts,
                regionScope: .austria,
                isPinned: true,
                createdAt: calendar.date(byAdding: .day, value: -8, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .day, value: -1, to: .now) ?? .now
            ),
            GuideArticle(
                id: "guide-9",
                title: localized("guide.mock.emergency.title", "Emergency numbers to know"),
                summary: localized("guide.mock.emergency.summary", "The fastest numbers to reach emergency support in Austria."),
                body: localized("guide.mock.emergency.body", "In urgent danger or medical emergency, call the appropriate Austrian emergency number immediately. If you are helping someone else, share the exact location first and keep the phone line free for callbacks."),
                category: .emergency,
                regionScope: .austria,
                isPinned: true,
                createdAt: calendar.date(byAdding: .day, value: -7, to: .now) ?? .now,
                updatedAt: calendar.date(byAdding: .hour, value: -12, to: .now) ?? .now
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
