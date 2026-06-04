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

    func configure(userID: String?, authState: AuthState) {
        guard observedUserID != userID else { return }

        listener?.remove()
        listener = nil
        observedUserID = userID
        activeNotice = nil
        acknowledgementError = nil
        presentedNoticeID = nil

        guard let userID else { return }

        listener = db.collection("users").document(userID).addSnapshotListener { [weak self, weak authState] snapshot, _ in
            Task { @MainActor in
                self?.handle(snapshot: snapshot, authState: authState)
            }
        }
    }

    func acknowledgeActiveNotice() async {
        guard let notice = activeNotice else { return }
        isAcknowledging = true
        acknowledgementError = nil
        defer { isAcknowledging = false }

        do {
            try await db.collection("users").document(notice.userID).updateData([
                "statusAcknowledgedAt": FieldValue.serverTimestamp()
            ])
            activeNotice = nil
        } catch {
            acknowledgementError = AppStrings.AccountStatusAlert.acknowledgementFailed
        }
    }

    deinit {
        listener?.remove()
    }

    private func handle(snapshot: DocumentSnapshot?, authState: AuthState?) {
        guard
            let snapshot,
            snapshot.exists,
            let user = makeUser(from: snapshot)
        else {
            return
        }

        authState?.user = user

        guard let notice = AccountStatusNotice(user: user) else {
            activeNotice = nil
            presentedNoticeID = nil
            return
        }

        guard notice.id != presentedNoticeID else { return }
        presentedNoticeID = notice.id
        acknowledgementError = nil
        activeNotice = notice
    }

    private func makeUser(from document: DocumentSnapshot) -> AppUser? {
        guard let data = document.data() else { return nil }
        let legacyRole = UserRole(rawValue: data["role"] as? String ?? "") ?? .user
        let globalRole = (data["globalRole"] as? String).flatMap(GlobalRole.init(rawValue:)) ?? .user
        let isBlocked = data["isBlocked"] as? Bool ?? false
        let blockState = UserBlockState(rawValue: data["blockState"] as? String ?? "") ?? (isBlocked ? .suspendedUntil : .active)

        return AppUser(
            id: data["id"] as? String ?? document.documentID,
            fullName: data["fullName"] as? String ?? "",
            displayName: data["displayName"] as? String ?? data["fullName"] as? String ?? "",
            city: data["city"] as? String ?? "",
            email: data["email"] as? String ?? "",
            avatarURL: (data["avatarURL"] as? String).flatMap(URL.init(string:)),
            bio: data["bio"] as? String ?? "",
            telegramUsername: data["telegramUsername"] as? String,
            role: legacyRole,
            globalRole: globalRole,
            moderatorSections: (data["moderatorSections"] as? [String] ?? []).compactMap(AppSection.init(rawValue:)),
            canManageGuide: data["canManageGuide"] as? Bool ?? false,
            blockState: blockState,
            accountStatus: (data["accountStatus"] as? String).flatMap(AccountStatus.init(rawValue:)) ?? (blockState.isRestricted ? .suspendedUntil : .active),
            banExpiresAt: (data["banExpiresAt"] as? Timestamp)?.dateValue(),
            warningCount: data["warningCount"] as? Int ?? 0,
            statusReason: data["statusReason"] as? String,
            statusMessage: data["statusMessage"] as? String,
            statusUpdatedAt: (data["statusUpdatedAt"] as? Timestamp)?.dateValue(),
            statusUpdatedBy: data["statusUpdatedBy"] as? String,
            statusAcknowledgedAt: (data["statusAcknowledgedAt"] as? Timestamp)?.dateValue(),
            communityMemberships: [],
            selectedFederalState: (data["selectedFederalState"] as? String).flatMap(AustrianFederalState.init(rawValue:)),
            acceptedTermsAt: (data["acceptedTermsAt"] as? Timestamp)?.dateValue(),
            acceptedPrivacyAt: (data["acceptedPrivacyAt"] as? Timestamp)?.dateValue(),
            termsVersion: data["termsVersion"] as? String,
            privacyVersion: data["privacyVersion"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast,
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
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
