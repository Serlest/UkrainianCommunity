import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
@Suite("Legal compliance account races")
struct LegalComplianceMonitorRaceTests {
    @Test
    func staleConfigurationCannotOverwriteNewAccountRequirement() async {
        let terms = makeDocument(type: .terms)
        let privacy = makeDocument(type: .privacy)
        let legalRepository = ControlledLegalDocumentRepository(
            documents: [terms, privacy],
            suspendsFetches: true
        )
        let service = LegalComplianceMonitorService(
            legalDocumentRepository: legalRepository,
            userRepository: ControlledLegalUserRepository(currentUser: makeUser(id: "user-b"))
        )
        let oldUser = makeUser(id: "user-a")
        let newUser = makeUser(id: "user-b", acceptedTermsVersion: terms.version)

        let oldConfiguration = Task { await service.configure(user: oldUser) }
        #expect(await eventually {
            legalRepository.fetchRequestCount(for: .terms) == 1
                && legalRepository.fetchRequestCount(for: .privacy) == 1
        })

        let newConfiguration = Task { await service.configure(user: newUser) }
        #expect(await eventually {
            legalRepository.fetchRequestCount(for: .terms) == 2
                && legalRepository.fetchRequestCount(for: .privacy) == 2
        })

        legalRepository.completeFetch(type: .terms, requestNumber: 2)
        legalRepository.completeFetch(type: .privacy, requestNumber: 2)
        await newConfiguration.value

        #expect(service.activeRequirement?.userID == newUser.id)
        #expect(service.activeRequirement?.requiredDocuments.map(\.type) == [.privacy])

        legalRepository.completeFetch(type: .terms, requestNumber: 1)
        legalRepository.completeFetch(type: .privacy, requestNumber: 1)
        await oldConfiguration.value

        #expect(service.activeRequirement?.userID == newUser.id)
        #expect(service.activeRequirement?.requiredDocuments.map(\.type) == [.privacy])
        #expect(service.errorMessage == nil)
    }

    @Test
    func cancelledOldAcceptanceCannotStartNextDocumentOrMutateNewAccount() async {
        let terms = makeDocument(type: .terms)
        let privacy = makeDocument(type: .privacy)
        let legalRepository = ControlledLegalDocumentRepository(documents: [terms, privacy])
        let service = LegalComplianceMonitorService(
            legalDocumentRepository: legalRepository,
            userRepository: ControlledLegalUserRepository(currentUser: makeUser(id: "user-a"))
        )
        let oldUser = makeUser(id: "user-a")
        let newUser = makeUser(id: "user-b", acceptedTermsVersion: terms.version)
        let authState = AuthState()
        authState.setAuthenticatedSession(user: oldUser)
        await service.configure(user: oldUser)

        let acceptance = Task { await service.acceptRequiredDocuments(authState: authState) }
        #expect(await eventually { legalRepository.acceptRequestCount == 1 })
        #expect(legalRepository.acceptedDocumentTypes == [.terms])

        acceptance.cancel()
        authState.setAuthenticatedSession(user: newUser)
        await service.configure(user: newUser)
        legalRepository.completeAcceptance(requestNumber: 1)
        await acceptance.value

        #expect(legalRepository.acceptRequestCount == 1)
        #expect(authState.user?.id == newUser.id)
        #expect(service.activeRequirement?.userID == newUser.id)
        #expect(service.activeRequirement?.requiredDocuments.map(\.type) == [.privacy])
        #expect(service.isAccepting == false)
        #expect(service.errorMessage == nil)
    }

    @Test
    func staleProfileRefreshAfterAcceptanceCannotReplaceNewAccount() async {
        let terms = makeDocument(type: .terms)
        let privacy = makeDocument(type: .privacy)
        let legalRepository = ControlledLegalDocumentRepository(documents: [terms, privacy])
        let oldUser = makeUser(id: "user-a", acceptedPrivacyVersion: privacy.version)
        let refreshedOldUser = makeUser(
            id: oldUser.id,
            acceptedTermsVersion: terms.version,
            acceptedPrivacyVersion: privacy.version
        )
        let userRepository = ControlledLegalUserRepository(
            currentUser: refreshedOldUser,
            suspendsFetches: true
        )
        let service = LegalComplianceMonitorService(
            legalDocumentRepository: legalRepository,
            userRepository: userRepository
        )
        let newUser = makeUser(id: "user-b", acceptedTermsVersion: terms.version)
        let authState = AuthState()
        authState.setAuthenticatedSession(user: oldUser)
        await service.configure(user: oldUser)

        let acceptance = Task { await service.acceptRequiredDocuments(authState: authState) }
        #expect(await eventually { legalRepository.acceptRequestCount == 1 })
        legalRepository.completeAcceptance(requestNumber: 1)
        #expect(await eventually { userRepository.fetchRequestCount == 1 })

        authState.setAuthenticatedSession(user: newUser)
        await service.configure(user: newUser)
        userRepository.completeFetch(requestNumber: 1, user: refreshedOldUser)
        await acceptance.value

        #expect(authState.user?.id == newUser.id)
        #expect(service.activeRequirement?.userID == newUser.id)
        #expect(service.activeRequirement?.requiredDocuments.map(\.type) == [.privacy])
        #expect(service.isAccepting == false)
        #expect(service.errorMessage == nil)
    }

    @Test
    func partialAcceptanceIsRememberedForCurrentAccount() async {
        let terms = makeDocument(type: .terms)
        let privacy = makeDocument(type: .privacy)
        let user = makeUser(id: "user-a")
        let legalRepository = ControlledLegalDocumentRepository(documents: [terms, privacy])
        let service = LegalComplianceMonitorService(
            legalDocumentRepository: legalRepository,
            userRepository: ControlledLegalUserRepository(currentUser: user)
        )
        let authState = AuthState()
        authState.setAuthenticatedSession(user: user)
        await service.configure(user: user)

        let acceptance = Task { await service.acceptRequiredDocuments(authState: authState) }
        #expect(await eventually { legalRepository.acceptRequestCount == 1 })
        legalRepository.completeAcceptance(requestNumber: 1)
        #expect(await eventually { legalRepository.acceptRequestCount == 2 })
        legalRepository.completeAcceptance(requestNumber: 2, error: .network)
        await acceptance.value

        #expect(legalRepository.acceptedDocumentTypes == [.terms, .privacy])
        #expect(service.activeRequirement?.userID == user.id)
        #expect(service.activeRequirement?.requiredDocuments.map(\.type) == [.privacy])
        #expect(service.isAccepting == false)
        #expect(service.errorMessage == AppStrings.LegalCompliance.acceptFailed)
    }

    private func makeDocument(type: LegalDocumentType, version: String = "2026.1") -> LegalDocument {
        LegalDocument(
            id: type.rawValue,
            type: type,
            version: version,
            versionNumber: 1,
            locales: [:],
            defaultLocale: AppLanguage.german.rawValue,
            canonicalLocale: AppLanguage.german.rawValue,
            contentHash: nil,
            changeSummary: nil,
            requiresAcceptance: true,
            status: .published,
            updatedAt: nil,
            updatedBy: nil,
            publishedAt: nil,
            publishedBy: nil
        )
    }

    private func makeUser(
        id: String,
        acceptedTermsVersion: String? = nil,
        acceptedPrivacyVersion: String? = nil
    ) -> AppUser {
        AppUser(
            id: id,
            fullName: "Test User",
            displayName: "Test User",
            city: "Vienna",
            email: "\(id)@example.com",
            bio: "",
            role: .user,
            blockState: .active,
            acceptedTermsVersion: acceptedTermsVersion,
            acceptedPrivacyVersion: acceptedPrivacyVersion,
            createdAt: .now,
            updatedAt: .now
        )
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }
}

