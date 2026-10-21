import FirebaseAuth
import FirebaseFirestore
import Foundation
import Testing
@testable import UkrainianCommunity

@Suite("Firebase read error mapper")
struct FirebaseReadErrorMapperTests {
    @Test
    func authenticationAndPermissionErrorsMapToPermissionDenied() {
        let codes = [
            FirestoreErrorCode.unauthenticated.rawValue,
            FirestoreErrorCode.permissionDenied.rawValue
        ]

        for code in codes {
            #expect(FirebaseReadErrorMapper.map(firestoreError(code)) == .permissionDenied)
        }
    }

    @Test
    func temporaryFirestoreErrorsMapToNetwork() {
        let codes = [
            FirestoreErrorCode.cancelled.rawValue,
            FirestoreErrorCode.deadlineExceeded.rawValue,
            FirestoreErrorCode.resourceExhausted.rawValue,
            FirestoreErrorCode.aborted.rawValue,
            FirestoreErrorCode.unavailable.rawValue
        ]

        for code in codes {
            #expect(FirebaseReadErrorMapper.map(firestoreError(code)) == .network)
        }
    }

    @Test
    func notFoundAndInvalidDataRemainDistinct() {
        #expect(FirebaseReadErrorMapper.map(firestoreError(FirestoreErrorCode.notFound.rawValue)) == .notFound)
        #expect(FirebaseReadErrorMapper.map(firestoreError(FirestoreErrorCode.invalidArgument.rawValue)) == .validationFailed)
        #expect(FirebaseReadErrorMapper.map(firestoreError(FirestoreErrorCode.dataLoss.rawValue)) == .validationFailed)
    }

    @Test
    func existingAppErrorIsPreserved() {
        #expect(FirebaseReadErrorMapper.map(AppError.permissionDenied) == .permissionDenied)
    }

    @Test
    func authConnectivityIsDistinctFromDisabledAccounts() {
        #expect(FirebaseReadErrorMapper.map(NSError(domain: AuthErrorDomain,
            code: AuthErrorCode.networkError.rawValue)) == .network)
        #expect(FirebaseReadErrorMapper.map(NSError(domain: AuthErrorDomain,
            code: AuthErrorCode.userDisabled.rawValue)) != .network)
        #expect(FirebaseReadErrorMapper.map(URLError(.notConnectedToInternet)) == .network)
        #expect(FirebaseReadErrorMapper.map(URLError(.timedOut)) == .network)
    }

    private func firestoreError(_ code: Int) -> NSError {
        NSError(domain: FirestoreErrorDomain, code: code)
    }
}
