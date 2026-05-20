import PhotosUI
import SwiftUI
import UIKit

struct EventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EventEditorViewModel
    @State private var selectedPhoto: PhotosPickerItem?

    private let onPublished: @MainActor () async -> Void

    init(repository: EventRepository, onPublished: @escaping @MainActor () async -> Void = {}) {
        _viewModel = StateObject(wrappedValue: EventEditorViewModel(repository: repository, mode: .create()))
        self.onPublished = onPublished
    }

    init(
        repository: EventRepository,
        organizationId: String,
        organizationName: String,
        organizationImageURL: String?,
        onPublished: @escaping @MainActor () async -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: EventEditorViewModel(
            repository: repository,
            mode: .create(context: .init(
                organizationId: organizationId,
                organizationName: organizationName,
                organizationImageURL: organizationImageURL
            ))
        ))
        self.onPublished = onPublished
    }

    init(repository: EventRepository, event: Event, onPublished: @escaping @MainActor () async -> Void = {}) {
        _viewModel = StateObject(wrappedValue: EventEditorViewModel(repository: repository, mode: .edit(existing: event)))
        self.onPublished = onPublished
    }

    var body: some View {
        Form {
            Section {
                TextField(AppStrings.Events.fieldTitle, text: $viewModel.title)
                TextField(AppStrings.Events.fieldSummary, text: $viewModel.summary, axis: .vertical)
                    .lineLimit(2...4)
                TextField(AppStrings.Events.fieldDetails, text: $viewModel.details, axis: .vertical)
                    .lineLimit(4...8)
                TextField(AppStrings.Common.city, text: $viewModel.city)
                TextField(AppStrings.Common.venue, text: $viewModel.venue)

                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    Label(AppStrings.NewsEditor.selectPhoto, systemImage: "photo.on.rectangle")
                }

                if let selectedImageData = viewModel.selectedImageData,
                   let image = UIImage(data: selectedImageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }

            Section {
                EventDateFieldRow(
                    title: AppStrings.Events.fieldStartDate,
                    selection: $viewModel.startDate
                )
                EventDateFieldRow(
                    title: AppStrings.Events.fieldEndDate,
                    selection: $viewModel.endDate
                )
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
                        await onPublished()
                        dismiss()
                    }
                } label: {
                    if viewModel.isPublishing || viewModel.isProcessingImage {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(viewModel.isUploadingImage ? AppStrings.NewsEditor.uploadingImage : AppStrings.Events.publishing)
                        }
                    } else {
                        Text(viewModel.submitButtonTitle)
                    }
                }
                .disabled(!viewModel.canPublish)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .tint(AppTheme.accentPrimary)
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                await loadSelectedPhoto(item: newItem)
            }
        }
    }

    private func loadSelectedPhoto(item: PhotosPickerItem?) async {
        guard let item else {
            await MainActor.run {
                viewModel.setImageProcessing(false)
                viewModel.setSelectedImageData(nil)
            }
            return
        }

        await MainActor.run {
            viewModel.setImageProcessing(true)
        }

        do {
            let data = try await item.loadTransferable(type: Data.self)
            guard let data else {
                await MainActor.run {
                    selectedPhoto = nil
                    viewModel.setImageProcessing(false)
                    viewModel.setSelectedImageData(nil)
                    viewModel.errorMessage = AppStrings.NewsEditor.imageLoadFailed
                }
                return
            }

            await MainActor.run {
                viewModel.setImageProcessing(false)
                viewModel.setSelectedImageData(data)
            }
        } catch {
            await MainActor.run {
                selectedPhoto = nil
                viewModel.setImageProcessing(false)
                viewModel.setSelectedImageData(nil)
                viewModel.errorMessage = AppStrings.NewsEditor.imageLoadFailed
            }
        }
    }
}

private struct EventDateFieldRow: View {
    let title: String
    @Binding var selection: Date

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(LocalizationStore.dateString(from: selection, dateStyle: .medium, timeStyle: .short))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            DatePicker(
                title,
                selection: $selection,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        EventEditorView(repository: MockEventRepository())
    }
}
