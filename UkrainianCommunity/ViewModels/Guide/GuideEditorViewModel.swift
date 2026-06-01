import Combine
import Foundation

enum GuideEditorValidationError: Equatable {
    case titleRequired
    case summaryRequired
    case categoryRequired
    case contentRequired
    case officialSourceRequired

    var message: String {
        switch self {
        case .titleRequired:
            AppStrings.Validation.guideTitleRequired
        case .summaryRequired:
            AppStrings.Validation.guideSummaryRequired
        case .categoryRequired:
            AppStrings.Validation.guideCategoryRequired
        case .contentRequired:
            AppStrings.Validation.guideContentRequired
        case .officialSourceRequired:
            AppStrings.Validation.guideOfficialSourceRequired
        }
    }
}

enum GuideEditorMode {
    case create
    case edit(GuideArticle)

    var initialDraft: GuideArticleDraft {
        switch self {
        case .create:
            GuideArticleDraft()
        case .edit(let article):
            GuideArticleDraft(article: article)
        }
    }

    var articleID: String? {
        switch self {
        case .create:
            nil
        case .edit(let article):
            article.id
        }
    }
}

enum GuideEditorSaveState: Equatable {
    case idle
    case saving
    case saved
    case failed(String)
}

@MainActor
final class GuideEditorViewModel: ObservableObject {
    @Published var draft: GuideArticleDraft
    @Published private(set) var validationErrors: [GuideEditorValidationError] = []
    @Published private(set) var saveState: GuideEditorSaveState = .idle
    @Published private(set) var savedArticle: GuideArticle?

    private let repository: GuideRepository
    private let currentUserId: String?
    private var mode: GuideEditorMode
    private var lastSavedDraft: GuideArticleDraft

    init(
        repository: GuideRepository,
        currentUserId: String?,
        mode: GuideEditorMode = .create
    ) {
        self.repository = repository
        self.currentUserId = currentUserId
        self.mode = mode
        self.draft = mode.initialDraft
        self.lastSavedDraft = mode.initialDraft
    }

    convenience init(
        article: GuideArticle,
        repository: GuideRepository,
        currentUserId: String?
    ) {
        self.init(
            repository: repository,
            currentUserId: currentUserId,
            mode: .edit(article)
        )
    }

    var canSaveDraft: Bool {
        Self.validationErrors(for: draft).isEmpty
    }

    var validationMessages: [String] {
        validationErrors.map(\.message)
    }

    var isSaving: Bool {
        saveState == .saving
    }

    var canSubmitForReview: Bool {
        guard let article = currentArticle else { return false }
        return article.moderationStatus == .draft
            && (article.status == nil || article.status == .draft)
            && article.archivedAt == nil
    }

    var saveActionTitle: String {
        switch currentArticle?.status {
        case .published:
            AppStrings.GuideEditor.saveChangesAction
        default:
            AppStrings.GuideEditor.saveDraftAction
        }
    }

    var saveStatusMessage: String? {
        switch saveState {
        case .idle:
            nil
        case .saving:
            AppStrings.GuideEditor.savingDraft
        case .saved:
            AppStrings.GuideEditor.draftSaved
        case .failed(let message):
            message
        }
    }

    @discardableResult
    func validate() -> Bool {
        validationErrors = Self.validationErrors(for: draft)
        return validationErrors.isEmpty
    }

    func clearValidation() {
        validationErrors = []
    }

    func clearSaveState() {
        if saveState != .saving {
            saveState = .idle
        }
    }

    @discardableResult
    func saveDraft() async -> GuideArticle? {
        guard !isSaving else { return nil }
        saveState = .idle
        guard validate() else { return nil }
        guard let currentUserId else {
            saveState = .failed(AppStrings.GuideEditor.missingAuthorError)
            return nil
        }

        saveState = .saving

        do {
            let article: GuideArticle
            switch mode {
            case .create:
                article = try await repository.createGuideArticle(from: draft, authorId: currentUserId)
                mode = .edit(article)
            case .edit(let existingArticle):
                article = try await repository.updateGuideArticle(
                    id: existingArticle.id,
                    from: draft,
                    editorId: currentUserId
                )
                mode = .edit(article)
            }

            savedArticle = article
            lastSavedDraft = draft
            saveState = .saved
            AppContentChangeBus.postGuideChanged()
            return article
        } catch {
            saveState = .failed(Self.saveErrorMessage(for: error))
            return nil
        }
    }

