import Combine
import Foundation

enum OrganizationEditorCategory: String, CaseIterable, Identifiable {
    case ukrainianProducts
    case foodAndDrink
    case retail
    case beautyAndHealth
    case legalAndFinance
    case workAndBusiness
    case education
    case childrenAndFamily
    case culture
    case support
    case integration
    case homeAndTransport
    case media
    case publicInstitution
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ukrainianProducts: AppStrings.Organizations.categoryUkrainianProducts
        case .foodAndDrink: AppStrings.Organizations.categoryFoodAndDrink
        case .retail: AppStrings.Organizations.categoryRetail
        case .beautyAndHealth: AppStrings.Organizations.categoryBeautyAndHealth
        case .legalAndFinance: AppStrings.Organizations.categoryLegalAndFinance
        case .workAndBusiness: AppStrings.Organizations.categoryWorkAndBusiness
        case .education:
            AppStrings.Organizations.categoryEducation
        case .childrenAndFamily: AppStrings.Organizations.categoryChildrenAndFamily
        case .culture:
            AppStrings.Organizations.categoryCulture
        case .support:
            AppStrings.Organizations.categorySupport
        case .integration:
            AppStrings.Organizations.categoryIntegration
        case .homeAndTransport: AppStrings.Organizations.categoryHomeAndTransport
        case .media: AppStrings.Organizations.categoryMedia
        case .publicInstitution: AppStrings.Organizations.categoryPublicInstitution
        case .other:
            AppStrings.Organizations.categoryOther
        }
    }

    var systemImage: String {
        switch self {
        case .ukrainianProducts: "basket"
        case .foodAndDrink: "fork.knife"
        case .retail: "bag"
        case .beautyAndHealth: "cross.case"
        case .legalAndFinance: "briefcase"
        case .workAndBusiness: "building.columns"
        case .education:
            "graduationcap"
        case .childrenAndFamily: "figure.2.and.child.holdinghands"
        case .culture:
            "theatermasks"
        case .support:
            "hands.clap"
        case .integration:
            "person.2"
        case .homeAndTransport: "car"
        case .media: "newspaper"
        case .publicInstitution: "building.2"
        case .other:
            "square.grid.2x2"
        }
    }
}

extension OrganizationProfileKind {
    var title: String {
        switch self {
        case .community: AppStrings.Organizations.profileKindCommunity
        case .business: AppStrings.Organizations.profileKindBusiness
        case .restaurant: AppStrings.Organizations.profileKindRestaurant
        case .specialist: AppStrings.Organizations.profileKindSpecialist
        case .institution: AppStrings.Organizations.profileKindInstitution
        case .mediaProject: AppStrings.Organizations.profileKindMediaProject
        }
    }

    var systemImage: String {
        switch self {
        case .community: "person.3"
        case .business: "storefront"
        case .restaurant: "fork.knife"
        case .specialist: "person.crop.circle.badge.checkmark"
        case .institution: "building.columns"
        case .mediaProject: "newspaper"
        }
    }
}

extension OrganizationServiceMode {
    var title: String {
        switch self {
        case .inStore: AppStrings.Organizations.serviceModeInStore
        case .pickup: AppStrings.Organizations.serviceModePickup
        case .delivery: AppStrings.Organizations.serviceModeDelivery
        case .online: AppStrings.Organizations.serviceModeOnline
        case .onSite: AppStrings.Organizations.serviceModeOnSite
        }
    }

    var systemImage: String {
        switch self {
        case .inStore: "storefront"
        case .pickup: "takeoutbag.and.cup.and.straw"
        case .delivery: "shippingbox"
        case .online: "globe"
        case .onSite: "car"
        }
    }
}

private struct OrganizationServiceSuggestion {
    let ukrainian: String
    let german: String
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