private enum LegalComplianceTestError: Error {
    case expected
}

@MainActor
private final class ControlledLegalDocumentRepository: LegalDocumentRepository {
    private let documentsByType: [LegalDocumentType: LegalDocument]
    private let suspendsFetches: Bool
    private var fetchCounts: [LegalDocumentType: Int] = [:]
    private var fetchContinuations: [String: CheckedContinuation<LegalDocument, Error>] = [:]
    private var acceptanceContinuations: [Int: CheckedContinuation<LegalAcceptanceReceipt, Error>] = [:]
    private var acceptanceRequests: [(type: LegalDocumentType, version: String)] = []

    init(documents: [LegalDocument], suspendsFetches: Bool = false) {
        documentsByType = Dictionary(uniqueKeysWithValues: documents.map { ($0.type, $0) })
        self.suspendsFetches = suspendsFetches
    }

    var acceptRequestCount: Int {
        acceptanceRequests.count
    }

    var acceptedDocumentTypes: [LegalDocumentType] {
        acceptanceRequests.map(\.type)
    }

    func fetchRequestCount(for type: LegalDocumentType) -> Int {
        fetchCounts[type, default: 0]
    }

    func fetchActiveDocument(type: LegalDocumentType) async throws -> LegalDocument {
        guard let document = documentsByType[type] else {
            throw AppError.notFound
        }
        guard suspendsFetches else { return document }

        fetchCounts[type, default: 0] += 1
        let requestNumber = fetchCounts[type, default: 0]
        return try await withCheckedThrowingContinuation { continuation in
            fetchContinuations[fetchKey(type: type, requestNumber: requestNumber)] = continuation
        }
    }

