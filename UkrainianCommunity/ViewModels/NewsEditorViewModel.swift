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
        !trimmedTitle.isEmpty
            && !trimmedBody.isEmpty
            && !isPublishing
    }

    func publish() async {
        successMessage = nil
        errorMessage = nil

        guard validate() else {
            return
        }

        let now = Date()
        let news = NewsPost(
            id: UUID().uuidString,
            title: trimmedTitle,
            subtitle: trimmedSummary,
            imageURL: trimmedImageURL,
            body: trimmedBody,
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
        print("Publishing started")

        do {
            try await repository.createNews(news)
            successMessage = "News published successfully."
            print("Publishing succeeded")
            title = ""
            summary = ""
            body = ""
            imageURL = ""
        } catch {
            errorMessage = "Failed to publish news."
            print("Publishing failed: \(error)")
        }

        isPublishing = false
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSummary: String {
        summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedBody: String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedImageURLString: String {
        imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedImageURL: String? {
        trimmedImageURLString.isEmpty ? nil : trimmedImageURLString
    }

    private func validate() -> Bool {
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Title is required."
            successMessage = nil
            print("Validation failed: \(errorMessage ?? "Unknown validation error.")")
            return false
        }

        guard !trimmedBody.isEmpty else {
            errorMessage = "Body is required."
            successMessage = nil
            print("Validation failed: \(errorMessage ?? "Unknown validation error.")")
            return false
        }

        if let trimmedImageURL {
            guard let url = URL(string: trimmedImageURL),
                  url.scheme != nil,
                  url.host != nil
            else {
                errorMessage = "Image URL must be a valid absolute URL."
                successMessage = nil
                print("Validation failed: \(errorMessage ?? "Unknown validation error.")")
                return false
            }
        }

        return true
    }
}