    @Published var name = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var shortDescription = "" {
        didSet {
            enforceShortDescriptionLimit()
            scheduleCreateDraftAutosave()
        }
    }
    @Published var fullDescription = "" {
        didSet {
            enforceFullDescriptionLimit()
            scheduleCreateDraftAutosave()
        }
    }
    @Published var germanName = "" { didSet { scheduleCreateDraftAutosave() } }
    @Published var germanShortDescription = "" { didSet { scheduleCreateDraftAutosave() } }
    @Published var germanFullDescription = "" { didSet { scheduleCreateDraftAutosave() } }
    @Published var germanMissionStatement = "" { didSet { scheduleCreateDraftAutosave() } }
    @Published var germanServiceArea = "" { didSet { scheduleCreateDraftAutosave() } }
    @Published var germanSpecialHoursNote = "" { didSet { scheduleCreateDraftAutosave() } }
    @Published var germanServices = "" { didSet { scheduleCreateDraftAutosave() } }
    @Published var germanCurrentOfferTitle = "" { didSet { scheduleCreateDraftAutosave() } }
    @Published var germanCurrentOfferDetails = "" { didSet { scheduleCreateDraftAutosave() } }
    @Published var city = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var address = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var selectedFederalState: AustrianFederalState? {
        didSet { markCreateDraftMetadataChanged() }
    }
    @Published var email = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var phone = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var website = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var telegramURL = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var donationURL = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var facebookURL = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var instagramURL = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var whatsappURL = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var youtubeURL = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var linkedinURL = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var missionStatement = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var contactPerson = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var organizationType = OrganizationEditorCategory.support.rawValue {
        didSet {
            secondaryCategories.remove(organizationType)
            markCreateDraftMetadataChanged()
        }
    }
    @Published var profileKind = OrganizationProfileKind.community {
        didSet { markCreateDraftMetadataChanged() }
    }
    @Published var secondaryCategories = Set<String>() {
        didSet { markCreateDraftMetadataChanged() }
    }
    @Published var serviceModes = Set<OrganizationServiceMode>() {
        didSet { markCreateDraftMetadataChanged() }
    }
    @Published var serviceArea = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var regularHours = [String: String]() {
        didSet { markCreateDraftMetadataChanged() }
    }
    @Published var specialHoursNote = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var services = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var orderURL = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var bookingURL = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var currentOfferTitle = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var currentOfferDetails = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var currentOfferURL = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var currentOfferValidUntil: Date? {
        didSet { markCreateDraftMetadataChanged() }
    }
    @Published var foundedYear = "" {
        didSet {
            if trimmedFoundedYear.isEmpty {
                foundedMonth = nil
            }
            scheduleCreateDraftAutosave()
        }
    }
    @Published var foundedMonth: Int? {
        didSet { markCreateDraftMetadataChanged() }
    }
    @Published var languages = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    private var legacySocialLinks: [String: String] = [:]
    @Published var selectedImageData: Data?
    @Published var isProcessingImage = false
    @Published var successMessage: String?
    @Published var errorMessage: String?
    @Published private(set) var pendingRecoveryDraft: OrganizationCreateDraft?

    private let mode: Mode
    private let draftRecoveryService: LocalDraftRecoveryService
    private let functionsClient: CloudFunctionsClient
    private let createOrganizationID = UUID().uuidString
    private let validationService = OrganizationValidationService()
    private var draftAutosaveTask: Task<Void, Never>?
    private var hasCheckedCreateDraftRecovery = false
    private var isApplyingRecoveredDraft = false
    private var isSubmittingCreate = false
    private var hasMeaningfulCreateDraftMetadata = false

