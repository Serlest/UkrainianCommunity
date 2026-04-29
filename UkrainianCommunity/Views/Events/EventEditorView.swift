import SwiftUI

struct EventEditorView: View {
    @StateObject private var viewModel: EventEditorViewModel

    private let onPublished: @MainActor () -> Void

    init(repository: EventRepository, onPublished: @escaping @MainActor () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: EventEditorViewModel(repository: repository))
        self.onPublished = onPublished
    }

    var body: some View {
        Form {
            Section {
                TextField(AppStrings.Events.fieldTitle, text: $viewModel.title)
                TextField(String(localized: "events.editor.field.summary", defaultValue: "Summary"), text: $viewModel.summary, axis: .vertical)
                    .lineLimit(2...4)
                TextField(String(localized: "events.editor.field.details", defaultValue: "Details"), text: $viewModel.details, axis: .vertical)
                    .lineLimit(4...8)
                TextField(AppStrings.Common.city, text: $viewModel.city)
                TextField(AppStrings.Common.venue, text: $viewModel.venue)
            }

            Section {
                DatePicker(AppStrings.Events.fieldStartDate, selection: $viewModel.startDate)
                DatePicker(AppStrings.Events.fieldEndDate, selection: $viewModel.endDate)
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let successMessage = viewModel.successMessage {
                Section {
                    Text(successMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }

            Section {
                Button {
                    Task {
                        let didPublish = await viewModel.publish()
                        guard didPublish else { return }
                        onPublished()
                    }
                } label: {
                    if viewModel.isPublishing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(AppStrings.Events.publishing)
                        }
                    } else {
                        Text(AppStrings.Events.publish)
                    }
                }
                .disabled(!viewModel.canPublish)
            }
        }
        .navigationTitle(AppStrings.Events.editorTitle)
    }
}

#Preview {
    NavigationStack {
        EventEditorView(repository: MockEventRepository())
    }
}
