import Combine
import Foundation

@MainActor
final class OrganizationEditorViewModel: ObservableObject {
    enum Mode {
        case create
        case edit(existing: Organization)

        var isEditing: Bool {
            if case .edit = self {
                return true
            }
            return false
        }
    }

    @Published var name = ""
    @Published var description = ""
    @Published var city = ""
    @Published var contactEmail = ""
    @Published var website = ""
    @Published var selectedImageData: Data?
    @Published var isProcessingImage = false
    @Published var successMessage: String?
    @Published var errorMessage: String?

    private let mode: Mode
    private let validationService = OrganizationValidationService()

    init(mode: Mode = .create) {
        self.mode = mode

        if case let .edit(existingOrganization) = mode {
            name = existingOrganization.name
            description = existingOrganization.description
            city = existingOrganization.city
            contactEmail = existingOrganization.contactEmail ?? ""
            website = existingOrganization.website ?? ""
        }
    }

    var navigationTitle: String {
        mode.isEditing ? AppStrings.Organizations.editTitle : AppStrings.Organizations.editorTitle
    }

    var isEditing: Bool {
        mode.isEditing
    }

    var existingImageURL: String? {
        if case let .edit(existingOrganization) = mode {
            return existingOrganization.imageURL
        }
        return nil
    }

    var submitButtonTitle: String {
        mode.isEditing ? AppStrings.Organizations.saveChanges : AppStrings.Organizations.publish
    }

    var canSubmit: Bool {
        !trimmedName.isEmpty && !trimmedDescription.isEmpty && !trimmedCity.isEmpty && !isProcessingImage
    }

    func setSelectedImageData(_ data: Data?) {
        selectedImageData = data
        if data != nil {
            successMessage = nil
            errorMessage = nil
        }
    }

    func setImageProcessing(_ isProcessing: Bool) {
        isProcessingImage = isProcessing
    }

    func submit(
        with organizationsViewModel: OrganizationsViewModel,
        user: AppUser?
    ) async -> Bool {
        successMessage = nil
        errorMessage = nil

        guard validate() else {
            return false
        }

        let now = Date()
        let organization: Organization
        switch mode {
        case .create:
            organization = Organization(
                id: UUID().uuidString,
                name: trimmedName,
                description: trimmedDescription,
                regionScope: .city,
                federalState: .tirol,
                city: trimmedCity,
                imageURL: nil,
                contactEmail: trimmedContactEmail.nilIfEmpty,
                website: normalizedWebsite.nilIfEmpty,
                createdAt: now,
                updatedAt: now,
                moderationStatus: .approved,
                likeCount: 0,
                likeState: .notLiked
            )
        case let .edit(existing):
            organization = Organization(
                id: existing.id,
                name: trimmedName,
                description: trimmedDescription,
                regionScope: existing.regionScope,
                federalState: existing.federalState,
                city: trimmedCity,
                imageURL: existing.imageURL,
                contactEmail: trimmedContactEmail.nilIfEmpty,
                website: normalizedWebsite.nilIfEmpty,
                createdAt: existing.createdAt,
                updatedAt: now,
                moderationStatus: existing.moderationStatus,
                likeCount: existing.likeCount,
                likeState: existing.likeState
            )
        }

        do {
            switch mode {
            case .create:
                try await organizationsViewModel.createOrganization(
                    organization,
                    imageData: selectedImageData,
                    user: user
                )
                successMessage = AppStrings.Organizations.publishedSuccessfully
                resetForm()
            case .edit:
                try await organizationsViewModel.updateOrganization(
                    organization,
                    imageData: selectedImageData,
                    user: user
                )
                successMessage = AppStrings.Organizations.updatedSuccessfully
            }

            return true
        } catch {
            errorMessage = organizationsViewModel.validationErrorMessage ?? readableErrorMessage(for: error)
            return false
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCity: String {
        city.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedContactEmail: String {
        contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedWebsite: String {
        website.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedWebsite: String {
        guard !trimmedWebsite.isEmpty else { return "" }
        guard URL(string: trimmedWebsite)?.scheme?.isEmpty != false else { return trimmedWebsite }
        return "https://\(trimmedWebsite)"
    }

    private func validate() -> Bool {
        let errors = validationService.validate(
            name: name,
            description: description,
            city: city,
            contactEmail: contactEmail,
            website: normalizedWebsite
        )

        guard let firstError = errors.first else {
            return true
        }

        errorMessage = firstError
        return false
    }

    private func resetForm() {
        name = ""
        description = ""
        city = ""
        contactEmail = ""
        website = ""
        selectedImageData = nil
    }

    private func readableErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? AppStrings.Organizations.actionUnknownError : message
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
