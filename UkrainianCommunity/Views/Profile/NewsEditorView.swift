import SwiftUI

struct NewsEditorView: View {
    @StateObject private var viewModel: NewsEditorViewModel

    init() {
        _viewModel = StateObject(wrappedValue: NewsEditorViewModel(repository: FirestoreNewsRepository()))
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $viewModel.title)
                TextField("Summary", text: $viewModel.summary)
                TextField("Body", text: $viewModel.body, axis: .vertical)
                    .lineLimit(5, reservesSpace: true)
                TextField("Image URL", text: $viewModel.imageURL)
            }

            Section {
                if viewModel.isPublishing {
                    ProgressView()
                }

                if let successMessage = viewModel.successMessage {
                    Text(successMessage)
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }

                Button("Publish") {
                    Task {
                        await viewModel.publish()
                    }
                }
                .disabled(!viewModel.canPublish)
            }
        }
        .navigationTitle("Create News")
    }
}

#Preview {
    NavigationStack {
        NewsEditorView()
    }
}
