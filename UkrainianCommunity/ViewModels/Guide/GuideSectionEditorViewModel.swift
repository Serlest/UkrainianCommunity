import Combine
import Foundation

enum GuideSectionEditorMode {
    case createRoot(category: GuideCategory)
    case createChild(parent: GuideNode)
    case edit(node: GuideNode)

    var initialCategory: GuideCategory {
        switch self {
        case .createRoot(let category):
            category
        case .createChild(let parent):
            parent.category
        case .edit(let node):
            node.category
        }
    }

    var initialTitle: String {
        switch self {
        case .edit(let node):
            node.title
        default:
            ""
        }
    }

    var initialSummary: String {
        switch self {
        case .edit(let node):
            node.summary
        default:
            ""
        }
    }

    var initialSortOrder: Int {
        switch self {
        case .edit(let node):
            node.sortOrder
        default:
            0
        }
    }

    var initialRegionScope: RegionScope {
        switch self {
        case .edit(let node):
            node.regionScope ?? .austria
        default:
            .austria
        }
    }

    var initialFederalState: AustrianFederalState? {
        switch self {
        case .edit(let node):
            node.federalState
        default:
            nil
        }
    }

    var initialHealthStatus: GuideHealthStatus {
        switch self {
        case .edit(let node):
            node.healthStatus
        default:
            .current
        }
    }

    var parentID: String {
        switch self {
        case .createRoot:
            FirestoreGuideWriteRepository.rootParentID
        case .createChild(let parent):
            parent.id
        case .edit(let node):
            node.parentID ?? FirestoreGuideWriteRepository.rootParentID
        }
    }

    var parentPathDescription: String {
        switch self {
        case .createRoot(let category):
            return GuideCategoryPresentation.publicTitle(for: category)
        case .createChild(let parent):
            return "\(GuideCategoryPresentation.publicTitle(for: parent.category)) → \(parent.title)"
        case .edit(let node):
            let categoryTitle = GuideCategoryPresentation.publicTitle(for: node.category)
            if let parentID = node.parentID, parentID != FirestoreGuideWriteRepository.rootParentID {
                return "\(categoryTitle) → \(node.title)"
            }
            return categoryTitle
        }
    }

    var title: String {
        switch self {
        case .createRoot:
            return GuideAuthoringPresentation.createSectionScreenTitle
        case .createChild:
            return GuideAuthoringPresentation.createSubsection
        case .edit:
            return GuideAuthoringPresentation.editSectionScreenTitle
        }
    }
}

enum GuideSectionEditorValidationError: Equatable {
    case titleRequired
    case federalStateRequired
    case missingAuthor

    var message: String {
        switch self {
        case .titleRequired:
            GuideAuthoringPresentation.localized(uk: "Назва є обов’язковою.", de: "Der Titel ist erforderlich.", en: "Title is required.")
        case .federalStateRequired:
            GuideAuthoringPresentation.localized(uk: "Оберіть федеральну землю для цього розділу.", de: "Wählen Sie ein Bundesland für diesen Abschnitt.", en: "Select a federal state for this section.")
        case .missingAuthor:
            GuideAuthoringPresentation.localized(uk: "Для збереження розділу потрібен увійдений менеджер.", de: "Zum Speichern des Abschnitts ist ein angemeldeter Manager erforderlich.", en: "A signed-in manager is required to save this section.")
        }
    }
}

enum GuideSectionEditorSaveState: Equatable {
    case idle
    case saving
    case saved
    case failed(String)
}

@MainActor
final class GuideSectionEditorViewModel: ObservableObject {
    @Published var title: String
    @Published var summary: String
    @Published var category: GuideCategory
    @Published var sortOrder: Int
    @Published var regionScope: RegionScope
    @Published var federalState: AustrianFederalState?
    @Published var healthStatus: GuideHealthStatus
    @Published private(set) var validationErrors: [GuideSectionEditorValidationError] = []
    @Published private(set) var saveState: GuideSectionEditorSaveState = .idle

    let mode: GuideSectionEditorMode
    let allowedCategories: [GuideCategory]

    private let repository: GuideWriteRepositoryProtocol
    private let currentUserID: String?

    init(
        mode: GuideSectionEditorMode,
        repository: GuideWriteRepositoryProtocol,
        currentUserID: String?,
        allowedCategories: [GuideCategory]? = nil
    ) {
        self.mode = mode
        self.repository = repository
        self.currentUserID = currentUserID
        self.allowedCategories = allowedCategories ?? GuideCategoryPresentation.publicTopLevelCategories
        self.title = mode.initialTitle
        self.summary = mode.initialSummary
        self.category = mode.initialCategory
        self.sortOrder = mode.initialSortOrder
        self.regionScope = mode.initialRegionScope == .city ? .austria : mode.initialRegionScope
        self.federalState = mode.initialFederalState
        self.healthStatus = mode.initialHealthStatus == .archived ? .current : mode.initialHealthStatus
    }

