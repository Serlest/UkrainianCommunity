import Foundation

struct MockGuideRepository: GuideRepositoryProtocol {
    static let rootParentID = "root"

    private let nodes: [GuideNode]
    private let materials: [GuideMaterial]

    init(
        nodes: [GuideNode] = MockGuideSeed.nodes,
        materials: [GuideMaterial] = MockGuideSeed.materials
    ) {
        self.nodes = nodes
        self.materials = materials
    }

    func fetchRootNodes(
        category: GuideCategory,
        selectedFederalState: AustrianFederalState?
    ) async throws -> [GuideNode] {
        nodes
            .filter {
                $0.category == category &&
                $0.parentID == Self.rootParentID &&
                $0.isPublished &&
                matchesSelectedRegion(
                    regionScope: $0.regionScope,
                    federalState: $0.federalState,
                    selectedFederalState: selectedFederalState
                )
            }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    func fetchChildNodes(
        parentId: String,
        selectedFederalState: AustrianFederalState?
    ) async throws -> [GuideNode] {
        nodes
            .filter {
                $0.parentID == parentId &&
                $0.isPublished &&
                matchesSelectedRegion(
                    regionScope: $0.regionScope,
                    federalState: $0.federalState,
                    selectedFederalState: selectedFederalState
                )
            }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    func fetchMaterials(
        nodeId: String,
        selectedFederalState: AustrianFederalState?
    ) async throws -> [GuideMaterial] {
        materials
            .filter {
                $0.nodeID == nodeId &&
                $0.isPublished &&
                matchesSelectedRegion(
                    regionScope: $0.regionScope,
                    federalState: $0.federalState,
                    selectedFederalState: selectedFederalState
                )
            }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }

                if lhs.title != rhs.title {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }

                return lhs.updatedAt > rhs.updatedAt
            }
    }