    init(
        mode: Mode = .create,
        draftRecoveryService: LocalDraftRecoveryService? = nil,
        functionsClient: CloudFunctionsClient? = nil
    ) {
        self.mode = mode
        self.draftRecoveryService = draftRecoveryService ?? .shared
        self.functionsClient = functionsClient ?? .shared

        if case let .edit(existingOrganization) = mode {
            name = existingOrganization.name
            shortDescription = Self.limitedShortDescription(existingOrganization.shortDescription)
            fullDescription = Self.limitedFullDescription(existingOrganization.fullDescription)
            let german = existingOrganization.localizations[PublishedContentLanguage.german.rawValue]
            germanName = german?.name ?? ""
            germanShortDescription = german?.shortDescription ?? ""
            germanFullDescription = german?.fullDescription ?? ""
            germanMissionStatement = german?.missionStatement ?? ""
            germanServiceArea = german?.serviceArea ?? ""
            germanSpecialHoursNote = german?.specialHoursNote ?? ""
            germanServices = german?.services.joined(separator: ", ") ?? ""
            germanCurrentOfferTitle = german?.currentOfferTitle ?? ""
            germanCurrentOfferDetails = german?.currentOfferDetails ?? ""
            city = existingOrganization.city
            address = existingOrganization.address ?? ""
            selectedFederalState = existingOrganization.federalState
            email = existingOrganization.email ?? existingOrganization.contactEmail ?? ""
            phone = existingOrganization.phone ?? ""
            website = existingOrganization.website ?? ""
            telegramURL = existingOrganization.telegramURL ?? ""
            donationURL = existingOrganization.donationURL ?? ""
            facebookURL = existingOrganization.facebookURL ?? Self.socialLinkText(from: existingOrganization.socialLinks, matching: "facebook")
            instagramURL = existingOrganization.instagramURL ?? Self.socialLinkText(from: existingOrganization.socialLinks, matching: "instagram")
            whatsappURL = existingOrganization.whatsappURL ?? Self.socialLinkText(from: existingOrganization.socialLinks, matching: "whatsapp")
            youtubeURL = existingOrganization.youtubeURL ?? Self.socialLinkText(from: existingOrganization.socialLinks, matching: "youtube")
            linkedinURL = existingOrganization.linkedinURL ?? Self.socialLinkText(from: existingOrganization.socialLinks, matching: "linkedin")
            missionStatement = existingOrganization.missionStatement ?? ""
            contactPerson = existingOrganization.contactPerson ?? ""
            organizationType = existingOrganization.organizationType ?? OrganizationEditorCategory.support.rawValue
            let directoryProfile = existingOrganization.directoryProfile
            profileKind = directoryProfile?.profileKind ?? .community
            secondaryCategories = Set(directoryProfile?.secondaryCategories ?? [])
            serviceModes = Set(directoryProfile?.serviceModes ?? [])
            serviceArea = directoryProfile?.serviceArea ?? ""
            regularHours = directoryProfile?.regularHours ?? [:]
            specialHoursNote = directoryProfile?.specialHoursNote ?? ""
            services = directoryProfile?.services.joined(separator: ", ") ?? ""
            orderURL = directoryProfile?.orderURL ?? ""
            bookingURL = directoryProfile?.bookingURL ?? ""
            currentOfferTitle = directoryProfile?.currentOfferTitle ?? ""
            currentOfferDetails = directoryProfile?.currentOfferDetails ?? ""
            currentOfferURL = directoryProfile?.currentOfferURL ?? ""
            currentOfferValidUntil = directoryProfile?.currentOfferValidUntil
            foundedYear = existingOrganization.foundedYear.map(String.init) ?? ""
            foundedMonth = existingOrganization.foundedYear == nil ? nil : existingOrganization.foundedMonth
            languages = existingOrganization.languages.joined(separator: ", ")
            legacySocialLinks = existingOrganization.socialLinks
        }
    }

    deinit {
        draftAutosaveTask?.cancel()
    }

    var navigationTitle: String {
        mode.isEditing ? AppStrings.Organizations.editTitle : AppStrings.Organizations.editorTitle
    }

    var isEditing: Bool {
        mode.isEditing
    }

    var editingOrganizationID: String? {
        guard case let .edit(existing) = mode else { return nil }
        return existing.id
    }

    var hasPendingRecoveryDraft: Bool {
        pendingRecoveryDraft != nil
    }