    var isSaving: Bool {
        saveState == .saving
    }

    var saveButtonTitle: String {
        switch mode {
        case .edit:
            GuideAuthoringPresentation.saveSectionButton
        default:
            GuideAuthoringPresentation.createSectionButton
        }
    }

    var selectableRegionScopes: [RegionScope] {
        [.austria, .federalState]
    }

    var selectableHealthStatuses: [GuideHealthStatus] {
        [.current, .dueSoon, .overdue]
    }

    @discardableResult
    func validate() -> Bool {
        var errors: [GuideSectionEditorValidationError] = []

        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.titleRequired)
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
    func save() async -> GuideNode? {
        guard !isSaving else { return nil }
        saveState = .idle
        guard validate() else { return nil }
        guard let currentUserID else {
            saveState = .failed(GuideSectionEditorValidationError.missingAuthor.message)
            return nil
        }

        saveState = .saving

        let now = Date()
        let node = makeNode(authorID: currentUserID, now: now)

        do {
            let savedNode: GuideNode
            switch mode {
            case .createRoot:
                savedNode = try await repository.createRootNode(node)
            case .createChild:
                savedNode = try await repository.createChildNode(node)
            case .edit:
                try await repository.updateNode(node)
                savedNode = node
            }

            saveState = .saved
            return savedNode
        } catch let error as AppError {
            saveState = .failed(readableMessage(for: error))
            return nil
        } catch {
            saveState = .failed(readableMessage(for: .unknown))
            return nil
        }
    }

    private func makeNode(authorID: String, now: Date) -> GuideNode {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedFederalState = regionScope == .federalState ? federalState : nil
        let parentID = mode.parentID

        switch mode {
        case .edit(let existingNode):
            return GuideNode(
                id: existingNode.id,
                parentID: parentID,
                kind: existingNode.kind,
                category: category,
                title: trimmedTitle,
                summary: trimmedSummary,
                sortOrder: sortOrder,
                regionScope: regionScope,
                federalState: resolvedFederalState,
                healthStatus: healthStatus,
                moderationStatus: existingNode.moderationStatus,
                publishedAt: existingNode.publishedAt,
                createdAt: existingNode.createdAt,
                updatedAt: now,
                createdBy: existingNode.createdBy ?? authorID,
                updatedBy: authorID,
                archivedAt: nil
            )
        case .createRoot, .createChild:
            return GuideNode(
                id: UUID().uuidString,
                parentID: parentID,
                kind: .section,
                category: category,
                title: trimmedTitle,
                summary: trimmedSummary,
                sortOrder: sortOrder,
                regionScope: regionScope,
                federalState: resolvedFederalState,
                healthStatus: healthStatus,
                moderationStatus: .approved,
                publishedAt: now,
                createdAt: now,
                updatedAt: now,
                createdBy: authorID,
                updatedBy: authorID,
                archivedAt: nil
            )
        }
    }

    private func readableMessage(for error: AppError) -> String {
        switch error {
        case .network:
            GuideAuthoringPresentation.localized(uk: "Помилка мережі. Спробуйте ще раз.", de: "Netzwerkfehler. Bitte versuchen Sie es erneut.", en: "Network error. Please try again.")
        case .permissionDenied:
            GuideAuthoringPresentation.localized(uk: "У вас немає прав для збереження цього розділу.", de: "Sie haben keine Berechtigung, diesen Abschnitt zu speichern.", en: "You do not have permission to save this section.")
        case .validationFailed:
            GuideAuthoringPresentation.localized(uk: "Перевірте поля розділу та спробуйте ще раз.", de: "Bitte prüfen Sie die Felder des Abschnitts und versuchen Sie es erneut.", en: "Check the section fields and try again.")
        case .notFound:
            GuideAuthoringPresentation.localized(uk: "Цей розділ більше не існує.", de: "Dieser Abschnitt existiert nicht mehr.", en: "The target section no longer exists.")
        case .unknown:
            GuideAuthoringPresentation.localized(uk: "Зараз не вдалося зберегти розділ.", de: "Der Abschnitt konnte gerade nicht gespeichert werden.", en: "Unable to save the section right now.")
        }
    }
}
