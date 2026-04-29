import Combine
import Foundation

@MainActor
final class NewsEditorViewModel: ObservableObject {
    @Published var title = ""
    @Published var summary = ""
    @Published var body = ""
    @Published var imageURL = ""
    @Published var isPublishing = false
    @Published var successMessage: String?
    @Published var errorMessage: String?

    private let repository: NewsRepository

    init(repository: NewsRepository) {
        self.repository = repository
    }

    var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isPublishing
    }

    func publish() async {
        let now = Date()
        let trimmedImageURL = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let news = NewsPost(
            id: UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            imageURL: trimmedImageURL.isEmpty ? nil : trimmedImageURL,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            authorName: "Admin",
            publishedAt: now,
            createdAt: now,
            updatedAt: now,
            comments: [],
            moderationStatus: .approved,
            likeCount: 0,
            likeState: .notLiked
        )

        isPublishing = true
        successMessage = nil
        errorMessage = nil

        do {
            try await repository.createNews(news)
            successMessage = "News published successfully."
            title = ""
            summary = ""
            body = ""
            imageURL = ""
        } catch {
            errorMessage = "Failed to publish news."
        }

        isPublishing = false
    }
}
