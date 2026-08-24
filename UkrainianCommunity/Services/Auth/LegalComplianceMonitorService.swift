import Combine
import Foundation

@MainActor
final class LegalComplianceMonitorService: ObservableObject {
    @Published var activeRequirement: LegalComplianceRequirement?
    @Published var isAccepting = false
    @Published var errorMessage: String?

    private let legalDocumentRepository: LegalDocumentRepository
    private let userRepository: UserRepository
    private var evaluatedKey: String?
    private var acceptingUserID: String?
    private var locallyAcceptedUserID: String?
    private var locallyAcceptedVersions: [LegalDocumentType: String] = [:]
    private var configuredUserID: String?
    private var configurationGeneration: UInt = 0
    private var acceptanceGeneration: UInt = 0

    init(
        legalDocumentRepository: LegalDocumentRepository,
        userRepository: UserRepository
    ) {
        self.legalDocumentRepository = legalDocumentRepository
        self.userRepository = userRepository
    }

    func configure(user: AppUser?) async {
        guard let user else {
            configurationGeneration &+= 1
            configuredUserID = nil
            invalidateAcceptance()
            evaluatedKey = nil
            activeRequirement = nil
            locallyAcceptedUserID = nil
            locallyAcceptedVersions = [:]
            errorMessage = nil
            return
        }

        guard !isAccepting || acceptingUserID != user.id else { return }
        let identityChanged = configuredUserID != user.id
        if identityChanged {
            invalidateAcceptance()
            activeRequirement = nil
            errorMessage = nil
        }
        updateLocalAcceptedVersions(for: user)

        let key = [
            user.id,
            user.acceptedTermsVersion ?? "",
            user.acceptedPrivacyVersion ?? ""
        ].joined(separator: ":")
        guard identityChanged || evaluatedKey != key else { return }

        configurationGeneration &+= 1
        let generation = configurationGeneration
        let userID = user.id
        configuredUserID = userID
        evaluatedKey = key
        errorMessage = nil

        do {
            try Task.checkCancellation()
            async let termsDocument = legalDocumentRepository.fetchActiveDocument(type: .terms)
            async let privacyDocument = legalDocumentRepository.fetchActiveDocument(type: .privacy)
            let documents = try await [termsDocument, privacyDocument]
            try Task.checkCancellation()
            guard isCurrentConfiguration(generation: generation, userID: userID, key: key) else {
                return
            }
            let requiredDocuments = documents.filter { document in
                guard document.requiresAcceptance else { return false }
                if locallyAcceptedUserID == userID,
                   locallyAcceptedVersions[document.type] == document.version {
                    return false
                }

                switch document.type {
                case .terms:
                    return user.acceptedTermsVersion != document.version
                case .privacy:
                    return user.acceptedPrivacyVersion != document.version
                }
            }

            activeRequirement = requiredDocuments.isEmpty ? nil : LegalComplianceRequirement(
                userID: userID,
                requiredDocuments: requiredDocuments
            )
        } catch is CancellationError {
            guard isCurrentConfiguration(generation: generation, userID: userID, key: key) else {
                return
            }
            evaluatedKey = nil
        } catch {
            guard isCurrentConfiguration(generation: generation, userID: userID, key: key) else {
                return
            }
            activeRequirement = nil
            errorMessage = AppStrings.LegalCompliance.loadFailed
        }
    }

    func acceptRequiredDocuments(authState: AuthState) async {
        guard let requirement = activeRequirement,
              !isAccepting,
              configuredUserID == requirement.userID,
              authState.isAuthenticated,
              authState.user?.id == requirement.userID else {
            return
        }

        configurationGeneration &+= 1
        acceptanceGeneration &+= 1
        let generation = acceptanceGeneration
        let userID = requirement.userID
        let requiredDocuments = requirement.requiredDocuments
        var acceptedVersions: [LegalDocumentType: String] = [:]
        isAccepting = true
        acceptingUserID = userID
        errorMessage = nil
        defer {
            clearAcceptanceIfOwned(generation: generation, userID: userID)
        }

        do {
            for document in requiredDocuments {
                guard isCurrentAcceptance(
                    generation: generation,
                    userID: userID,
                    authState: authState
                ) else { return }
                guard !Task.isCancelled else {
                    preservePartialAcceptance(
                        acceptedVersions,
                        requirement: requirement,
                        userID: userID
                    )
                    return
                }

                let receipt = try await legalDocumentRepository.acceptDocument(
                    type: document.type,
                    version: document.version,
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                    locale: AppLanguage.stored.rawValue,
                    acceptedFromPlatform: "ios"
                )

                guard isCurrentAcceptance(
                    generation: generation,
                    userID: userID,
                    authState: authState
                ) else { return }
                acceptedVersions[receipt.documentType] = receipt.version
                guard !Task.isCancelled else {
                    preservePartialAcceptance(
                        acceptedVersions,
                        requirement: requirement,
                        userID: userID
                    )
                    return
                }
            }

            guard isCurrentAcceptance(
                generation: generation,
                userID: userID,
                authState: authState
            ), !Task.isCancelled else { return }

            rememberAcceptedVersions(acceptedVersions, userID: userID)
            activeRequirement = nil
            evaluatedKey = nil
            errorMessage = nil

            guard isCurrentAcceptance(
                generation: generation,
                userID: userID,
                authState: authState
            ), !Task.isCancelled else { return }
            let refreshedUser = try? await userRepository.fetchCurrentUser()
            guard isCurrentAcceptance(
                generation: generation,
                userID: userID,
                authState: authState
            ), !Task.isCancelled else { return }

            if let refreshedUser, refreshedUser.id == userID {
                _ = authState.updateAuthenticatedUser(refreshedUser)
            }

            clearAcceptanceIfOwned(generation: generation, userID: userID)
            guard isCurrentAcceptanceGeneration(
                generation,
                userID: userID,
                authState: authState
            ), !Task.isCancelled else { return }
            let currentUser = authState.user
            await configure(user: currentUser)
            guard isCurrentAcceptanceGeneration(
                generation,
                userID: userID,
                authState: authState
            ), !Task.isCancelled else { return }
        } catch {
            guard isCurrentAcceptance(
                generation: generation,
                userID: userID,
                authState: authState
            ) else { return }

            if Task.isCancelled || error is CancellationError {
                preservePartialAcceptance(
                    acceptedVersions,
                    requirement: requirement,
                    userID: userID
                )
                return
            }

            rememberAcceptedVersions(acceptedVersions, userID: userID)
            evaluatedKey = nil

            guard isCurrentAcceptance(
                generation: generation,
                userID: userID,
                authState: authState
            ) else { return }
            let refreshedUser = try? await userRepository.fetchCurrentUser()
            guard isCurrentAcceptance(
                generation: generation,
                userID: userID,
                authState: authState
            ), !Task.isCancelled else { return }

            if let refreshedUser, refreshedUser.id == userID {
                _ = authState.updateAuthenticatedUser(refreshedUser)
            }

            clearAcceptanceIfOwned(generation: generation, userID: userID)
            guard isCurrentAcceptanceGeneration(
                generation,
                userID: userID,
                authState: authState
            ), !Task.isCancelled else { return }
            let currentUser = authState.user
            await configure(user: currentUser)
            guard isCurrentAcceptanceGeneration(
                generation,
                userID: userID,
                authState: authState
            ), !Task.isCancelled else { return }
            errorMessage = AppStrings.LegalCompliance.acceptFailed
        }
    }

