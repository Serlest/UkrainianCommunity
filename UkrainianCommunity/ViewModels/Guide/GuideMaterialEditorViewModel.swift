import Combine
import Foundation

enum GuideMaterialEditorMode {
    case create(node: GuideNode, nodePath: GuideTreePath)
    case edit(material: GuideMaterial)

    var title: String {
        switch self {
        case .create:
            return "Add Material"
        case .edit:
            return "Edit Material"
        }
    }

    var initialTitle: String {
        switch self {
        case .create:
            return ""
        case .edit(let material):
            return material.title
        }
    }

    var initialSummary: String {
        switch self {
        case .create:
            return ""
        case .edit(let material):
            return material.summary
        }
    }

    var initialBody: String {
        switch self {
        case .create:
            return ""
        case .edit(let material):
            return material.body
        }
    }

    var initialSortOrder: Int {
        switch self {
        case .create:
            return 0
        case .edit(let material):
            return material.sortOrder
        }
    }

    var initialContentBlocks: [GuideContentBlock] {
        switch self {
        case .create:
            return []
        case .edit(let material):
            return material.contentBlocks
        }
    }

    var initialSourceLinks: [GuideSourceLink] {
        switch self {
        case .create:
            return []
        case .edit(let material):
            return material.sourceLinks
        }
    }

    var initialOfficialSourceURL: String {
        switch self {
        case .create:
            return ""
        case .edit(let material):
            return material.officialSourceURL ?? ""
        }
    }

    var initialSourceName: String {
        switch self {
        case .create:
            return ""
        case .edit(let material):
            return material.sourceName ?? ""
        }
    }

    var initialOfficialSourcesRequired: Bool {
        switch self {
        case .create:
            return false
        case .edit(let material):
            return material.officialSourcesRequired
        }
    }

    var initialReviewInterval: ReviewInterval {
        switch self {
        case .create:
            return .normal
        case .edit(let material):
            return material.reviewInterval
        }
    }

    var initialLastReviewedAt: Date {
        switch self {
        case .create:
            return Date()
        case .edit(let material):
            return material.lastReviewedAt ?? Date()
        }
    }

    var initialNextReviewAt: Date {
        switch self {
        case .create:
            let now = Date()
            return Calendar.current.date(byAdding: .month, value: ReviewInterval.normal.months, to: now) ?? now
        case .edit(let material):
            if let nextReviewAt = material.nextReviewAt {
                return nextReviewAt
            }

            let lastReviewedAt = material.lastReviewedAt ?? Date()
            return Calendar.current.date(byAdding: .month, value: material.reviewInterval.months, to: lastReviewedAt) ?? lastReviewedAt
        }
    }

    var category: GuideCategory {
        switch self {
        case .create(let node, _):
            return node.category
        case .edit(let material):
            return material.category
        }
    }

    var nodeID: String {
        switch self {
        case .create(let node, _):
            return node.id
        case .edit(let material):
            return material.nodeID
        }
    }

    var nodePath: GuideTreePath {
        switch self {
        case .create(_, let nodePath):
            return nodePath
        case .edit(let material):
            return material.nodePath
        }
    }

    var initialRegionScope: RegionScope {
        switch self {
        case .create(let node, _):
            return node.regionScope ?? .austria
        case .edit(let material):
            return material.regionScope ?? .austria
        }
    }

    var initialFederalState: AustrianFederalState? {
        switch self {
        case .create(let node, _):
            return node.federalState
        case .edit(let material):
            return material.federalState
        }
    }
}

enum GuideMaterialEditorValidationError: Equatable {
    case titleRequired
    case summaryRequired
    case bodyOrBlocksRequired
    case nodeIDRequired
    case federalStateRequired
    case missingAuthor

