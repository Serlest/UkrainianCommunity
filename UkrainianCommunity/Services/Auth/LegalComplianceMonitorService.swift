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
            errorMessage = nil
            return
        }

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
        guard let requirement = activeRequirement else { return }
        isAccepting = true
        errorMessage = nil
        defer { isAccepting = false }

        do {
            for document in requirement.requiredDocuments {
                _ = try await legalDocumentRepository.acceptDocument(
                    type: document.type,
                    version: document.version,
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                    locale: AppLanguage.stored.rawValue,
                    acceptedFromPlatform: "ios"
                )
            }

            let refreshedUser = try await userRepository.fetchCurrentUser()
            authState.user = refreshedUser
            activeRequirement = nil
            evaluatedKey = nil
            await configure(user: refreshedUser)
        } catch {
            errorMessage = AppStrings.LegalCompliance.acceptFailed
        }
    }

    func declineAndSignOut() {
        _ = AuthService.shared.signOut()
        activeRequirement = nil
        evaluatedKey = nil
        errorMessage = nil
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