    func declineAndSignOut() async {
        guard await AuthService.shared.signOut() else {
            errorMessage = AppStrings.Profile.signOutFailed
            return
        }
        activeRequirement = nil
        evaluatedKey = nil
        configuredUserID = nil
        configurationGeneration &+= 1
        invalidateAcceptance()
        locallyAcceptedUserID = nil
        locallyAcceptedVersions = [:]
        errorMessage = nil
    }

    private func rememberAcceptedVersions(
        _ acceptedVersions: [LegalDocumentType: String],
        userID: String
    ) {
        guard !acceptedVersions.isEmpty else { return }

        if locallyAcceptedUserID != userID {
            locallyAcceptedUserID = userID
            locallyAcceptedVersions = [:]
        }

        for (type, version) in acceptedVersions {
            locallyAcceptedVersions[type] = version
        }
    }

    private func updateLocalAcceptedVersions(for user: AppUser) {
        guard locallyAcceptedUserID == user.id else {
            locallyAcceptedUserID = nil
            locallyAcceptedVersions = [:]
            return
        }

        if locallyAcceptedVersions[.terms] == user.acceptedTermsVersion {
            locallyAcceptedVersions[.terms] = nil
        }

        if locallyAcceptedVersions[.privacy] == user.acceptedPrivacyVersion {
            locallyAcceptedVersions[.privacy] = nil
        }

        if locallyAcceptedVersions.isEmpty {
            locallyAcceptedUserID = nil
        }
    }

    private func invalidateAcceptance() {
        acceptanceGeneration &+= 1
        isAccepting = false
        acceptingUserID = nil
    }

    private func clearAcceptanceIfOwned(generation: UInt, userID: String) {
        guard acceptanceGeneration == generation,
              acceptingUserID == userID else { return }
        isAccepting = false
        acceptingUserID = nil
    }

    private func isCurrentConfiguration(generation: UInt, userID: String, key: String) -> Bool {
        configurationGeneration == generation
            && configuredUserID == userID
            && evaluatedKey == key
    }

    private func isCurrentAcceptance(
        generation: UInt,
        userID: String,
        authState: AuthState
    ) -> Bool {
        acceptanceGeneration == generation
            && acceptingUserID == userID
            && isAccepting
            && configuredUserID == userID
            && authState.isAuthenticated
            && authState.user?.id == userID
    }

    private func isCurrentAcceptanceGeneration(
        _ generation: UInt,
        userID: String,
        authState: AuthState
    ) -> Bool {
        acceptanceGeneration == generation
            && configuredUserID == userID
            && authState.isAuthenticated
            && authState.user?.id == userID
    }

    private func preservePartialAcceptance(
        _ acceptedVersions: [LegalDocumentType: String],
        requirement: LegalComplianceRequirement,
        userID: String
    ) {
        rememberAcceptedVersions(acceptedVersions, userID: userID)
        evaluatedKey = nil

        let remainingDocuments = requirement.requiredDocuments.filter { document in
            acceptedVersions[document.type] != document.version
        }
        activeRequirement = remainingDocuments.isEmpty ? nil : LegalComplianceRequirement(
            userID: userID,
            requiredDocuments: remainingDocuments
        )
    }
}

struct LegalComplianceRequirement: Identifiable, Equatable {
    let userID: String
    let requiredDocuments: [LegalDocument]

    var id: String {
        ([userID] + requiredDocuments.map { "\($0.type.rawValue):\($0.version)" })
            .joined(separator: "|")
    }

    var requiresTerms: Bool {
        requiredDocuments.contains { $0.type == .terms }
    }

    var requiresPrivacy: Bool {
        requiredDocuments.contains { $0.type == .privacy }
    }

    func document(type: LegalDocumentType) -> LegalDocument? {
        requiredDocuments.first { $0.type == type }
    }
}
