import Foundation

enum GuideMockContentFactory {
    nonisolated private static let calendar = Calendar.current

    nonisolated static func guideArticles() -> [GuideArticle] {
        [
            guideArticle(
                id: "guide-first-steps-arrival",
                title: "First 72 hours after arrival",
                summary: "A calm checklist for registration, safety, connectivity, and first appointments.",
                body: "Start with identity documents, temporary address, phone access, and a short list of urgent appointments. Keep every confirmation in one folder and avoid relying on social media posts for official requirements.",
                category: .firstSteps,
                federalState: .tirol,
                city: "Innsbruck",
                isPinned: true,
                contentType: .checklist,
                contentBlocks: [
                    infoBox("first-priority", "Priority", "If you are safe and have a place to sleep, focus next on registration, health access, school or childcare needs, and a reachable phone number."),
                    checklist("first-checklist", "First checklist", [
                        "Save passport and residence document copies securely.",
                        "Write down your temporary address and host contact.",
                        "Check the municipality website before visiting the registration office.",
                        "Save emergency numbers and a trusted local contact."
                    ]),
                    links("first-links", "Useful starting points", [
                        source("oesterreich", "oesterreich.gv.at", "https://www.oesterreich.gv.at/", "Federal Austrian portal"),
                        source("tirol-help", "Land Tirol", "https://www.tirol.gv.at/", "State of Tirol")
                    ])
                ],
                audience: ["new arrivals", "families", "volunteers"],
                sourceLinks: [
                    source("first-source-oesterreich", "Official Austrian information", "https://www.oesterreich.gv.at/", "oesterreich.gv.at")
                ],
                reviewInterval: .critical,
                publishedDaysAgo: 42,
                lastReviewedDaysAgo: 4,
                nextReviewDaysFromNow: 86,
                isFeatured: true,
                priority: 1
            ),
            guideArticle(
                id: "guide-documents-folder",
                title: "Documents folder for appointments",
                summary: "What to keep ready for offices, schools, doctors, banks, and support organizations.",
                body: "A complete document folder saves time and reduces stress. Keep originals separate from printed copies and use clear file names for digital scans.",
                category: .documents,
                federalState: .tirol,
                isPinned: true,
                contentType: .guide,
                contentBlocks: [
                    text("documents-text", "Core idea", "Prepare one physical folder and one secure digital folder. Include identity, registration, insurance, school, medical, and income-related documents where available."),
                    checklist("documents-checklist", "Bring when relevant", [
                        "Passport or identity card",
                        "Registration confirmation or address proof",
                        "Insurance confirmation or e-card information",
                        "Birth certificates and school records for children",
                        "Rental agreement or host confirmation"
                    ]),
                    warning("documents-warning", "Protect originals", "Do not hand over original documents unless the office explicitly requires them. Ask for a receipt when an original must stay with an authority.")
                ],
                audience: ["new arrivals", "parents", "students"],
                sourceLinks: [
                    source("documents-oesterreich", "Official document guidance", "https://www.oesterreich.gv.at/", "oesterreich.gv.at")
                ],
                reviewInterval: .normal,
                publishedDaysAgo: 64,
                lastReviewedDaysAgo: 12,
                nextReviewDaysFromNow: 150,
                isFeatured: true,
                priority: 2
            ),
            guideArticle(
                id: "guide-anmeldung-meldezettel",
                title: "Anmeldung and Meldezettel",
                summary: "How address registration usually works and what to clarify before visiting the office.",
                body: "Municipal registration requirements can differ in details. Check the local office page, bring identification, and make sure the accommodation provider signs the required form where needed.",
                category: .anmeldung,
                federalState: .tirol,
                city: "Innsbruck",
                contentType: .process,
                contentBlocks: [
                    steps("anmeldung-steps", "Typical flow", [
                        "Download or request the local registration form.",
                        "Ask the accommodation provider to confirm the address.",
                        "Bring ID and required documents to the municipal office.",
                        "Keep the registration confirmation for later appointments."
                    ]),
                    links("anmeldung-links", "Municipal references", [
                        source("innsbruck", "Stadt Innsbruck", "https://www.innsbruck.gv.at/", "Stadt Innsbruck"),
                        source("oesterreich-melde", "Residence registration overview", "https://www.oesterreich.gv.at/", "oesterreich.gv.at")
                    ])
                ],
                audience: ["new arrivals", "hosts"],
                sourceLinks: [
                    source("anmeldung-source", "Stadt Innsbruck", "https://www.innsbruck.gv.at/", "Stadt Innsbruck")
                ],
                reviewInterval: .critical,
                publishedDaysAgo: 70,
                lastReviewedDaysAgo: 80,
                nextReviewDaysFromNow: -3,
                isFeatured: true,
                priority: 3
            ),
            guideArticle(
                id: "guide-work-contract",
                title: "Before signing a work contract",
                summary: "Check hours, pay, social insurance, trial period, and written duties before accepting.",
                body: "A written contract should make the basic terms clear. If something is unclear, ask before signing and keep all messages related to the job offer.",
                category: .work,
                contentType: .guide,
                contentBlocks: [
                    text("work-text", "Contract basics", "Confirm weekly hours, gross pay, start date, workplace, probation terms, notice period, and who registers you for social insurance."),
                    warning("work-warning", "Do not work without clarity", "Be careful with informal cash work or pressure to start without written terms. Ask Arbeiterkammer or a counseling service before agreeing."),
                    links("work-links", "Advice sources", [
                        source("ak", "Arbeiterkammer", "https://www.arbeiterkammer.at/", "Arbeiterkammer"),
                        source("ams-work", "AMS", "https://www.ams.at/", "AMS")
                    ])
                ],
                audience: ["job seekers", "students", "parents"],
                sourceLinks: [
                    source("work-ak-source", "Arbeiterkammer", "https://www.arbeiterkammer.at/", "Arbeiterkammer")
                ],
                reviewInterval: .normal,
                publishedDaysAgo: 38,
                lastReviewedDaysAgo: 16,
                nextReviewDaysFromNow: 164,
                priority: 6
            ),
            guideArticle(
                id: "guide-finance-bank-tax",
                title: "Bank account, taxes, and FinanzOnline",
                summary: "A quick orientation for salary payments, tax records, and official finance portals.",
                body: "A bank account is often needed for rent, salary, and benefits. Keep tax and salary documents organized from the beginning and use official finance portals for sensitive information.",
                category: .finance,
                contentType: .quickInfo,
                contentBlocks: [
                    infoBox("finance-infobox", "Practical rule", "Use official portals for tax matters and be careful with links sent through chats or unofficial groups."),
                    checklist("finance-checklist", "Keep together", [
                        "Bank account documents",
                        "Salary slips",
                        "Tax identification or FinanzOnline access information",
                        "Benefit or allowance decisions"
                    ]),
                    links("finance-links", "Finance references", [
                        source("bmf", "Federal Ministry of Finance", "https://www.bmf.gv.at/", "BMF"),
                        source("finanzonline", "FinanzOnline", "https://finanzonline.bmf.gv.at/", "BMF")
                    ])
                ],
                audience: ["working adults", "families"],
                sourceLinks: [
                    source("finance-source", "Federal Ministry of Finance", "https://www.bmf.gv.at/", "BMF")
                ],
                reviewInterval: .normal,
                publishedDaysAgo: 31,
                lastReviewedDaysAgo: 145,
                nextReviewDaysFromNow: 18,
                priority: 9
            ),
            guideArticle(
                id: "guide-family-child-benefits",
                title: "Family support and child benefits",
                summary: "Documents and offices families often need when asking about child-related support.",
                body: "Family support questions usually require identity, residence, school, and household information. Requirements depend on your exact status, so check official sources before applying.",
                category: .family,
                contentType: .guide,
                contentBlocks: [
                    checklist("family-checklist", "Prepare before asking", [
                        "Child identity documents",
                        "Proof of address",
                        "School or childcare confirmation",
                        "Residence and income documents where available"
                    ]),
                    warning("family-warning", "Eligibility varies", "Do not assume eligibility based on another family's case. Ask an official office or qualified counseling service."),
                    links("family-links", "Official information", [
                        source("family-oesterreich", "Family benefits overview", "https://www.oesterreich.gv.at/", "oesterreich.gv.at")
                    ])
                ],
                audience: ["parents", "guardians"],
                sourceLinks: [
                    source("family-source", "Austrian federal portal", "https://www.oesterreich.gv.at/", "oesterreich.gv.at")
                ],
                reviewInterval: .critical,
                publishedDaysAgo: 92,
                lastReviewedDaysAgo: 92,
                nextReviewDaysFromNow: -2,
                priority: 8
            ),
            guideArticle(
                id: "guide-health-ogk-doctor",
                title: "Health insurance and doctor visits",
                summary: "How to prepare for appointments and keep medical information usable in Austria.",
                body: "Write down current medication, allergies, diagnoses, and questions before appointments. Bring insurance information and referrals if you have them.",
                category: .health,
                contentType: .process,
                contentBlocks: [
                    steps("health-steps", "Before the appointment", [
                        "Check whether the doctor accepts your insurance.",
                        "Bring e-card or insurance confirmation.",
                        "Prepare medication names and previous documents.",
                        "Ask for written instructions after the visit."
                    ]),
                    contacts("health-contacts", "Helpful contact types", [
                        contact("health-ogk", "ÖGK", "Health insurance questions", nil, nil, "https://www.gesundheitskasse.at/"),
                        contact("health-1450", "1450", "Health advice line for non-emergency medical questions", "1450", nil, nil)
                    ]),
                    links("health-links", "Health references", [
                        source("gesundheit", "gesundheit.gv.at", "https://www.gesundheit.gv.at/", "gesundheit.gv.at"),
                        source("ogk", "ÖGK", "https://www.gesundheitskasse.at/", "ÖGK")
                    ])
                ],
                audience: ["families", "older adults", "people with medication"],
                sourceLinks: [
                    source("health-source", "gesundheit.gv.at", "https://www.gesundheit.gv.at/", "gesundheit.gv.at")
                ],
                reviewInterval: .critical,
                publishedDaysAgo: 44,
                lastReviewedDaysAgo: 20,
                nextReviewDaysFromNow: 25,
                priority: 4
            ),
            guideArticle(
                id: "guide-housing-rent-deposit",
                title: "Rent, deposit, and utilities",
                summary: "Key checks before agreeing to a flat, room, deposit, or shared housing arrangement.",
                body: "Before paying anything, clarify rent, operating costs, deposit amount, utility setup, contract duration, and handover condition.",
                category: .housing,
                federalState: .tirol,
                contentType: .checklist,
                contentBlocks: [
                    checklist("housing-checklist", "Before paying", [
                        "Ask for a written rental agreement.",
                        "Confirm what is included in monthly costs.",
                        "Document the flat condition with photos.",
                        "Get a receipt for deposit or first payment."
                    ]),
                    warning("housing-warning", "Avoid pressure payments", "Do not transfer a deposit before seeing the place, confirming the owner or agent, and receiving clear written terms.")
                ],
                audience: ["new arrivals", "students", "families"],
                sourceLinks: [
                    source("housing-tirol", "Land Tirol housing information", "https://www.tirol.gv.at/", "Land Tirol")
                ],
                reviewInterval: .stable,
                publishedDaysAgo: 55,
                lastReviewedDaysAgo: 30,
                nextReviewDaysFromNow: 300,
                priority: 7
            ),
            guideArticle(
                id: "guide-transport-tirol",
                title: "Public transport in Tirol",
                summary: "Tickets, routes, and habits that make everyday travel easier.",
                body: "Check route planners before appointments and leave buffer time for transfers. Keep a ticket or pass valid before boarding.",
                category: .transport,
                federalState: .tirol,
                contentType: .quickInfo,
                contentBlocks: [
                    infoBox("transport-info", "Everyday tip", "Save your most common routes and check the return trip before leaving, especially in smaller towns."),
                    links("transport-links", "Transport references", [
                        source("vvt", "Verkehrsverbund Tirol", "https://www.vvt.at/", "VVT"),
                        source("oebb", "ÖBB", "https://www.oebb.at/", "ÖBB")
                    ])
                ],
                audience: ["students", "commuters", "families"],
                sourceLinks: [
                    source("transport-source", "Verkehrsverbund Tirol", "https://www.vvt.at/", "VVT")
                ],
                reviewInterval: .normal,
                publishedDaysAgo: 26,
                lastReviewedDaysAgo: 10,
                nextReviewDaysFromNow: 170,
                priority: 12
            ),
            guideArticle(
                id: "guide-education-school",
                title: "School enrollment and language support",
                summary: "A practical guide for contacting schools and preparing children's documents.",
                body: "Contact the local school or education authority early. Explain missing documents clearly and ask what can be submitted later.",
                category: .education,
                federalState: .tirol,
                contentType: .process,
                contentBlocks: [
                    steps("education-steps", "Typical preparation", [
                        "Collect identity and previous school documents.",
                        "Prepare address confirmation if available.",
                        "Contact the school administration.",
                        "Ask about German language support and bridging options."
                    ]),
                    infoBox("education-info", "Missing papers", "Schools often can discuss next steps even if some Ukrainian documents are unavailable.")
                ],
                audience: ["parents", "children", "teenagers"],
                sourceLinks: [
                    source("education-tirol", "Education in Tirol", "https://www.tirol.gv.at/", "Land Tirol")
                ],
                reviewInterval: .normal,
                publishedDaysAgo: 21,
                lastReviewedDaysAgo: 14,
                nextReviewDaysFromNow: 166,
                priority: 5
            ),
            guideArticle(
                id: "guide-law-free-advice",
                title: "When to ask for legal advice",
                summary: "Situations where a qualified advisor is safer than community chat answers.",
                body: "Legal status, contracts, family matters, and deadlines should be checked with qualified advisors. Use community groups for orientation, not final legal decisions.",
                category: .law,
                contentType: .guide,
                status: .needsReview,
                contentBlocks: [
                    warning("law-warning", "Deadlines matter", "If a letter mentions a deadline, ask for help immediately and keep the envelope and all pages."),
                    checklist("law-checklist", "Bring to advice appointments", [
                        "The complete letter or contract",
                        "Identity and residence documents",
                        "Timeline of what happened",
                        "Any previous replies or emails"
                    ]),
                    links("law-links", "Starting references", [
                        source("oesterreich-law", "Federal legal information", "https://www.oesterreich.gv.at/", "oesterreich.gv.at")
                    ])
                ],
                audience: ["new arrivals", "workers", "families"],
                sourceLinks: [
                    source("law-source", "oesterreich.gv.at", "https://www.oesterreich.gv.at/", "oesterreich.gv.at")
                ],
                reviewInterval: .critical,
                publishedDaysAgo: 120,
                lastReviewedDaysAgo: 120,
                nextReviewDaysFromNow: -30,
                priority: 10
            ),
            guideArticle(
                id: "guide-emergency-numbers",
                title: "Emergency numbers in Austria",
                summary: "Numbers and basic call habits for urgent medical, fire, police, and crisis situations.",
                body: "In an emergency, call first and explain location clearly. Stay on the line until the operator says you can hang up.",
                category: .emergency,
                isPinned: true,
                contentType: .contact,
                contentBlocks: [
                    contacts("emergency-contacts", "Emergency contacts", [
                        contact("emergency-eu", "112", "European emergency number", "112", nil, nil),
                        contact("emergency-fire", "122", "Fire brigade", "122", nil, nil),
                        contact("emergency-police", "133", "Police", "133", nil, nil),
                        contact("emergency-ambulance", "144", "Ambulance", "144", nil, nil),
                        contact("emergency-health", "1450", "Health advice line", "1450", nil, nil)
                    ]),
                    text("emergency-text", "What to say first", "Start with where you are, what happened, how many people need help, and whether there is immediate danger.")
                ],
                audience: ["everyone"],
                sourceLinks: [
                    source("emergency-source", "Austrian emergency information", "https://www.oesterreich.gv.at/", "oesterreich.gv.at")
                ],
                reviewInterval: .stable,
                publishedDaysAgo: 18,
                lastReviewedDaysAgo: 1,
                nextReviewDaysFromNow: 364,
                isFeatured: true,
                priority: 0
            ),
            guideArticle(
                id: "guide-community-trusted-help",
                title: "Finding trusted Ukrainian community help",
                summary: "How to choose reliable local support without exposing private documents unnecessarily.",
                body: "Community groups are useful, but personal documents and case details should be shared carefully. Prefer known organizations, clear contact channels, and official referrals.",
                category: .ukrainianCommunity,
                federalState: .tirol,
                city: "Innsbruck",
                contentType: .guide,
                contentBlocks: [
                    checklist("community-checklist", "Trust signals", [
                        "The group has a clear organizer or legal entity.",
                        "Appointments and services are described transparently.",
                        "No one asks for original documents in a chat.",
                        "Sensitive questions are handled privately."
                    ]),
                    contacts("community-contacts", "Example local contact types", [
                        contact("community-house", "Ukrainian House Tirol", "Community orientation and events", nil, "hello@example.org", "https://example.org/ukrainian-house-tirol"),
                        contact("community-volunteers", "Tirol Volunteer Network", "Transport and everyday support coordination", nil, "support@example.org", "https://example.org/volunteer-network")
                    ])
                ],
                audience: ["new arrivals", "volunteers", "organizers"],
                reviewInterval: .normal,
                publishedDaysAgo: 15,
                lastReviewedDaysAgo: 8,
                nextReviewDaysFromNow: 172,
                priority: 11
            ),
            guideArticle(
                id: "guide-life-in-austria-etiquette",
                title: "Everyday life in Austria: appointments, letters, quiet hours",
                summary: "Small habits that prevent missed deadlines and neighbor conflicts.",
                body: "Many Austrian services rely on appointments and written letters. Open official mail quickly, keep appointment confirmations, and ask early if you cannot attend.",
                category: .lifeInAustria,
                contentType: .quickInfo,
                contentBlocks: [
                    text("life-text", "Letters are important", "Letters from authorities, landlords, insurance, schools, and courts can contain deadlines. Photograph and translate them early if needed."),
                    infoBox("life-info", "Quiet hours", "House rules can include quiet hours and waste sorting rules. Ask your landlord or neighbors if you are unsure."),
                    checklist("life-checklist", "Useful habits", [
                        "Keep a calendar for appointments and deadlines.",
                        "Save letters by date and sender.",
                        "Cancel appointments you cannot attend.",
                        "Check building rules for waste, laundry, and quiet times."
                    ])
                ],
                audience: ["families", "students", "new arrivals"],
                reviewInterval: .stable,
                publishedDaysAgo: 10,
                lastReviewedDaysAgo: 5,
                nextReviewDaysFromNow: 360,
                priority: 13
            ),
            guideArticle(
                id: "guide-ams-appointment",
                title: "Preparing for an AMS appointment",
                summary: "What to bring and how to make job support meetings more useful.",
                body: "AMS appointments are easier when you bring a CV, previous work history, certificates, and a realistic list of work options.",
                category: .ams,
                contentType: .process,
                contentBlocks: [
                    steps("ams-steps", "Before the visit", [
                        "Update your CV with Austrian contact details.",
                        "Collect certificates or translations if available.",
                        "Write down work experience and preferred working hours.",
                        "Ask in advance if language support is available."
                    ]),
                    links("ams-links", "AMS references", [
                        source("ams-main", "AMS", "https://www.ams.at/", "Arbeitsmarktservice")
                    ])
                ],
                audience: ["job seekers"],
                sourceLinks: [
                    source("ams-source", "Arbeitsmarktservice", "https://www.ams.at/", "AMS")
                ],
                reviewInterval: .normal,
                publishedDaysAgo: 28,
                lastReviewedDaysAgo: 11,
                nextReviewDaysFromNow: 169,
                priority: 14
            )
        ]
        .sorted { lhs, rhs in
            let lhsPriority = lhs.priority ?? Int.max
            let rhsPriority = rhs.priority ?? Int.max

            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }

            return lhs.updatedAt > rhs.updatedAt
        }
    }

    nonisolated private static func guideArticle(
        id: String,
        title: String,
        summary: String,
        body: String,
        category: GuideCategory,
        regionScope: RegionScope = .austria,
        federalState: AustrianFederalState? = nil,
        city: String? = nil,
        officialSourceURL: String? = nil,
        sourceName: String? = nil,
        isPinned: Bool = false,
        contentType: GuideContentType,
        status: GuideStatus = .published,
        contentBlocks: [GuideContentBlock],
        audience: [String],
        sourceLinks: [GuideSourceLink] = [],
        reviewInterval: ReviewInterval,
        publishedDaysAgo: Int,
        lastReviewedDaysAgo: Int,
        nextReviewDaysFromNow: Int,
        isFeatured: Bool = false,
        priority: Int
    ) -> GuideArticle {
        let publishedAt = daysFromNow(-publishedDaysAgo)
        let lastReviewedAt = daysFromNow(-lastReviewedDaysAgo)
        let nextReviewAt = daysFromNow(nextReviewDaysFromNow)
        let primarySourceLink = sourceLinks.first

        return GuideArticle(
            id: id,
            title: localized("guide.mock.\(id).title", title),
            summary: localized("guide.mock.\(id).summary", summary),
            body: localized("guide.mock.\(id).body", body),
            category: category,
            regionScope: regionScope,
            federalState: federalState,
            city: city,
            officialSourceURL: officialSourceURL ?? primarySourceLink?.url,
            sourceName: sourceName ?? primarySourceLink?.sourceName ?? primarySourceLink?.title,
            isPinned: isPinned,
            moderationStatus: .approved,
            createdAt: daysFromNow(-(publishedDaysAgo + 4)),
            updatedAt: lastReviewedAt,
            contentType: contentType,
            status: status,
            contentBlocks: contentBlocks,
            audience: audience,
            sourceLinks: sourceLinks,
            officialSourcesRequired: !sourceLinks.isEmpty,
            priority: priority,
            isFeatured: isFeatured,
            createdBy: "mock-guide-editor",
            updatedBy: "mock-guide-editor",
            reviewedBy: "mock-guide-reviewer",
            publishedAt: publishedAt,
            lastReviewedAt: lastReviewedAt,
            nextReviewAt: nextReviewAt,
            reviewInterval: reviewInterval,
            archivedAt: nil
        )
    }

    nonisolated private static func daysFromNow(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: .now) ?? .now
    }

    nonisolated private static func text(_ id: String, _ title: String?, _ value: String) -> GuideContentBlock {
        .text(.init(id: id, title: title, text: value))
    }

    nonisolated private static func steps(_ id: String, _ title: String?, _ values: [String]) -> GuideContentBlock {
        .steps(.init(id: id, title: title, steps: values))
    }

    nonisolated private static func checklist(_ id: String, _ title: String?, _ values: [String]) -> GuideContentBlock {
        .checklist(.init(id: id, title: title, items: values))
    }

    nonisolated private static func warning(_ id: String, _ title: String?, _ value: String) -> GuideContentBlock {
        .warning(.init(id: id, title: title, message: value))
    }

    nonisolated private static func infoBox(_ id: String, _ title: String?, _ value: String) -> GuideContentBlock {
        .infoBox(.init(id: id, title: title, message: value))
    }

    nonisolated private static func links(_ id: String, _ title: String?, _ values: [GuideSourceLink]) -> GuideContentBlock {
        .links(.init(id: id, title: title, links: values))
    }

    nonisolated private static func contacts(_ id: String, _ title: String?, _ values: [GuideContactReference]) -> GuideContentBlock {
        .contacts(.init(id: id, title: title, contacts: values))
    }

    nonisolated private static func source(_ id: String, _ title: String, _ url: String, _ sourceName: String, isOfficial: Bool = true) -> GuideSourceLink {
        GuideSourceLink(id: id, title: title, url: url, sourceName: sourceName, isOfficial: isOfficial)
    }

    nonisolated private static func contact(
        _ id: String,
        _ name: String,
        _ description: String?,
        _ phone: String?,
        _ email: String?,
        _ website: String?
    ) -> GuideContactReference {
        GuideContactReference(id: id, name: name, description: description, phone: phone, email: email, website: website)
    }

    nonisolated private static func localized(_ key: String, _ defaultValue: String) -> String {
        LocalizationStore.localizedString(key, defaultValue: defaultValue)
    }
}
