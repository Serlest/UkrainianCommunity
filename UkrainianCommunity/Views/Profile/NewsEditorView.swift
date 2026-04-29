import PhotosUI
import SwiftUI
import UIKit

struct NewsEditorView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: NewsEditorViewModel
    @State private var selectedPhoto: PhotosPickerItem?

    init(repository: NewsRepository) {
        _viewModel = StateObject(wrappedValue: NewsEditorViewModel(repository: repository))
    }

    var body: some View {
        Form {
            Section {
                TextField(AppStrings.NewsEditor.fieldTitle, text: $viewModel.title)
                TextField(AppStrings.NewsEditor.fieldSummary, text: $viewModel.summary)
                TextField(AppStrings.NewsEditor.fieldBody, text: $viewModel.body, axis: .vertical)
                    .lineLimit(5, reservesSpace: true)

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
                if viewModel.isPublishing {
                    if viewModel.isUploadingImage {
                        ProgressView(AppStrings.NewsEditor.uploadingImage)
                    } else {
                        ProgressView(AppStrings.NewsEditor.publishing)
                    }
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

                Button(AppStrings.NewsEditor.publish) {
                    Task {
                        await viewModel.publish()
                    }
                }
                .disabled(!viewModel.canPublish)
            }
        }
        .navigationTitle(AppStrings.NewsEditor.title)
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                await loadSelectedPhoto(item: newItem)
            }
        }
        .task(id: authState.user?.id) {
            viewModel.setAuthState(authState)
        }
    }

    private func loadSelectedPhoto(item: PhotosPickerItem?) async {
        guard let item else {
            await MainActor.run {
                viewModel.setSelectedImageData(nil)
            }
            return
        }

        do {
            let data = try await item.loadTransferable(type: Data.self)
            await MainActor.run {
                viewModel.setSelectedImageData(data)
            }
        } catch {
            await MainActor.run {
                viewModel.errorMessage = AppStrings.NewsEditor.imageLoadFailed
            }
        }
    }
}

#Preview {
    NavigationStack {
        NewsEditorView(repository: MockNewsRepository())
    }
    .environmentObject(AuthState())
}
