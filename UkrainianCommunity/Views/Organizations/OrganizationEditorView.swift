import PhotosUI
import SwiftUI
import UIKit

struct OrganizationEditorView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var organizationsViewModel: OrganizationsViewModel
    @StateObject private var viewModel: OrganizationEditorViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    private let onSaved: @MainActor () async -> Void

    init(
        organizationsViewModel: OrganizationsViewModel,
        onSaved: @escaping @MainActor () async -> Void = {}
    ) {
        self.organizationsViewModel = organizationsViewModel
        _viewModel = StateObject(wrappedValue: OrganizationEditorViewModel(mode: .create))
        self.onSaved = onSaved
    }

    init(
        organizationsViewModel: OrganizationsViewModel,
        organization: Organization,
        onSaved: @escaping @MainActor () async -> Void = {}
    ) {
        self.organizationsViewModel = organizationsViewModel
        _viewModel = StateObject(wrappedValue: OrganizationEditorViewModel(mode: .edit(existing: organization)))
        self.onSaved = onSaved
    }

    var body: some View {
        Form {
            Section(AppStrings.Organizations.detailsSectionTitle) {
                TextField(AppStrings.Organizations.fieldName, text: $viewModel.name)
                    .accessibilityLabel(AppStrings.Organizations.fieldName)
                TextField(AppStrings.Organizations.fieldDescription, text: $viewModel.description, axis: .vertical)
                    .lineLimit(4...8)
                    .accessibilityLabel(AppStrings.Organizations.fieldDescription)
                TextField(AppStrings.Common.city, text: $viewModel.city)
                    .accessibilityLabel(AppStrings.Common.city)
                TextField(AppStrings.Organizations.fieldContactEmail, text: $viewModel.contactEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel(AppStrings.Organizations.fieldContactEmail)
                TextField(AppStrings.Organizations.fieldWebsite, text: $viewModel.website)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel(AppStrings.Organizations.fieldWebsite)
            }

            Section(AppStrings.Organizations.imageSectionTitle) {
                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    Label(AppStrings.NewsEditor.selectPhoto, systemImage: "photo.on.rectangle")
                }
                .accessibilityLabel(AppStrings.NewsEditor.selectPhoto)

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
                        let didSave = await viewModel.submit(
                            with: organizationsViewModel,
                            user: authState.user
                        )
                        guard didSave else { return }
                        await onSaved()
                        dismiss()
                    }
                } label: {
                    if organizationsViewModel.isSavingOrganization || viewModel.isProcessingImage {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(
                                organizationsViewModel.isUploadingOrganizationImage
                                    ? AppStrings.NewsEditor.uploadingImage
                                    : AppStrings.Organizations.publishing
                            )
                        }
                    } else {
                        Text(viewModel.submitButtonTitle)
                    }
                }
                .disabled(!viewModel.canSubmit || organizationsViewModel.isSavingOrganization)
                .accessibilityLabel(viewModel.submitButtonTitle)
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

#Preview {
    NavigationStack {
        OrganizationEditorView(organizationsViewModel: OrganizationsViewModel(repository: MockOrganizationRepository()))
    }
    .environmentObject(AuthState())
}
