import Combine
import Foundation

@MainActor
final class GuideReportsManagementViewModel: ObservableObject {
    @Published private(set) var items: [GuideFeedbackEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    private let repository: FeedbackRepository
    private var hasLoaded = false

    init(repository: FeedbackRepository) {
        self.repository = repository
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        error = nil
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            let feedbackItems = try await repository.fetchFeedback()
            items = feedbackItems
                .compactMap(GuideFeedbackEntry.init(feedback:))
                .sorted { lhs, rhs in lhs.createdAt > rhs.createdAt }
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }
}

struct GuideFeedbackEntry: Identifiable, Hashable {
    let id: String
    let type: FeedbackType
    let message: String
    let materialID: String?
    let materialTitle: String?
    let subjectPrefix: String
    let userID: String
    let createdAt: Date
    let status: FeedbackStatus

    init?(feedback: FeedbackItem) {
        guard let subject = feedback.subject?.trimmingCharacters(in: .whitespacesAndNewlines),
              !subject.isEmpty
        else {
            return nil
        }

        let parts = subject
            .components(separatedBy: "•")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let prefix = parts.first,
              prefix == "Guide" || prefix == "Guide V2"
        else {
            return nil
        }

        id = feedback.id
        type = feedback.type
        message = feedback.message
        materialID = parts.count > 1 ? parts[1] : nil
        materialTitle = parts.count > 2 ? parts[2] : nil
        subjectPrefix = prefix
        userID = feedback.userId
        createdAt = feedback.createdAt
        status = feedback.status
    }
}
