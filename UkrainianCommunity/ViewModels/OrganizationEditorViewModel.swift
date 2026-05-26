import Combine
import Foundation

enum OrganizationEditorCategory: String, CaseIterable, Identifiable {
    case education
    case culture
    case support
    case integration
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .education:
            AppStrings.Organizations.categoryEducation
        case .culture:
            AppStrings.Organizations.categoryCulture
        case .support:
            AppStrings.Organizations.categorySupport
        case .integration:
            AppStrings.Organizations.categoryIntegration
        case .other:
            AppStrings.Organizations.categoryOther
        }
    }

    var systemImage: String {
        switch self {
        case .education:
            "graduationcap"
        case .culture:
            "theatermasks"
        case .support:
            "hands.clap"
        case .integration:
            "person.2"
        case .other:
            "square.grid.2x2"
        }
    }
}

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

    static let shortDescriptionLimit = 160
    static let fullDescriptionLimit = 1200

    @Published var name = ""
    @Published var shortDescription = "" {
        didSet {
            enforceShortDescriptionLimit()
        }
    }
    @Published var fullDescription = "" {
        didSet {
            enforceFullDescriptionLimit()
        }
    }
    @Published var city = ""
    @Published var address = ""
    @Published var selectedFederalState: AustrianFederalState?
    @Published var email = ""
    @Published var phone = ""
    @Published var website = ""
    @Published var telegramURL = ""
    @Published var donationURL = ""
    @Published var missionStatement = ""
    @Published var contactPerson = ""
    @Published var organizationType = OrganizationEditorCategory.support.rawValue
    @Published var foundedYear = "" {
        didSet {
            if trimmedFoundedYear.isEmpty {
                foundedMonth = nil
            }
        }
    }
    @Published var foundedMonth: Int?
    @Published var languages = ""
    @Published var socialLinks = ""
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
            shortDescription = Self.limitedShortDescription(existingOrganization.shortDescription)
            fullDescription = Self.limitedFullDescription(existingOrganization.fullDescription)
            city = existingOrganization.city
            address = existingOrganization.address ?? ""
            selectedFederalState = existingOrganization.federalState
            email = existingOrganization.email ?? existingOrganization.contactEmail ?? ""
            phone = existingOrganization.phone ?? ""
            website = existingOrganization.website ?? ""
            telegramURL = existingOrganization.telegramURL ?? ""
            donationURL = existingOrganization.donationURL ?? ""
            missionStatement = existingOrganization.missionStatement ?? ""
            contactPerson = existingOrganization.contactPerson ?? ""
            organizationType = existingOrganization.organizationType ?? OrganizationEditorCategory.support.rawValue
            foundedYear = existingOrganization.foundedYear.map(String.init) ?? ""
            foundedMonth = existingOrganization.foundedYear == nil ? nil : existingOrganization.foundedMonth
            languages = existingOrganization.languages.joined(separator: ", ")
            socialLinks = Self.socialLinksText(from: existingOrganization.socialLinks)
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
            return existingOrganization.logoURL ?? existingOrganization.imageURL
        }
        return nil
    }

    func submitButtonTitle(for user: AppUser?) -> String {
        if mode.isEditing {
            return shouldResubmitRequest(user: user) ? AppStrings.Organizations.resubmitRequest : AppStrings.Organizations.saveChanges
        }
        return isPlatformOwner(user) ? AppStrings.Organizations.publish : AppStrings.Organizations.submitRequest
    }

    var canSubmit: Bool {
        !trimmedName.isEmpty &&
            !trimmedShortDescription.isEmpty &&
            selectedFederalState != nil &&
            !trimmedOrganizationType.isEmpty &&
            !isProcessingImage
    }

    var canSelectFoundedMonth: Bool {
        parsedFoundedYear != nil
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
            let legacyImageURL: String? = nil
            let isOwnerCreate = isPlatformOwner(user)
            organization = Organization(
                id: UUID().uuidString,
                name: trimmedName,
                description: trimmedShortDescription,
                shortDescription: trimmedShortDescription,
                fullDescription: trimmedFullDescription.nilIfEmpty ?? trimmedShortDescription,
                regionScope: .federalState,
                federalState: selectedFederalState,
                city: trimmedCity,
                imageURL: legacyImageURL,
                logoURL: legacyImageURL,
                coverURL: legacyImageURL,
                contactEmail: trimmedEmail.nilIfEmpty,
                email: trimmedEmail.nilIfEmpty,
                phone: trimmedPhone.nilIfEmpty,
                website: normalizedWebsite.nilIfEmpty,
                address: trimmedAddress.nilIfEmpty,
                organizationType: trimmedOrganizationType.nilIfEmpty,
                foundedYear: parsedFoundedYear,
                foundedMonth: parsedFoundedMonth,
                languages: parsedLanguages,
                socialLinks: parsedSocialLinks,
                telegramURL: normalizedTelegramURL.nilIfEmpty,
                donationURL: normalizedDonationURL.nilIfEmpty,
                missionStatement: trimmedMissionStatement.nilIfEmpty,
                contactPerson: trimmedContactPerson.nilIfEmpty,
                submittedByUserId: isOwnerCreate ? nil : user?.id,
                submittedByDisplayName: isOwnerCreate ? nil : displayName(for: user),
                submittedAt: isOwnerCreate ? nil : now,
                createdAt: now,
                updatedAt: now,
                moderationStatus: isOwnerCreate ? .approved : .pendingReview,
                likeCount: 0,
                likeState: .notLiked
            )
        case let .edit(existing):
            let shouldResubmit = shouldResubmitRequest(user: user)
            organization = Organization(
                id: existing.id,
                name: trimmedName,
                description: trimmedShortDescription,
                shortDescription: trimmedShortDescription,
                fullDescription: trimmedFullDescription.nilIfEmpty ?? trimmedShortDescription,
                regionScope: existing.regionScope,
                federalState: selectedFederalState,
                city: trimmedCity,
                imageURL: existing.imageURL,
                logoURL: existing.logoURL,
                coverURL: existing.coverURL,
                contactEmail: trimmedEmail.nilIfEmpty,
                email: trimmedEmail.nilIfEmpty,
                phone: trimmedPhone.nilIfEmpty,
                website: normalizedWebsite.nilIfEmpty,
                address: trimmedAddress.nilIfEmpty,
                latitude: existing.latitude,
                longitude: existing.longitude,
                organizationType: trimmedOrganizationType.nilIfEmpty,
                foundedYear: parsedFoundedYear,
                foundedMonth: parsedFoundedMonth,
                languages: parsedLanguages,
                socialLinks: parsedSocialLinks,
                telegramURL: normalizedTelegramURL.nilIfEmpty,
                donationURL: normalizedDonationURL.nilIfEmpty,
                missionStatement: trimmedMissionStatement.nilIfEmpty,
                contactPerson: trimmedContactPerson.nilIfEmpty,
                subscriberCount: existing.subscriberCount,
                eventsHeldCount: existing.eventsHeldCount,
                volunteersCount: existing.volunteersCount,
                helpedPeopleCount: existing.helpedPeopleCount,
                ownerId: existing.ownerId,
                adminIds: existing.adminIds,
                moderatorIds: existing.moderatorIds,
                pinnedNewsId: existing.pinnedNewsId,
                pinnedEventId: existing.pinnedEventId,
                submittedByUserId: existing.submittedByUserId,
                submittedByDisplayName: existing.submittedByDisplayName,
                submittedAt: shouldResubmit ? now : existing.submittedAt,
                reviewMessage: shouldResubmit ? nil : existing.reviewMessage,
                reviewedByUserId: existing.reviewedByUserId,
                reviewedAt: existing.reviewedAt,
                rejectionReason: shouldResubmit ? nil : existing.rejectionReason,
                createdAt: existing.createdAt,
                updatedAt: now,
                moderationStatus: shouldResubmit ? .pendingReview : existing.moderationStatus,
                likeCount: existing.likeCount,
                likeState: existing.likeState,
                isSubscribed: existing.isSubscribed,
                isBookmarked: existing.isBookmarked
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
                successMessage = isPlatformOwner(user)
                    ? AppStrings.Organizations.publishedSuccessfully
                    : AppStrings.Organizations.requestSubmittedSuccessfully
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

    private var trimmedShortDescription: String {
        Self.limitedShortDescription(shortDescription.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var trimmedFullDescription: String {
        Self.limitedFullDescription(fullDescription.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var trimmedCity: String {
        city.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPhone: String {
        phone.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedWebsite: String {
        website.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTelegramURL: String {
        telegramURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDonationURL: String {
        donationURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedMissionStatement: String {
        missionStatement.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedContactPerson: String {
        contactPerson.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedOrganizationType: String {
        organizationType.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedFoundedYear: String {
        foundedYear.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedFoundedYear: Int? {
        Int(trimmedFoundedYear)
    }

    private var parsedFoundedMonth: Int? {
        guard parsedFoundedYear != nil else { return nil }
        return foundedMonth.flatMap { (1...12).contains($0) ? $0 : nil }
    }

    private var parsedLanguages: [String] {
        languages.commaSeparatedValues
    }

    private var parsedSocialLinks: [String: String] {
        socialLinks.commaSeparatedValues.reduce(into: [:]) { result, value in
            if let separatorIndex = value.firstIndex(of: ":") {
                let key = String(value[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let link = String(value[value.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty, !link.isEmpty {
                    result[key] = Self.normalizedSocialLink(link, key: key)
                }
            } else if let host = URL(string: value)?.host {
                result[host] = Self.normalizedSocialLink(value, key: host)
            }
        }
    }

    private var normalizedWebsite: String {
        guard !trimmedWebsite.isEmpty else { return "" }
        guard URL(string: trimmedWebsite)?.scheme?.isEmpty != false else { return trimmedWebsite }
        return "https://\(trimmedWebsite)"
    }

    private var normalizedTelegramURL: String {
        Self.normalizedTelegramURL(trimmedTelegramURL)
    }

    private var normalizedDonationURL: String {
        Self.normalizedWebURL(trimmedDonationURL)
    }

    private func validate() -> Bool {
        let errors = validationService.validate(
            name: name,
            shortDescription: shortDescription,
            region: selectedFederalState,
            city: city,
            email: email,
            website: normalizedWebsite,
            foundedYear: foundedYear
        )

        let optionalURLErrors = validateOptionalURLs()
        if let firstURLError = optionalURLErrors.first {
            errorMessage = firstURLError
            return false
        }

        guard let firstError = errors.first else {
            return true
        }

        errorMessage = firstError
        return false
    }

    private func resetForm() {
        name = ""
        shortDescription = ""
        fullDescription = ""
        city = ""
        address = ""
        selectedFederalState = nil
        email = ""
        phone = ""
        website = ""
        telegramURL = ""
        donationURL = ""
        missionStatement = ""
        contactPerson = ""
        organizationType = OrganizationEditorCategory.support.rawValue
        foundedYear = ""
        foundedMonth = nil
        languages = ""
        socialLinks = ""
        selectedImageData = nil
    }

    private func readableErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? AppStrings.Organizations.actionUnknownError : message
    }

    private func isPlatformOwner(_ user: AppUser?) -> Bool {
        user?.globalRole.authorizationRole == .owner
    }

    private func shouldResubmitRequest(user: AppUser?) -> Bool {
        guard case let .edit(existing) = mode else { return false }
        guard existing.submittedByUserId == user?.id else { return false }
        return existing.moderationStatus == .needsRevision || existing.moderationStatus == .rejected
    }

    private func displayName(for user: AppUser?) -> String? {
        guard let user else { return nil }
        let displayName = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty { return displayName }
        let fullName = user.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return fullName.isEmpty ? user.email : fullName
    }

    private static func socialLinksText(from links: [String: String]) -> String {
        links
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")
    }

    private static func normalizedWebURL(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard URL(string: trimmed)?.scheme?.isEmpty != false else { return trimmed }
        return "https://\(trimmed)"
    }

    private static func normalizedTelegramURL(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if trimmed.hasPrefix("@") {
            return "https://t.me/\(trimmed.dropFirst())"
        }

        let lowercase = trimmed.lowercased()
        if lowercase.hasPrefix("t.me/") || lowercase.hasPrefix("telegram.me/") {
            return "https://\(trimmed)"
        }

        return normalizedWebURL(trimmed)
    }

    private static func normalizedSocialLink(_ rawValue: String, key: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let lowercaseKey = key.lowercased()
        let lowercaseValue = trimmed.lowercased()
        if lowercaseKey.contains("telegram") || lowercaseValue.hasPrefix("@") || lowercaseValue.contains("t.me/") {
            return normalizedTelegramURL(trimmed)
        }
        if lowercaseKey.contains("instagram"), !lowercaseValue.contains("instagram.com") {
            let username = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
            return normalizedWebURL("instagram.com/\(username)")
        }
        if lowercaseKey.contains("facebook"), !lowercaseValue.contains("facebook.com") && !lowercaseValue.contains("fb.com") {
            return normalizedWebURL("facebook.com/\(trimmed)")
        }
        return normalizedWebURL(trimmed)
    }

    private func validateOptionalURLs() -> [String] {
        [normalizedTelegramURL, normalizedDonationURL]
            .filter { !$0.isEmpty }
            .compactMap { value in
                URL(string: value)?.scheme?.isEmpty == false ? nil : AppStrings.Validation.organizationWebsiteInvalid
            }
    }

    private func enforceShortDescriptionLimit() {
        let limitedValue = Self.limitedShortDescription(shortDescription)
        if shortDescription != limitedValue {
            shortDescription = limitedValue
        }
    }

    private func enforceFullDescriptionLimit() {
        let limitedValue = Self.limitedFullDescription(fullDescription)
        if fullDescription != limitedValue {
            fullDescription = limitedValue
        }
    }

    private static func limitedShortDescription(_ value: String) -> String {
        String(value.prefix(shortDescriptionLimit))
    }

    private static func limitedFullDescription(_ value: String) -> String {
        String(value.prefix(fullDescriptionLimit))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var commaSeparatedValues: [String] {
        split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