    func fetchAllNodesForSearch(
        selectedFederalState: AustrianFederalState?
    ) async throws -> [GuideNode] {
        nodes
            .filter {
                $0.isPublished &&
                matchesSelectedRegion(
                    regionScope: $0.regionScope,
                    federalState: $0.federalState,
                    selectedFederalState: selectedFederalState
                )
            }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    func fetchAllMaterialsForSearch(
        selectedFederalState: AustrianFederalState?
    ) async throws -> [GuideMaterial] {
        materials
            .filter {
                $0.isPublished &&
                matchesSelectedRegion(
                    regionScope: $0.regionScope,
                    federalState: $0.federalState,
                    selectedFederalState: selectedFederalState
                )
            }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }

                if lhs.title != rhs.title {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }

                return lhs.updatedAt > rhs.updatedAt
            }
    }

    func fetchMaterialsNeedingReview() async throws -> [GuideMaterial] {
        materials
            .filter {
                let status = $0.healthStatus
                return status == .dueSoon || status == .overdue
            }
            .sorted { lhs, rhs in
                switch (lhs.nextReviewAt, rhs.nextReviewAt) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate != rhsDate {
                        return lhsDate < rhsDate
                    }
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    break
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    func fetchSavedMaterialIDs() async throws -> [String] {
        await MockGuideBookmarkStore.shared.savedMaterialIDs()
    }

    func bookmarkMaterial(id: String) async throws {
        await MockGuideBookmarkStore.shared.save(materialID: id)
    }

    func unbookmarkMaterial(id: String) async throws {
        await MockGuideBookmarkStore.shared.remove(materialID: id)
    }

    func fetchMaterial(id: String) async throws -> GuideMaterial {
        guard let material = materials.first(where: { $0.id == id && $0.isPublished }) else {
            throw AppError.notFound
        }

        return material
    }

    private func matchesSelectedRegion(
        regionScope: RegionScope?,
        federalState: AustrianFederalState?,
        selectedFederalState: AustrianFederalState?
    ) -> Bool {
        guard let selectedFederalState else {
            return true
        }

        switch regionScope ?? .austria {
        case .austria:
            return true
        case .federalState, .city:
            return federalState == selectedFederalState
        }
    }
}

private actor MockGuideBookmarkStore {
    static let shared = MockGuideBookmarkStore()

    private var savedIDs: [String] = []

    func savedMaterialIDs() -> [String] {
        savedIDs
    }

    func save(materialID: String) {
        savedIDs.removeAll { $0 == materialID }
        savedIDs.insert(materialID, at: 0)
    }

    func remove(materialID: String) {
        savedIDs.removeAll { $0 == materialID }
    }
}

private enum MockGuideSeed {
    static let authorID = "guide-seed"
    static let reviewOwnerID = "guide-reviewer"
    static let now = Date(timeIntervalSince1970: 1_717_000_000)

    static let nodes: [GuideNode] = [
        GuideNode(
            id: "guide-node-healthcare",
            parentID: MockGuideRepository.rootParentID,
            kind: .section,
            category: .health,
            title: GuideCategory.health.title,
            summary: "Базові матеріали про медичну систему, страхування та перші кроки у сфері здоров'я.",
            sortOrder: 0,
            regionScope: .austria,
            healthStatus: .current,
            moderationStatus: .approved,
            publishedAt: now.addingTimeInterval(-86_400 * 14),
            createdAt: now.addingTimeInterval(-86_400 * 40),
            updatedAt: now.addingTimeInterval(-86_400 * 7),
            createdBy: authorID,
            updatedBy: authorID
        ),
        GuideNode(
            id: "guide-node-healthcare-insurance",
            parentID: "guide-node-healthcare",
            kind: .folder,
            category: .health,
            title: "Медичне страхування",
            summary: "Основна інформація про покриття, контакти страхової каси та перші дії після реєстрації.",
            sortOrder: 10,
            regionScope: .austria,
            healthStatus: .current,
            moderationStatus: .approved,
            publishedAt: now.addingTimeInterval(-86_400 * 10),
            createdAt: now.addingTimeInterval(-86_400 * 30),
            updatedAt: now.addingTimeInterval(-86_400 * 5),
            createdBy: authorID,
            updatedBy: authorID
        ),
        GuideNode(
            id: "guide-node-transport",
            parentID: MockGuideRepository.rootParentID,
            kind: .section,
            category: .transport,
            title: GuideCategory.transport.title,
            summary: "Регіональні транспортні системи, тарифи та базові правила користування.",
            sortOrder: 0,
            regionScope: .austria,
            healthStatus: .current,
            moderationStatus: .approved,
            publishedAt: now.addingTimeInterval(-86_400 * 14),
            createdAt: now.addingTimeInterval(-86_400 * 42),
            updatedAt: now.addingTimeInterval(-86_400 * 6),
            createdBy: authorID,
            updatedBy: authorID
        ),
        GuideNode(
            id: "guide-node-transport-tirol",
            parentID: "guide-node-transport",
            kind: .folder,
            category: .transport,
            title: "Tirol",
            summary: "Регіональні транспортні сервіси та маршрути для Тіролю.",
            sortOrder: 10,
            regionScope: .federalState,
            federalState: .tirol,
            healthStatus: .dueSoon,
            moderationStatus: .approved,
            publishedAt: now.addingTimeInterval(-86_400 * 12),
            createdAt: now.addingTimeInterval(-86_400 * 45),
            updatedAt: now.addingTimeInterval(-86_400 * 4),
            createdBy: authorID,
            updatedBy: authorID
        ),
        GuideNode(
            id: "guide-node-transport-wien",
            parentID: "guide-node-transport",
            kind: .folder,
            category: .transport,
            title: "Wien",
            summary: "Міський транспорт Відня, квитки, маршрути та офіційні джерела.",
            sortOrder: 20,
            regionScope: .federalState,
            federalState: .wien,
            healthStatus: .current,
            moderationStatus: .approved,
            publishedAt: now.addingTimeInterval(-86_400 * 8),
            createdAt: now.addingTimeInterval(-86_400 * 40),
            updatedAt: now.addingTimeInterval(-86_400 * 3),
            createdBy: authorID,
            updatedBy: authorID
        )
    ]

    static let materials: [GuideMaterial] = [
        GuideMaterial(
            id: "guide-material-health-insurance-basics",
            title: "Як працює медичне страхування",
            summary: "Коротке пояснення, як підтверджується доступ до медичних послуг і що перевірити на старті.",
            body: "Доступ до медичних послуг в Австрії зазвичай починається з активного страхового покриття та коректних даних у страховій системі.",
            sortOrder: 10,
            contentBlocks: [
                .text(.init(
                    id: "guide-material-health-insurance-basics-text",
                    title: "Основне",
                    text: "Перед зверненням до лікаря або медичного закладу варто перевірити, що страхування активне, а персональні дані вказані без помилок."
                )),
                .checklist(.init(
                    id: "guide-material-health-insurance-basics-checklist",
                    title: "Що перевірити",
                    items: [
                        "Чи активне ваше страхування",
                        "Чи правильно вказані персональні дані",
                        "Чи знаєте ви, до якого страхового фонду належите"
                    ]
                ))
            ],
            sourceLinks: [
                GuideSourceLink(
                    id: "guide-material-health-insurance-basics-link",
                    title: "Austrian social insurance overview",
                    url: "https://www.sozialversicherung.at/",
                    sourceName: "Sozialversicherung",
                    isOfficial: true
                )
            ],
            officialSourceURL: "https://www.sozialversicherung.at/",
            sourceName: "Sozialversicherung",
            officialSourcesRequired: true,
            kind: .page,
            category: .health,
            nodeID: "guide-node-healthcare-insurance",
            nodePath: GuideTreePath(components: [
                .init(id: GuideCategory.health.rawValue, title: GuideCategory.health.title),
                .init(id: "guide-node-healthcare-insurance", title: "Медичне страхування")
            ]),
            regionScope: .austria,
            reviewInterval: .normal,
            lastReviewedAt: now.addingTimeInterval(-86_400 * 20),
            nextReviewAt: now.addingTimeInterval(86_400 * 120),
            reviewedBy: reviewOwnerID,
            moderationStatus: .approved,
            publishedAt: now.addingTimeInterval(-86_400 * 10),
            createdAt: now.addingTimeInterval(-86_400 * 30),
            updatedAt: now.addingTimeInterval(-86_400 * 5),
            createdBy: authorID,
            updatedBy: authorID
        ),
        GuideMaterial(
            id: "guide-material-health-insurance-setup",
            title: "З чого почати оформлення покриття",
            summary: "Які кроки пройти, щоб підтвердити страхування та зрозуміти свій наступний крок.",
            body: "Оформлення покриття зазвичай починається з підтвердження типу страхування, перевірки реєстраційних даних і контакту зі страховою установою.",
            sortOrder: 20,
            contentBlocks: [
                .steps(.init(
                    id: "guide-material-health-insurance-setup-steps",
                    title: "Базові кроки",
                    steps: [
                        "Перевірте, хто є вашим страховим провайдером",
                        "Підготуйте посвідчення особи та підтвердження реєстрації",
                        "Уточніть спосіб подання документів онлайн або офлайн"
                    ]
                )),
                .links(.init(
                    id: "guide-material-health-insurance-setup-links",
                    title: "Корисні посилання",
                    links: [
                        GuideSourceLink(
                            id: "guide-material-health-insurance-setup-link",
                            title: "Health insurance contact points",
                            url: "https://www.gesundheitskasse.at/",
                            sourceName: "ÖGK",
                            isOfficial: true
                        )
                    ]
                ))
            ],
            sourceLinks: [
                GuideSourceLink(
                    id: "guide-material-health-insurance-setup-source",
                    title: "Österreichische Gesundheitskasse",
                    url: "https://www.gesundheitskasse.at/",
                    sourceName: "ÖGK",
                    isOfficial: true
                )
            ],
            officialSourceURL: "https://www.gesundheitskasse.at/",
            sourceName: "ÖGK",
            officialSourcesRequired: true,
            kind: .page,
            category: .health,
            nodeID: "guide-node-healthcare-insurance",
            nodePath: GuideTreePath(components: [
                .init(id: GuideCategory.health.rawValue, title: GuideCategory.health.title),
                .init(id: "guide-node-healthcare-insurance", title: "Медичне страхування")
            ]),
            regionScope: .austria,
            reviewInterval: .normal,
            lastReviewedAt: now.addingTimeInterval(-86_400 * 25),
            nextReviewAt: now.addingTimeInterval(86_400 * 90),
            reviewedBy: reviewOwnerID,
            moderationStatus: .approved,
            publishedAt: now.addingTimeInterval(-86_400 * 10),
            createdAt: now.addingTimeInterval(-86_400 * 28),
            updatedAt: now.addingTimeInterval(-86_400 * 4),
            createdBy: authorID,
            updatedBy: authorID
        ),
        GuideMaterial(
            id: "guide-material-transport-tirol-overview",
            title: "Транспорт у Тіролі",
            summary: "Де перевіряти маршрути, як уточнювати тарифи та на які офіційні джерела спиратися.",
            body: "Для громадського транспорту Тіролю важливо перевіряти актуальні маршрути й тарифи лише через офіційні регіональні сервіси перевізників.",
            sortOrder: 10,
            contentBlocks: [
                .infoBox(.init(
                    id: "guide-material-transport-tirol-overview-info",
                    title: "Регіональне покриття",
                    message: "Матеріал актуальний насамперед для Тіролю й не повинен показуватися як універсальна порада для всієї Австрії."
                ))
            ],
            sourceLinks: [
                GuideSourceLink(
                    id: "guide-material-transport-tirol-overview-source",
                    title: "Regional transport information",
                    url: "https://www.vvt.at/",
                    sourceName: "Regional transport",
                    isOfficial: true
                )
            ],
            officialSourceURL: "https://www.vvt.at/",
            sourceName: "Regional transport",
            officialSourcesRequired: true,
            kind: .page,
            category: .transport,
            nodeID: "guide-node-transport-tirol",
            nodePath: GuideTreePath(components: [
                .init(id: GuideCategory.transport.rawValue, title: GuideCategory.transport.title),
                .init(id: "guide-node-transport", title: GuideCategory.transport.title),
                .init(id: "guide-node-transport-tirol", title: "Tirol")
            ]),
            regionScope: .federalState,
            federalState: .tirol,
            reviewInterval: .critical,
            lastReviewedAt: now.addingTimeInterval(-86_400 * 70),
            nextReviewAt: now.addingTimeInterval(86_400 * 10),
            reviewedBy: reviewOwnerID,
            moderationStatus: .approved,
            publishedAt: now.addingTimeInterval(-86_400 * 12),
            createdAt: now.addingTimeInterval(-86_400 * 45),
            updatedAt: now.addingTimeInterval(-86_400 * 4),
            createdBy: authorID,
            updatedBy: authorID
        ),
        GuideMaterial(
            id: "guide-material-transport-wiener-linien",
            title: "Wiener Linien у Відні",
            summary: "Швидка база по маршрутах, квитках і офіційному джерелу для віденського транспорту.",
            body: "Wiener Linien є основним міським оператором транспорту у Відні. Для тарифів і планування маршруту слід використовувати офіційний сайт або застосунок.",
            sortOrder: 10,
            contentBlocks: [
                .warning(.init(
                    id: "guide-material-transport-wiener-linien-warning",
                    title: "Актуальність тарифів",
                    message: "Ціни на квитки можуть змінюватися, тому фінальну вартість потрібно перевіряти лише в офіційному джерелі."
                ))
            ],
            sourceLinks: [
                GuideSourceLink(
                    id: "guide-material-transport-wiener-linien-source",
                    title: "Wiener Linien official website",
                    url: "https://www.wienerlinien.at/",
                    sourceName: "Wiener Linien",
                    isOfficial: true
                )
            ],
            officialSourceURL: "https://www.wienerlinien.at/",
            sourceName: "Wiener Linien",
            officialSourcesRequired: true,
            kind: .page,
            category: .transport,
            nodeID: "guide-node-transport-wien",
            nodePath: GuideTreePath(components: [
                .init(id: GuideCategory.transport.rawValue, title: GuideCategory.transport.title),
                .init(id: "guide-node-transport", title: GuideCategory.transport.title),
                .init(id: "guide-node-transport-wien", title: "Wien")
            ]),
            regionScope: .federalState,
            federalState: .wien,
            reviewInterval: .normal,
            lastReviewedAt: now.addingTimeInterval(-86_400 * 18),
            nextReviewAt: now.addingTimeInterval(86_400 * 95),
            reviewedBy: reviewOwnerID,
            moderationStatus: .approved,
            publishedAt: now.addingTimeInterval(-86_400 * 8),
            createdAt: now.addingTimeInterval(-86_400 * 40),
            updatedAt: now.addingTimeInterval(-86_400 * 3),
            createdBy: authorID,
            updatedBy: authorID
        )
    ]
}
