import PhotosUI
import SwiftUI
import UIKit

struct EventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EventEditorViewModel
    @State private var selectedPhoto: PhotosPickerItem?

    private let onPublished: @MainActor () async -> Void

    init(repository: EventRepository, onPublished: @escaping @MainActor () async -> Void = {}) {
        _viewModel = StateObject(wrappedValue: EventEditorViewModel(repository: repository))
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
                        print("Event onPublished callback start")
                        await onPublished()
                        print("Event onPublished callback success")
                        dismiss()
                    }
                } label: {
                    if viewModel.isPublishing || viewModel.isProcessingImage {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(viewModel.isUploadingImage ? AppStrings.NewsEditor.uploadingImage : AppStrings.Events.publishing)
                        }
                    } else {
                        Text(AppStrings.Events.publish)
                    }
                }
                .disabled(!viewModel.canPublish)
            }
        }
        .navigationTitle(AppStrings.Events.editorTitle)
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
            await MainActor.run {
                viewModel.setImageProcessing(false)
                viewModel.setSelectedImageData(data)
            }
        } catch {
            await MainActor.run {
                viewModel.setImageProcessing(false)
                viewModel.errorMessage = AppStrings.NewsEditor.imageLoadFailed
            }
        }
    }
}

#Preview {
    NavigationStack {
        EventEditorView(repository: MockEventRepository())
    }
}
