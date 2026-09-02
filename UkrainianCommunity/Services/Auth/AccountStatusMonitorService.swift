import Combine
import FirebaseFirestore
import Foundation

@MainActor
final class AccountStatusMonitorService: ObservableObject {
    @Published var activeNotice: AccountStatusNotice?
    @Published var isAcknowledging = false
    @Published var acknowledgementError: String?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var observedUserID: String?
    private var presentedNoticeID: String?
    private var acknowledgementGeneration = 0

    func configure(userID: String?, authState: AuthState) {
        guard observedUserID != userID else { return }

        listener?.remove()
        listener = nil
        invalidateAcknowledgement()
        observedUserID = userID
        activeNotice = nil
        acknowledgementError = nil
        presentedNoticeID = nil

        guard let userID else { return }

        listener = db.collection("users").document(userID).addSnapshotListener { [weak self, weak authState] snapshot, error in
            if let error {
                Self.logListenerFailure(error, userID: userID)
                return
            }

            Task { @MainActor in
                self?.handle(snapshot: snapshot, expectedUserID: userID, authState: authState)
            }
        }
    }

    func acknowledgeActiveNotice() async {
        guard let notice = activeNotice,
              observedUserID == notice.userID else { return }

        acknowledgementGeneration &+= 1
        let generation = acknowledgementGeneration
        isAcknowledging = true
        acknowledgementError = nil
        defer {
            if acknowledgementGeneration == generation {
                isAcknowledging = false
            }
        }

        do {
            try await db.collection("users").document(notice.userID).updateData([
                "statusAcknowledgedAt": FieldValue.serverTimestamp()
            ])
            guard isCurrentAcknowledgement(generation: generation, notice: notice) else { return }
            activeNotice = nil
        } catch {
            guard isCurrentAcknowledgement(generation: generation, notice: notice) else { return }
            acknowledgementError = AppStrings.AccountStatusAlert.acknowledgementFailed
        }
    }

    func completeActiveNotice() async {
        guard let notice = activeNotice else { return }
        guard notice.requiresSignOut else {
            await acknowledgeActiveNotice()
            return
        }

        isAcknowledging = true
        acknowledgementError = nil
        let didSignOut = await AuthService.shared.completeRestrictedAccountSignOut()
        isAcknowledging = false
        if didSignOut {
            activeNotice = nil
        } else {
            acknowledgementError = AppStrings.AccountStatusAlert.restrictedSignOutFailed
        }
    }

    deinit {
        listener?.remove()
    }

    private func handle(
        snapshot: DocumentSnapshot?,
        expectedUserID: String,
        authState: AuthState?
    ) {
        guard
            observedUserID == expectedUserID,
            let snapshot,
            snapshot.exists,
            let authState,
            let currentUser = authState.user,
            currentUser.id == expectedUserID,
            let user = makeUser(from: snapshot, preserving: currentUser)
        else {
            return
        }

        guard authState.updateAuthenticatedUser(user) else { return }

        guard let notice = AccountStatusNotice(user: user) else {
            if activeNotice != nil || isAcknowledging {
                invalidateAcknowledgement()
            }
            activeNotice = nil
            presentedNoticeID = nil
            return
        }

        guard notice.id != presentedNoticeID else { return }
        invalidateAcknowledgement()
        presentedNoticeID = notice.id
        acknowledgementError = nil
        activeNotice = notice
    }