    func acceptDocument(
        type: LegalDocumentType,
        version: String,
        appVersion: String?,
        locale: String?,
        acceptedFromPlatform: String
    ) async throws -> LegalAcceptanceReceipt {
        acceptanceRequests.append((type, version))
        let requestNumber = acceptanceRequests.count
        return try await withCheckedThrowingContinuation { continuation in
            acceptanceContinuations[requestNumber] = continuation
        }
    }

    func completeFetch(
        type: LegalDocumentType,
        requestNumber: Int,
        error: AppError? = nil
    ) {
        let key = fetchKey(type: type, requestNumber: requestNumber)
        guard let continuation = fetchContinuations.removeValue(forKey: key),
              let document = documentsByType[type] else {
            Issue.record("Missing legal document fetch continuation \(key)")
            return
        }

        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: document)
        }
    }

    func completeAcceptance(requestNumber: Int, error: AppError? = nil) {
        guard let continuation = acceptanceContinuations.removeValue(forKey: requestNumber),
              acceptanceRequests.indices.contains(requestNumber - 1) else {
            Issue.record("Missing legal acceptance continuation \(requestNumber)")
            return
        }
        let request = acceptanceRequests[requestNumber - 1]

        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: LegalAcceptanceReceipt(
                documentType: request.type,
                version: request.version,
                acceptedAt: .now
            ))
        }
    }

    func fetchManagementState(type: LegalDocumentType) async throws -> LegalDocumentManagementState {
        guard let activeDocument = documentsByType[type] else { throw AppError.notFound }
        return LegalDocumentManagementState(type: type, activeDocument: activeDocument, draftDocument: nil)
    }

    func saveDraft(_ draft: LegalDocumentDraft, updatedBy userID: String) async throws {
        throw LegalComplianceTestError.expected
    }

    func publishDraft(_ draft: LegalDocumentDraft, publishedBy userID: String) async throws {
        throw LegalComplianceTestError.expected
    }

    private func fetchKey(type: LegalDocumentType, requestNumber: Int) -> String {
        "\(type.rawValue):\(requestNumber)"
    }
}

@MainActor
private final class ControlledLegalUserRepository: UserRepository {
    private let currentUser: AppUser
    private let suspendsFetches: Bool
    private var fetchContinuations: [Int: CheckedContinuation<AppUser, Error>] = [:]
    private(set) var fetchRequestCount = 0

    init(currentUser: AppUser, suspendsFetches: Bool = false) {
        self.currentUser = currentUser
        self.suspendsFetches = suspendsFetches
    }

    func fetchCurrentUser() async throws -> AppUser {
        guard suspendsFetches else { return currentUser }
        fetchRequestCount += 1
        let requestNumber = fetchRequestCount
        return try await withCheckedThrowingContinuation { continuation in
            fetchContinuations[requestNumber] = continuation
        }
    }

    func completeFetch(requestNumber: Int, user: AppUser, error: AppError? = nil) {
        guard let continuation = fetchContinuations.removeValue(forKey: requestNumber) else {
            Issue.record("Missing legal user fetch continuation \(requestNumber)")
            return
        }

        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: user)
        }
    }

    func fetchSettings() async throws -> UserSettings {
        fatalError("Unused in legal compliance race tests")
    }

    func updateProfile(_ profile: EditableUserProfileDraft) async throws -> AppUser {
        currentUser
    }

    func deleteAccount(currentUser: AppUser) async throws {}
}