    @discardableResult
    func submitForReview() async -> Bool {
        guard !isSaving else { return false }
        saveState = .idle
        guard validate() else { return false }
        guard let currentUserId else {
            saveState = .failed(AppStrings.GuideEditor.missingAuthorError)
            return false
        }
        guard let articleID = mode.articleID, canSubmitForReview else {
            saveState = .failed(AppStrings.GuideEditor.submitUnavailable)
            return false
        }
        guard draft == lastSavedDraft else {
            saveState = .failed(AppStrings.GuideEditor.submitUnsavedChanges)
            return false
        }

        saveState = .saving

        do {
            try await repository.submitGuideArticleForReview(id: articleID, submitterId: currentUserId)
            AppContentChangeBus.postGuideChanged()
            saveState = .saved
            return true
        } catch {
            saveState = .failed(Self.saveErrorMessage(for: error))
            return false
        }
    }

    func archive() async {
        guard validate() else { return }
        guard let currentUserId else {
            saveState = .failed(AppStrings.GuideEditor.missingAuthorError)
            return
        }
        guard let articleID = mode.articleID else {
            saveState = .failed(AppStrings.GuideEditor.archiveUnavailable)
            return
        }

        saveState = .saving

        do {
            try await repository.archiveGuideArticle(id: articleID, editorId: currentUserId)
            saveState = .saved
        } catch {
            saveState = .failed(Self.saveErrorMessage(for: error))
        }
    }

    func updateDraft(_ update: (inout GuideArticleDraft) -> Void) {
        update(&draft)
        if !validationErrors.isEmpty {
            validationErrors = Self.validationErrors(for: draft)
        }
        if saveState != .saving {
            saveState = .idle
        }
    }

    private var currentArticle: GuideArticle? {
        switch mode {
        case .create:
            nil
        case .edit(let article):
            article
        }
    }

    private static func validationErrors(for draft: GuideArticleDraft) -> [GuideEditorValidationError] {
        var errors = [GuideEditorValidationError]()

        if draft.title.trimmedForGuideEditor.isEmpty {
            errors.append(.titleRequired)
        }

        if draft.summary.trimmedForGuideEditor.isEmpty {
            errors.append(.summaryRequired)
        }

        if draft.category == nil {
            errors.append(.categoryRequired)
        }

        if !draft.hasGuideEditorContent {
            errors.append(.contentRequired)
        }

        if draft.officialSourcesRequired && !draft.hasOfficialGuideEditorSource {
            errors.append(.officialSourceRequired)
        }

        return errors
    }

    private static func saveErrorMessage(for error: Error) -> String {
        guard let appError = error as? AppError else {
            return AppStrings.GuideEditor.saveFailed
        }

        switch appError {
        case .network:
            return AppStrings.GuideEditor.saveNetworkError
        case .permissionDenied:
            return AppStrings.GuideEditor.savePermissionError
        case .validationFailed:
            return AppStrings.GuideEditor.saveNotImplemented
        case .notFound:
            return AppStrings.GuideEditor.saveNotFoundError
        case .unknown:
            return AppStrings.GuideEditor.saveFailed
        }
    }
}

private extension GuideArticleDraft {
    var hasGuideEditorContent: Bool {
        if !body.trimmedForGuideEditor.isEmpty {
            return true
        }

        return contentBlocks.contains { block in
            block.isRenderable
        }
    }

    var hasOfficialGuideEditorSource: Bool {
        sourceLinks.contains { sourceLink in
            sourceLink.isOfficial && !sourceLink.url.trimmedForGuideEditor.isEmpty
        }
    }
}

private extension String {
    var trimmedForGuideEditor: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