    private static func logListenerFailure(_ error: Error, userID: String) {
        Task {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "AccountStatus",
                    operationName: "listenAccountStatus",
                    targetType: .userProfile,
                    targetId: userID,
                    metadata: [
                        "listenerName": "accountStatus",
                        "pathGroup": "users/{userID}"
                    ]
                )
            )
        }
    }

    private func makeUser(from document: DocumentSnapshot, preserving currentUser: AppUser) -> AppUser? {
        guard let data = document.data() else { return nil }
        let snapshotUserID = data["id"] as? String ?? document.documentID
        guard snapshotUserID == currentUser.id,
              document.documentID == currentUser.id else { return nil }

        let legacyBlockState = (data["isBlocked"] as? Bool).map {
            $0 ? UserBlockState.suspendedUntil : .active
        }
        let blockState = (data["blockState"] as? String).flatMap(UserBlockState.init(rawValue:))
            ?? legacyBlockState
            ?? currentUser.blockState
        let update = AccountStatusSnapshotUpdate(
            requiresMultiFactorAuth: data["requiresMultiFactorAuth"] as? Bool ?? false,
            blockState: blockState,
            accountStatus: (data["accountStatus"] as? String).flatMap(AccountStatus.init(rawValue:))
                ?? (blockState.isRestricted ? .suspendedUntil : .active),
            banExpiresAt: (data["banExpiresAt"] as? Timestamp)?.dateValue(),
            warningCount: data["warningCount"] as? Int ?? 0,
            statusReason: data["statusReason"] as? String,
            statusMessage: data["statusMessage"] as? String,
            statusUpdatedAt: (data["statusUpdatedAt"] as? Timestamp)?.dateValue(),
            statusUpdatedBy: data["statusUpdatedBy"] as? String,
            statusAcknowledgedAt: (data["statusAcknowledgedAt"] as? Timestamp)?.dateValue()
        )
        return update.applying(to: currentUser)
    }

    private func isCurrentAcknowledgement(
        generation: Int,
        notice: AccountStatusNotice
    ) -> Bool {
        acknowledgementGeneration == generation
            && observedUserID == notice.userID
            && activeNotice?.id == notice.id
    }

    private func invalidateAcknowledgement() {
        acknowledgementGeneration &+= 1
        isAcknowledging = false
    }
}

struct AccountStatusSnapshotUpdate {
    let requiresMultiFactorAuth: Bool
    let blockState: UserBlockState
    let accountStatus: AccountStatus
    let banExpiresAt: Date?
    let warningCount: Int
    let statusReason: String?
    let statusMessage: String?
    let statusUpdatedAt: Date?
    let statusUpdatedBy: String?
    let statusAcknowledgedAt: Date?

    func applying(to user: AppUser) -> AppUser {
        AppUser(
            id: user.id,
            fullName: user.fullName,
            displayName: user.displayName,
            city: user.city,
            email: user.email,
            avatarURL: user.avatarURL,
            bio: user.bio,
            telegramUsername: user.telegramUsername,
            role: user.role,
            globalRole: user.globalRole,
            requiresMultiFactorAuth: requiresMultiFactorAuth,
            moderatorSections: user.moderatorSections,
            blockState: blockState,
            accountStatus: accountStatus,
            banExpiresAt: banExpiresAt,
            warningCount: warningCount,
            statusReason: statusReason,
            statusMessage: statusMessage,
            statusUpdatedAt: statusUpdatedAt,
            statusUpdatedBy: statusUpdatedBy,
            statusAcknowledgedAt: statusAcknowledgedAt,
            communityMemberships: user.communityMemberships,
            selectedFederalState: user.selectedFederalState,
            acceptedTermsAt: user.acceptedTermsAt,
            acceptedPrivacyAt: user.acceptedPrivacyAt,
            acceptedTermsVersion: user.acceptedTermsVersion,
            acceptedPrivacyVersion: user.acceptedPrivacyVersion,
            termsVersion: user.termsVersion,
            privacyVersion: user.privacyVersion,
            createdAt: user.createdAt,
            updatedAt: user.updatedAt
        )
    }
}

struct AccountStatusNotice: Identifiable, Equatable {
    enum Kind: Equatable {
        case warned
        case suspended
        case banned
        case deactivated
        case restored
    }

    let id: String
    let userID: String
    let kind: Kind
    let reason: String?
    let message: String?
    let banExpiresAt: Date?
    let statusUpdatedAt: Date

    var requiresSignOut: Bool {
        switch kind {
        case .suspended, .banned, .deactivated:
            true
        case .warned, .restored:
            false
        }
    }

    init?(user: AppUser) {
        guard let statusUpdatedAt = user.statusUpdatedAt else { return nil }
        if let acknowledgedAt = user.statusAcknowledgedAt, acknowledgedAt >= statusUpdatedAt {
            return nil
        }

        let kind: Kind
        switch user.accountStatus {
        case .warned:
            kind = .warned
        case .suspendedUntil, .temporarilyBanned:
            kind = .suspended
        case .bannedPermanent, .permanentlyBanned:
            kind = .banned
        case .deactivated:
            kind = .deactivated
        case .active:
            guard user.blockState == .active else { return nil }
            kind = .restored
        }

        self.id = [
            user.id,
            user.accountStatus.rawValue,
            user.blockState.rawValue,
            String(statusUpdatedAt.timeIntervalSince1970)
        ].joined(separator: ":")
        self.userID = user.id
        self.kind = kind
        self.reason = user.statusReason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.message = user.statusMessage?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.banExpiresAt = user.banExpiresAt
        self.statusUpdatedAt = statusUpdatedAt
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
