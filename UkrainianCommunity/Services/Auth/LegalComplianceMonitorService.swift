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

    init(
        legalDocumentRepository: LegalDocumentRepository,
        userRepository: UserRepository
    ) {
        self.legalDocumentRepository = legalDocumentRepository
        self.userRepository = userRepository
    }

    func configure(user: AppUser?) async {
        guard let user else {
            evaluatedKey = nil
            activeRequirement = nil
            acceptingUserID = nil
            locallyAcceptedUserID = nil
            locallyAcceptedVersions = [:]
            errorMessage = nil
            return
        }

        guard !isAccepting || acceptingUserID != user.id else { return }
        if isAccepting {
            isAccepting = false
            acceptingUserID = nil
        }
        updateLocalAcceptedVersions(for: user)

        let key = [
            user.id,
            user.acceptedTermsVersion ?? "",
            user.acceptedPrivacyVersion ?? ""
        ].joined(separator: ":")
        guard evaluatedKey != key else { return }
        evaluatedKey = key
        errorMessage = nil

        do {
            async let termsDocument = legalDocumentRepository.fetchActiveDocument(type: .terms)
            async let privacyDocument = legalDocumentRepository.fetchActiveDocument(type: .privacy)
            let documents = try await [termsDocument, privacyDocument]
            let requiredDocuments = documents.filter { document in
                guard document.requiresAcceptance else { return false }
                if locallyAcceptedUserID == user.id,
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
                userID: user.id,
                requiredDocuments: requiredDocuments
            )
        } catch {
            activeRequirement = nil
            errorMessage = AppStrings.LegalCompliance.loadFailed
        }
    }

    func acceptRequiredDocuments(authState: AuthState) async {
        guard let requirement = activeRequirement, !isAccepting else { return }
        let requiredDocuments = requirement.requiredDocuments
        var acceptedVersions: [LegalDocumentType: String] = [:]
        isAccepting = true
        acceptingUserID = requirement.userID
        errorMessage = nil

        do {
            for document in requiredDocuments {
                let receipt = try await legalDocumentRepository.acceptDocument(
                    type: document.type,
                    version: document.version,
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                    locale: AppLanguage.stored.rawValue,
                    acceptedFromPlatform: "ios"
                )
                acceptedVersions[receipt.documentType] = receipt.version
            }

            if acceptingUserID == requirement.userID {
                rememberAcceptedVersions(acceptedVersions, userID: requirement.userID)
                activeRequirement = nil
                evaluatedKey = nil
                errorMessage = nil
                if let refreshedUser = try? await userRepository.fetchCurrentUser() {
                    authState.user = refreshedUser
                }
            }
            isAccepting = false
            acceptingUserID = nil
            await configure(user: authState.user)
        } catch {
            rememberAcceptedVersions(acceptedVersions, userID: requirement.userID)
            isAccepting = false
            acceptingUserID = nil
            evaluatedKey = nil

            if let refreshedUser = try? await userRepository.fetchCurrentUser() {
                authState.user = refreshedUser
                await configure(user: refreshedUser)
            } else if let currentUser = authState.user {
                await configure(user: currentUser)
            }

            errorMessage = AppStrings.LegalCompliance.acceptFailed
        }
    }

    func declineAndSignOut() {
        _ = AuthService.shared.signOut()
        activeRequirement = nil
        evaluatedKey = nil
        acceptingUserID = nil
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