    var message: String {
        switch self {
        case .titleRequired:
            return GuideAuthoringPresentation.localized(uk: "Назва є обов’язковою.", de: "Der Titel ist erforderlich.", en: "Title is required.")
        case .summaryRequired:
            return GuideAuthoringPresentation.localized(uk: "Короткий опис є обов’язковим.", de: "Die Kurzbeschreibung ist erforderlich.", en: "Summary is required.")
        case .bodyOrBlocksRequired:
            return GuideAuthoringPresentation.localized(uk: "Додайте основний текст або хоча б один змістовний блок.", de: "Fügen Sie einen Haupttext oder mindestens einen darstellbaren Block hinzu.", en: "Add body text or at least one renderable block.")
        case .nodeIDRequired:
            return GuideAuthoringPresentation.localized(uk: "Для цього матеріалу потрібен розділ.", de: "Für diesen Artikel ist ein Zielabschnitt erforderlich.", en: "A target section is required for this material.")
        case .federalStateRequired:
            return GuideAuthoringPresentation.localized(uk: "Оберіть федеральну землю для цього матеріалу.", de: "Wählen Sie ein Bundesland für diesen Artikel.", en: "Select a federal state for this article.")
        case .missingAuthor:
            return GuideAuthoringPresentation.localized(uk: "Для збереження матеріалу потрібен увійдений менеджер.", de: "Zum Speichern des Artikels ist ein angemeldeter Manager erforderlich.", en: "A signed-in manager is required to save this material.")
        }
    }
}

enum GuideMaterialEditorSaveState: Equatable {
    case idle
    case saving
    case saved
    case failed(String)
}

@MainActor
final class GuideMaterialEditorViewModel: ObservableObject {
    @Published var title: String
    @Published var summary: String
    @Published var body: String
    @Published var sortOrder: Int
    @Published private(set) var contentBlocks: [GuideContentBlock]
    @Published var steps: [String]
    @Published var checklistItems: [String]
    @Published var contacts: [GuideContactReference]
    @Published var importantInformation: String
    @Published var sourceLinks: [GuideSourceLink]
    @Published var officialSourceURL: String
    @Published var sourceName: String
    @Published var officialSourcesRequired: Bool
    @Published var reviewInterval: ReviewInterval
    @Published var lastReviewedAt: Date
    @Published var nextReviewAt: Date
    @Published var regionScope: RegionScope
    @Published var federalState: AustrianFederalState?
    @Published private(set) var validationErrors: [GuideMaterialEditorValidationError] = []
    @Published private(set) var saveState: GuideMaterialEditorSaveState = .idle

    let mode: GuideMaterialEditorMode

    private let repository: GuideWriteRepositoryProtocol
    private let currentUserID: String?

    init(
        mode: GuideMaterialEditorMode,
        repository: GuideWriteRepositoryProtocol,
        currentUserID: String?
    ) {
        self.mode = mode
        self.repository = repository
        self.currentUserID = currentUserID
        self.title = mode.initialTitle
        self.summary = mode.initialSummary
        self.body = mode.initialBody
        self.sortOrder = mode.initialSortOrder
        self.sourceLinks = mode.initialSourceLinks
        self.officialSourceURL = mode.initialOfficialSourceURL
        self.sourceName = mode.initialSourceName
        self.officialSourcesRequired = mode.initialOfficialSourcesRequired
        self.reviewInterval = mode.initialReviewInterval
        self.lastReviewedAt = mode.initialLastReviewedAt
        self.nextReviewAt = mode.initialNextReviewAt
        self.regionScope = mode.initialRegionScope == .city ? .austria : mode.initialRegionScope
        self.federalState = mode.initialFederalState

        let sectionContent = Self.makeSectionContent(
            body: mode.initialBody,
            contentBlocks: mode.initialContentBlocks,
            sourceLinks: mode.initialSourceLinks
        )
        self.body = sectionContent.description
        self.steps = sectionContent.steps
        self.checklistItems = sectionContent.checklistItems
        self.contacts = sectionContent.contacts
        self.importantInformation = sectionContent.importantInformation
        self.sourceLinks = sectionContent.sourceLinks
        self.contentBlocks = mode.initialContentBlocks
    }

    var isSaving: Bool {
        saveState == .saving
    }

    var saveButtonTitle: String {
        switch mode {
        case .create:
            return GuideAuthoringPresentation.createMaterialButton
        case .edit:
            return GuideAuthoringPresentation.saveMaterialButton
        }
    }

    var category: GuideCategory {
        mode.category
    }

    var nodePathDescription: String {
        mode.nodePath.titles.joined(separator: " → ")
    }

    var selectableRegionScopes: [RegionScope] {
        [.austria, .federalState]
    }