    var shouldConfirmDraftBeforeDismiss: Bool {
        guard isCreateMode else { return false }
        guard !isSubmittingCreate, !isProcessingImage else { return false }
        return currentOrganizationCreateDraft().hasMeaningfulContent
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

    var canAdvanceBasics: Bool {
        !trimmedName.isEmpty
            && trimmedShortDescription.count >= 20
            && !trimmedOrganizationType.isEmpty
    }

    var canAdvanceLocation: Bool {
        selectedFederalState != nil && !trimmedCity.isEmpty
    }

    func toggleSecondaryCategory(_ category: OrganizationEditorCategory) {
        let value = category.rawValue
        if secondaryCategories.contains(value) {
            secondaryCategories.remove(value)
        } else if value != organizationType,
                  secondaryCategories.count < OrganizationDirectoryProfile.maximumSecondaryCategoryCount {
            secondaryCategories.insert(value)
        }
    }

    func toggleServiceMode(_ mode: OrganizationServiceMode) {
        if serviceModes.contains(mode) {
            serviceModes.remove(mode)
        } else {
            serviceModes.insert(mode)
        }
    }

    func suggestedServices(language: PublishedContentLanguage) -> [String] {
        serviceSuggestions.map { language == .german ? $0.german : $0.ukrainian }
    }

    func isSuggestedServiceSelected(_ value: String, language: PublishedContentLanguage) -> Bool {
        let source = language == .german ? germanServices : services
        return source.commaSeparatedValues.contains { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }
    }

    func toggleSuggestedService(_ value: String, language: PublishedContentLanguage) {
        let source = language == .german ? germanServices : services
        var values = source.commaSeparatedValues
        if let index = values.firstIndex(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) {
            values.remove(at: index)
        } else if values.count < OrganizationDirectoryProfile.maximumServiceCount {
            values.append(value)
        }
        if language == .german {
            germanServices = values.joined(separator: ", ")
        } else {
            services = values.joined(separator: ", ")
        }
    }

    func setHours(_ value: String, for weekday: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        regularHours[weekday] = trimmed.isEmpty ? "closed" : trimmed
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

    func loadRecoverableDraftIfNeeded() async {
        guard isCreateMode, !hasCheckedCreateDraftRecovery else { return }
        hasCheckedCreateDraftRecovery = true

        do {
            guard let draft = try await draftRecoveryService.loadOrganizationCreateDraft(key: createDraftStorageKey),
                  draft.hasMeaningfulContent else {
                pendingRecoveryDraft = nil
                return
            }
            pendingRecoveryDraft = draft
        } catch {
            pendingRecoveryDraft = nil
        }
    }

    func continueRecoveredDraft() {
        guard let draft = pendingRecoveryDraft, isCreateMode else { return }
        applyRecoveredDraft(draft)
        pendingRecoveryDraft = nil
    }

    func createNewInsteadOfRecoveredDraft() async {
        pendingRecoveryDraft = nil
        hasMeaningfulCreateDraftMetadata = false
        try? await draftRecoveryService.deleteOrganizationCreateDraft(key: createDraftStorageKey)
    }

    func deleteRecoveredDraft() async {
        pendingRecoveryDraft = nil
        hasMeaningfulCreateDraftMetadata = false
        try? await draftRecoveryService.deleteOrganizationCreateDraft(key: createDraftStorageKey)
    }

    func saveDraftBeforeClosing() async {
        await saveCurrentCreateDraftIfNeeded()
    }

    func discardCreateDraft() async {
        draftAutosaveTask?.cancel()
        pendingRecoveryDraft = nil
        hasMeaningfulCreateDraftMetadata = false
        try? await draftRecoveryService.deleteOrganizationCreateDraft(key: createDraftStorageKey)
    }

    func submit(
        with organizationsViewModel: OrganizationsViewModel,
        user: AppUser?,
        organizationRulesVersion: String? = nil
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
                id: createOrganizationID,
                localizations: resolvedLocalizations,
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
                directoryProfile: directoryProfileForWrite,
                foundedYear: parsedFoundedYear,
                foundedMonth: parsedFoundedMonth,
                languages: parsedLanguages,
                socialLinks: parsedSocialLinks,
                telegramURL: normalizedTelegramURL.nilIfEmpty,
                donationURL: normalizedDonationURL.nilIfEmpty,
                facebookURL: normalizedFacebookURL.nilIfEmpty,
                instagramURL: normalizedInstagramURL.nilIfEmpty,
                whatsappURL: normalizedWhatsAppURL.nilIfEmpty,
                youtubeURL: normalizedYouTubeURL.nilIfEmpty,
                linkedinURL: normalizedLinkedInURL.nilIfEmpty,
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
                localizations: resolvedLocalizations,
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
                directoryProfile: directoryProfileForWrite,
                foundedYear: parsedFoundedYear,
                foundedMonth: parsedFoundedMonth,
                languages: parsedLanguages,
                socialLinks: parsedSocialLinks,
                telegramURL: normalizedTelegramURL.nilIfEmpty,
                donationURL: normalizedDonationURL.nilIfEmpty,
                facebookURL: normalizedFacebookURL.nilIfEmpty,
                instagramURL: normalizedInstagramURL.nilIfEmpty,
                whatsappURL: normalizedWhatsAppURL.nilIfEmpty,
                youtubeURL: normalizedYouTubeURL.nilIfEmpty,
                linkedinURL: normalizedLinkedInURL.nilIfEmpty,
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
                isSubmittingCreate = true
                defer { isSubmittingCreate = false }
                guard let organizationRulesVersion else {
                    errorMessage = AppStrings.OrganizationRules.loadFailed
                    return false
                }
                do {
                    _ = try await functionsClient.acceptOrganizationRules(
                        organizationId: organization.id,
                        organizationName: organization.name,
                        version: organizationRulesVersion,
                        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                        locale: AppLanguage.stored.rawValue
                    )
                } catch {
                    errorMessage = AppStrings.OrganizationRules.acceptanceFailed
                    return false
                }
                try await organizationsViewModel.createOrganization(
                    organization,
                    imageData: selectedImageData,
                    user: user
                )
                successMessage = isPlatformOwner(user)
                    ? AppStrings.Organizations.publishedSuccessfully
                    : AppStrings.Organizations.requestSubmittedSuccessfully
                draftAutosaveTask?.cancel()
                try? await draftRecoveryService.deleteOrganizationCreateDraft(key: createDraftStorageKey)
                hasMeaningfulCreateDraftMetadata = false
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

    private var directoryProfileForWrite: OrganizationDirectoryProfile {
        OrganizationDirectoryProfile(
            profileKind: profileKind,
            secondaryCategories: secondaryCategories.sorted(),
            serviceModes: serviceModes.sorted { $0.rawValue < $1.rawValue },
            serviceArea: serviceArea,
            regularHours: regularHours,
            specialHoursNote: specialHoursNote,
            services: services.commaSeparatedValues,
            orderURL: Self.normalizedWebURL(orderURL),
            bookingURL: Self.normalizedWebURL(bookingURL),
            currentOfferTitle: currentOfferTitle,
            currentOfferDetails: currentOfferDetails,
            currentOfferURL: Self.normalizedWebURL(currentOfferURL),
            currentOfferValidUntil: currentOfferValidUntil
        )
    }

    private var serviceSuggestions: [OrganizationServiceSuggestion] {
        switch OrganizationEditorCategory(rawValue: organizationType) {
        case .foodAndDrink:
            return [
                .init(ukrainian: "Доставка", german: "Lieferung"),
                .init(ukrainian: "Самовивіз", german: "Abholung"),
                .init(ukrainian: "Бронювання столика", german: "Tischreservierung"),
                .init(ukrainian: "Кейтеринг", german: "Catering")
            ]
        case .legalAndFinance:
            return [
                .init(ukrainian: "Юридична консультація", german: "Rechtsberatung"),
                .init(ukrainian: "Податкова консультація", german: "Steuerberatung"),
                .init(ukrainian: "Допомога з документами", german: "Hilfe bei Dokumenten"),
                .init(ukrainian: "Онлайн-консультація", german: "Online-Beratung")
            ]
        case .education:
            return [
                .init(ukrainian: "Мовні курси", german: "Sprachkurse"),
                .init(ukrainian: "Репетиторство", german: "Nachhilfe"),
                .init(ukrainian: "Онлайн-навчання", german: "Online-Unterricht"),
                .init(ukrainian: "Підготовка до іспитів", german: "Prüfungsvorbereitung")
            ]
        case .beautyAndHealth:
            return [
                .init(ukrainian: "Консультація", german: "Beratung"),
                .init(ukrainian: "Запис онлайн", german: "Online-Termin"),
                .init(ukrainian: "Виїзд додому", german: "Hausbesuch"),
                .init(ukrainian: "Подарунковий сертифікат", german: "Gutschein")
            ]
        case .support, .integration, .childrenAndFamily:
            return [
                .init(ukrainian: "Безкоштовна консультація", german: "Kostenlose Beratung"),
                .init(ukrainian: "Допомога з документами", german: "Hilfe bei Dokumenten"),
                .init(ukrainian: "Підтримка сімей", german: "Familienhilfe"),
                .init(ukrainian: "Онлайн-підтримка", german: "Online-Unterstützung")
            ]
        default:
            return [
                .init(ukrainian: "Консультація", german: "Beratung"),
                .init(ukrainian: "Запис онлайн", german: "Online-Termin"),
                .init(ukrainian: "Доставка", german: "Lieferung"),
                .init(ukrainian: "Виїзд", german: "Vor-Ort-Service")
            ]
        }
    }

    private var hasGermanContent: Bool {
        [
            germanName, germanShortDescription, germanFullDescription, germanMissionStatement,
            germanServiceArea, germanSpecialHoursNote, germanServices,
            germanCurrentOfferTitle, germanCurrentOfferDetails
        ].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var resolvedLocalizations: [String: OrganizationLocalizedContent] {
        var result = [PublishedContentLanguage.ukrainian.rawValue: OrganizationLocalizedContent(
            name: trimmedName,
            shortDescription: trimmedShortDescription,
            fullDescription: trimmedFullDescription.nilIfEmpty ?? trimmedShortDescription,
            missionStatement: trimmedMissionStatement.nilIfEmpty,
            serviceArea: serviceArea.trimmed.nilIfEmpty,
            specialHoursNote: specialHoursNote.trimmed.nilIfEmpty,
            services: services.commaSeparatedValues,
            currentOfferTitle: currentOfferTitle.trimmed.nilIfEmpty,
            currentOfferDetails: currentOfferDetails.trimmed.nilIfEmpty
        )]
        if hasGermanContent {
            result[PublishedContentLanguage.german.rawValue] = OrganizationLocalizedContent(
                name: germanName.organizationTrimmedOrFallback(trimmedName),
                shortDescription: germanShortDescription.organizationTrimmedOrFallback(trimmedShortDescription),
                fullDescription: germanFullDescription.organizationTrimmedOrFallback(trimmedFullDescription.nilIfEmpty ?? trimmedShortDescription),
                missionStatement: germanMissionStatement.trimmed.nilIfEmpty ?? trimmedMissionStatement.nilIfEmpty,
                serviceArea: germanServiceArea.trimmed.nilIfEmpty ?? serviceArea.trimmed.nilIfEmpty,
                specialHoursNote: germanSpecialHoursNote.trimmed.nilIfEmpty ?? specialHoursNote.trimmed.nilIfEmpty,
                services: germanServices.commaSeparatedValues.isEmpty ? services.commaSeparatedValues : germanServices.commaSeparatedValues,
                currentOfferTitle: germanCurrentOfferTitle.trimmed.nilIfEmpty ?? currentOfferTitle.trimmed.nilIfEmpty,
                currentOfferDetails: germanCurrentOfferDetails.trimmed.nilIfEmpty ?? currentOfferDetails.trimmed.nilIfEmpty
            )
        }
        return result
    }

    private var parsedSocialLinks: [String: String] {
        legacySocialLinks.filter { key, _ in
            let lowercasedKey = key.lowercased()
            return !["facebook", "instagram", "whatsapp", "youtube", "linkedin"].contains { lowercasedKey.contains($0) }
        }
    }

    private var isCreateMode: Bool {
        if case .create = mode {
            return true
        }
        return false
    }

    private var createDraftStorageKey: String {
        "organization-create"
    }

    private func scheduleCreateDraftAutosave() {
        guard isCreateMode, !isApplyingRecoveredDraft else { return }
        guard !isSubmittingCreate, !isProcessingImage else { return }

        draftAutosaveTask?.cancel()
        draftAutosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            await self?.saveCurrentCreateDraftIfNeeded()
        }
    }

    private func markCreateDraftMetadataChanged() {
        guard isCreateMode, !isApplyingRecoveredDraft else { return }
        guard !isSubmittingCreate, !isProcessingImage else { return }
        hasMeaningfulCreateDraftMetadata = true
        scheduleCreateDraftAutosave()
    }

    private func saveCurrentCreateDraftIfNeeded() async {
        guard isCreateMode else { return }
        guard !isSubmittingCreate, !isProcessingImage else { return }

        let draft = currentOrganizationCreateDraft()
        do {
            if draft.hasMeaningfulContent {
                try await draftRecoveryService.saveOrganizationCreateDraft(draft, key: createDraftStorageKey)
            } else {
                try await draftRecoveryService.deleteOrganizationCreateDraft(key: createDraftStorageKey)
            }
        } catch {
            // Draft recovery is best-effort and must not block organization creation.
        }
    }

    private func currentOrganizationCreateDraft(updatedAt: Date = Date()) -> OrganizationCreateDraft {
        OrganizationCreateDraft(
            version: OrganizationCreateDraft.currentVersion,
            hasMeaningfulMetadata: hasMeaningfulCreateDraftMetadata,
            updatedAt: updatedAt,
            name: name,
            shortDescription: shortDescription,
            fullDescription: fullDescription,
            germanName: germanName,
            germanShortDescription: germanShortDescription,
            germanFullDescription: germanFullDescription,
            germanMissionStatement: germanMissionStatement,
            germanServiceArea: germanServiceArea,
            germanSpecialHoursNote: germanSpecialHoursNote,
            germanServices: germanServices,
            germanCurrentOfferTitle: germanCurrentOfferTitle,
            germanCurrentOfferDetails: germanCurrentOfferDetails,
            city: city,
            address: address,
            selectedFederalState: selectedFederalState,
            email: email,
            phone: phone,
            website: website,
            telegramURL: telegramURL,
            donationURL: donationURL,
            facebookURL: facebookURL,
            instagramURL: instagramURL,
            whatsappURL: whatsappURL,
            youtubeURL: youtubeURL,
            linkedinURL: linkedinURL,
            missionStatement: missionStatement,
            contactPerson: contactPerson,
            organizationType: organizationType,
            profileKind: profileKind.rawValue,
            secondaryCategories: secondaryCategories.sorted(),
            serviceModes: serviceModes.map(\.rawValue).sorted(),
            serviceArea: serviceArea,
            regularHours: regularHours,
            specialHoursNote: specialHoursNote,
            services: services,
            orderURL: orderURL,
            bookingURL: bookingURL,
            currentOfferTitle: currentOfferTitle,
            currentOfferDetails: currentOfferDetails,
            currentOfferURL: currentOfferURL,
            currentOfferValidUntil: currentOfferValidUntil,
            foundedYear: foundedYear,
            foundedMonth: foundedMonth,
            languages: languages,
            socialLinks: Self.socialLinksText(from: legacySocialLinks)
        )
    }

    private func applyRecoveredDraft(_ draft: OrganizationCreateDraft) {
        isApplyingRecoveredDraft = true

        name = draft.name
        shortDescription = Self.limitedShortDescription(draft.shortDescription)
        fullDescription = Self.limitedFullDescription(draft.fullDescription)
        germanName = draft.germanName ?? ""
        germanShortDescription = draft.germanShortDescription ?? ""
        germanFullDescription = draft.germanFullDescription ?? ""
        germanMissionStatement = draft.germanMissionStatement ?? ""
        germanServiceArea = draft.germanServiceArea ?? ""
        germanSpecialHoursNote = draft.germanSpecialHoursNote ?? ""
        germanServices = draft.germanServices ?? ""
        germanCurrentOfferTitle = draft.germanCurrentOfferTitle ?? ""
        germanCurrentOfferDetails = draft.germanCurrentOfferDetails ?? ""
        city = draft.city
        address = draft.address
        selectedFederalState = draft.selectedFederalState
        email = draft.email
        phone = draft.phone
        website = draft.website
        telegramURL = draft.telegramURL
        donationURL = draft.donationURL
        facebookURL = draft.facebookURL ?? ""
        instagramURL = draft.instagramURL ?? ""
        whatsappURL = draft.whatsappURL ?? ""
        youtubeURL = draft.youtubeURL ?? ""
        linkedinURL = draft.linkedinURL ?? ""
        missionStatement = draft.missionStatement
        contactPerson = draft.contactPerson
        organizationType = draft.organizationType
        profileKind = draft.profileKind.flatMap(OrganizationProfileKind.init(rawValue:)) ?? .community
        secondaryCategories = Set(draft.secondaryCategories ?? [])
        serviceModes = Set((draft.serviceModes ?? []).compactMap(OrganizationServiceMode.init(rawValue:)))
        serviceArea = draft.serviceArea ?? ""
        regularHours = draft.regularHours ?? [:]
        specialHoursNote = draft.specialHoursNote ?? ""
        services = draft.services ?? ""
        orderURL = draft.orderURL ?? ""
        bookingURL = draft.bookingURL ?? ""
        currentOfferTitle = draft.currentOfferTitle ?? ""
        currentOfferDetails = draft.currentOfferDetails ?? ""
        currentOfferURL = draft.currentOfferURL ?? ""
        currentOfferValidUntil = draft.currentOfferValidUntil
        foundedYear = draft.foundedYear
        foundedMonth = draft.foundedMonth
        languages = draft.languages
        legacySocialLinks = Self.parsedLegacySocialLinks(from: draft.socialLinks)
        hasMeaningfulCreateDraftMetadata = draft.hasMeaningfulMetadata == true

        isApplyingRecoveredDraft = false
    }

    private var normalizedWebsite: String {
        OrganizationWebURL.normalizedInput(trimmedWebsite)
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
        germanName = ""
        germanShortDescription = ""
        germanFullDescription = ""
        germanMissionStatement = ""
        germanServiceArea = ""
        germanSpecialHoursNote = ""
        germanServices = ""
        germanCurrentOfferTitle = ""
        germanCurrentOfferDetails = ""
        city = ""
        address = ""
        selectedFederalState = nil
        email = ""
        phone = ""
        website = ""
        telegramURL = ""
        donationURL = ""
        facebookURL = ""
        instagramURL = ""
        whatsappURL = ""
        youtubeURL = ""
        linkedinURL = ""
        missionStatement = ""
        contactPerson = ""
        organizationType = OrganizationEditorCategory.support.rawValue
        profileKind = .community
        secondaryCategories = []
        serviceModes = []
        serviceArea = ""
        regularHours = [:]
        specialHoursNote = ""
        services = ""
        orderURL = ""
        bookingURL = ""
        currentOfferTitle = ""
        currentOfferDetails = ""
        currentOfferURL = ""
        currentOfferValidUntil = nil
        foundedYear = ""
        foundedMonth = nil
        languages = ""
        legacySocialLinks = [:]
        selectedImageData = nil
    }

    private func readableErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? AppStrings.Organizations.actionUnknownError : message
    }

    private func isPlatformOwner(_ user: AppUser?) -> Bool {
        PermissionService.isAppOwner(user: user)
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

    private static func socialLinkText(from links: [String: String], matching platform: String) -> String {
        links.first { key, value in
            key.localizedCaseInsensitiveContains(platform) ||
                value.localizedCaseInsensitiveContains(platform)
        }?.value ?? ""
    }

    private static func parsedLegacySocialLinks(from text: String) -> [String: String] {
        text.commaSeparatedValues.reduce(into: [:]) { result, value in
            if let separatorIndex = value.firstIndex(of: ":") {
                let key = String(value[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let link = String(value[value.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty, !link.isEmpty {
                    result[key] = normalizedSocialLink(link, key: key)
                }
            } else if let host = URL(string: value)?.host {
                result[host] = normalizedWebURL(value)
            }
        }
    }

    private static func normalizedWebURL(_ rawValue: String) -> String {
        OrganizationWebURL.normalizedInput(rawValue)
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
        if lowercaseKey.contains("telegram") || lowercaseValue.contains("t.me/") {
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

    private static func normalizedPlatformURL(_ rawValue: String, host: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return trimmed
        }
        if lowercased.contains(host) {
            return normalizedWebURL(trimmed)
        }
        let handle = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        return normalizedWebURL("\(host)/\(handle)")
    }

    private static func normalizedWhatsAppURL(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return trimmed
        }
        if lowercased.contains("wa.me/") || lowercased.contains("whatsapp.com/") {
            return normalizedWebURL(trimmed)
        }
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty else { return trimmed }
        return "https://wa.me/\(digits)"
    }

    private static func normalizedYouTubeURL(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return trimmed
        }
        if lowercased.contains("youtube.com") || lowercased.contains("youtu.be") {
            return normalizedWebURL(trimmed)
        }
        let handle = trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
        return normalizedWebURL("youtube.com/\(handle)")
    }

    private var normalizedFacebookURL: String {
        Self.normalizedPlatformURL(facebookURL, host: "facebook.com")
    }

    private var normalizedInstagramURL: String {
        Self.normalizedPlatformURL(instagramURL, host: "instagram.com")
    }

    private var normalizedWhatsAppURL: String {
        Self.normalizedWhatsAppURL(whatsappURL)
    }

    private var normalizedYouTubeURL: String {
        Self.normalizedYouTubeURL(youtubeURL)
    }

    private var normalizedLinkedInURL: String {
        Self.normalizedPlatformURL(linkedinURL, host: "linkedin.com")
    }

    private func validateOptionalURLs() -> [String] {
        [
            normalizedTelegramURL,
            normalizedDonationURL,
            normalizedFacebookURL,
            normalizedInstagramURL,
            normalizedWhatsAppURL,
            normalizedYouTubeURL,
            normalizedLinkedInURL,
            Self.normalizedWebURL(orderURL),
            Self.normalizedWebURL(bookingURL),
            Self.normalizedWebURL(currentOfferURL)
        ]
            .filter { !$0.isEmpty }
            .compactMap { value in
                OrganizationWebURL.url(from: value) != nil ? nil : AppStrings.Validation.organizationWebsiteInvalid
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
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func organizationTrimmedOrFallback(_ fallback: String) -> String {
        let value = trimmed
        return value.isEmpty ? fallback : value
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var commaSeparatedValues: [String] {
        split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
