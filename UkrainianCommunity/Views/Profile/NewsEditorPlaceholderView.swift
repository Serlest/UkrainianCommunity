import SwiftUI

struct NewsEditorPlaceholderView: View {
    @State private var title = ""
    @State private var summary = ""
    @State private var bodyText = ""
    @State private var imageURL = ""
    @State private var isPublishing = false
    @State private var successMessage: String?
    @State private var errorMessage: String?

    private let repository = FirestoreNewsRepository()

    private var trimmedImageURL: String? {
        let value = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isPublishing
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                TextField("Summary", text: $summary)
                TextField("Body", text: $bodyText, axis: .vertical)
                    .lineLimit(5, reservesSpace: true)
                TextField("Image URL", text: $imageURL)
            }

            Section {
                if isPublishing {
                    ProgressView()
                }

                if let successMessage {
                    Text(successMessage)
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }

                Button("Publish") {
                    publishNews()
                }
                .disabled(!canPublish)
            }
        }
        .navigationTitle("Create News")
    }

    private func publishNews() {
        let now = Date()
        let news = NewsPost(
            id: UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            imageURL: trimmedImageURL,
            body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
            authorName: "Admin",
            publishedAt: now,
            createdAt: now,
            updatedAt: now,
            comments: [],
            moderationStatus: .approved,
            likeCount: 0,
            likeState: .notLiked
        )

        Task {
            isPublishing = true
            successMessage = nil
            errorMessage = nil

            do {
                try await repository.createNews(news)
                successMessage = "News published successfully."
                title = ""
                summary = ""
                bodyText = ""
                imageURL = ""
            } catch {
                errorMessage = "Failed to publish news."
            }

            isPublishing = false
        }
    }
}

#Preview {
    NavigationStack {
        NewsEditorPlaceholderView()
    }
}