    @discardableResult
    func validate() -> Bool {
        var errors: [GuideMaterialEditorValidationError] = []

        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.titleRequired)
        }

        if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.summaryRequired)
        }

        let generatedBlocks = buildContentBlocks()
        let hasBody = !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasRenderableBlocks = generatedBlocks.contains(where: \.isRenderable)
        if !hasBody && !hasRenderableBlocks {
            errors.append(.bodyOrBlocksRequired)
        }

        if mode.nodeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.nodeIDRequired)
        }

        if regionScope == .federalState, federalState == nil {
            errors.append(.federalStateRequired)
        }

        if currentUserID == nil {
            errors.append(.missingAuthor)
        }

        validationErrors = errors
        return errors.isEmpty
    }

    func clearTransientState() {
        if saveState != .saving {
            saveState = .idle
        }
    }

    @discardableResult
    func save() async -> GuideMaterial? {
        guard !isSaving else { return nil }
        saveState = .idle
        guard validate() else { return nil }
        guard let currentUserID else {
            saveState = .failed(GuideMaterialEditorValidationError.missingAuthor.message)
            return nil
        }

        saveState = .saving

        let now = Date()
        let material = makeMaterial(authorID: currentUserID, now: now)

        do {
            let savedMaterial: GuideMaterial
            switch mode {
            case .create:
                savedMaterial = try await repository.createMaterial(material)
            case .edit:
                try await repository.updateMaterial(material)
                savedMaterial = material
            }

            saveState = .saved
            return savedMaterial
        } catch let error as AppError {
            saveState = .failed(readableMessage(for: error))
            return nil
        } catch {
            saveState = .failed(readableMessage(for: .unknown))
            return nil
        }
    }

    private func makeMaterial(authorID: String, now: Date) -> GuideMaterial {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOfficialSourceURL = officialSourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSourceName = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedFederalState = regionScope == .federalState ? federalState : nil
        let generatedBlocks = buildContentBlocks()
        contentBlocks = generatedBlocks

        switch mode {
        case .create:
            return GuideMaterial(
                id: UUID().uuidString,
                title: trimmedTitle,
                summary: trimmedSummary,
                body: trimmedBody,
                sortOrder: sortOrder,
                contentBlocks: generatedBlocks,
                sourceLinks: sourceLinks,
                officialSourceURL: trimmedOfficialSourceURL.isEmpty ? nil : trimmedOfficialSourceURL,
                sourceName: trimmedSourceName.isEmpty ? nil : trimmedSourceName,
                officialSourcesRequired: officialSourcesRequired,
                kind: .page,
                category: mode.category,
                nodeID: mode.nodeID,
                nodePath: mode.nodePath,
                regionScope: regionScope,
                federalState: resolvedFederalState,
                reviewInterval: reviewInterval,
                lastReviewedAt: lastReviewedAt,
                nextReviewAt: nextReviewAt,
                reviewedBy: authorID,
                moderationStatus: .approved,
                publishedAt: now,
                createdAt: now,
                updatedAt: now,
                createdBy: authorID,
                updatedBy: authorID,
                archivedAt: nil
            )
        case .edit(let existingMaterial):
            return GuideMaterial(
                id: existingMaterial.id,
                title: trimmedTitle,
                summary: trimmedSummary,
                body: trimmedBody,
                sortOrder: sortOrder,
                contentBlocks: generatedBlocks,
                sourceLinks: sourceLinks,
                officialSourceURL: trimmedOfficialSourceURL.isEmpty ? nil : trimmedOfficialSourceURL,
                sourceName: trimmedSourceName.isEmpty ? nil : trimmedSourceName,
                officialSourcesRequired: officialSourcesRequired,
                kind: .page,
                category: existingMaterial.category,
                nodeID: existingMaterial.nodeID,
                nodePath: existingMaterial.nodePath,
                regionScope: regionScope,
                federalState: resolvedFederalState,
                reviewInterval: reviewInterval,
                lastReviewedAt: lastReviewedAt,
                nextReviewAt: nextReviewAt,
                reviewedBy: authorID,
                moderationStatus: existingMaterial.moderationStatus,
                publishedAt: existingMaterial.publishedAt,
                createdAt: existingMaterial.createdAt,
                updatedAt: now,
                createdBy: existingMaterial.createdBy ?? authorID,
                updatedBy: authorID,
                archivedAt: nil
            )
        }
    }

    private func readableMessage(for error: AppError) -> String {
        switch error {
        case .network:
            return GuideAuthoringPresentation.localized(uk: "Помилка мережі. Спробуйте ще раз.", de: "Netzwerkfehler. Bitte versuchen Sie es erneut.", en: "Network error. Please try again.")
        case .permissionDenied:
            return GuideAuthoringPresentation.localized(uk: "У вас немає прав для збереження цього матеріалу.", de: "Sie haben keine Berechtigung, diesen Artikel zu speichern.", en: "You do not have permission to save this material.")
        case .validationFailed:
            return GuideAuthoringPresentation.localized(uk: "Перевірте поля матеріалу та спробуйте ще раз.", de: "Bitte prüfen Sie die Felder des Artikels und versuchen Sie es erneut.", en: "Check the material fields and try again.")
        case .notFound:
            return GuideAuthoringPresentation.localized(uk: "Розділ або матеріал більше не існує.", de: "Der Abschnitt oder Artikel existiert nicht mehr.", en: "The target section or material no longer exists.")
        case .unknown:
            return GuideAuthoringPresentation.localized(uk: "Зараз не вдалося зберегти матеріал.", de: "Der Artikel konnte gerade nicht gespeichert werden.", en: "Unable to save the material right now.")
        }
    }

    private func buildContentBlocks() -> [GuideContentBlock] {
        var blocks: [GuideContentBlock] = []

        let normalizedSteps = steps.normalizedGuideLines
        if !normalizedSteps.isEmpty {
            blocks.append(
                .steps(
                    .init(
                        id: "guide-steps",
                        title: GuideAuthoringPresentation.stepsSectionTitle,
                        steps: normalizedSteps
                    )
                )
            )
        }

        let normalizedChecklist = checklistItems.normalizedGuideLines
        if !normalizedChecklist.isEmpty {
            blocks.append(
                .checklist(
                    .init(
                        id: "guide-checklist",
                        title: GuideAuthoringPresentation.checklistSectionTitle,
                        items: normalizedChecklist
                    )
                )
            )
        }

        let normalizedContacts = contacts.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !normalizedContacts.isEmpty {
            blocks.append(
                .contacts(
                    .init(
                        id: "guide-contacts",
                        title: GuideAuthoringPresentation.contactsSectionTitle,
                        contacts: normalizedContacts
                    )
                )
            )
        }

        let normalizedInformation = importantInformation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedInformation.isEmpty {
            blocks.append(
                .infoBox(
                    .init(
                        id: "guide-important-information",
                        title: GuideAuthoringPresentation.importantInformationSectionTitle,
                        message: normalizedInformation
                    )
                )
            )
        }

        return blocks
    }

    private static func makeSectionContent(
        body: String,
        contentBlocks: [GuideContentBlock],
        sourceLinks: [GuideSourceLink]
    ) -> MaterialSectionContent {
        var mergedBodyParts = [body.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
        var steps: [String] = []
        var checklistItems: [String] = []
        var contacts: [GuideContactReference] = []
        var importantInformationParts: [String] = []
        var collectedLinks = sourceLinks

        for block in contentBlocks {
            switch block {
            case .text(let block):
                let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    mergedBodyParts.append(text)
                }
            case .steps(let block):
                steps.append(contentsOf: block.steps.normalizedGuideLines)
            case .checklist(let block):
                checklistItems.append(contentsOf: block.items.normalizedGuideLines)
            case .contacts(let block):
                contacts.append(contentsOf: block.contacts)
            case .warning(let block), .infoBox(let block):
                let message = block.message.trimmingCharacters(in: .whitespacesAndNewlines)
                if !message.isEmpty {
                    if let title = block.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                        importantInformationParts.append("\(title)\n\(message)")
                    } else {
                        importantInformationParts.append(message)
                    }
                }
            case .links(let block):
                collectedLinks.append(contentsOf: block.links.filter(\.isRenderable))
            }
        }

        return MaterialSectionContent(
            description: mergedBodyParts.joined(separator: "\n\n"),
            steps: steps.normalizedGuideLines,
            checklistItems: checklistItems.normalizedGuideLines,
            contacts: contacts.uniqueByID(),
            importantInformation: importantInformationParts.joined(separator: "\n\n"),
            sourceLinks: collectedLinks.uniqueByID()
        )
    }
}

private struct MaterialSectionContent {
    let description: String
    let steps: [String]
    let checklistItems: [String]
    let contacts: [GuideContactReference]
    let importantInformation: String
    let sourceLinks: [GuideSourceLink]
}

private extension Array where Element == String {
    var normalizedGuideLines: [String] {
        map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private extension Array where Element == GuideSourceLink {
    func uniqueByID() -> [GuideSourceLink] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}

private extension Array where Element == GuideContactReference {
    func uniqueByID() -> [GuideContactReference] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}
