import SwiftUI

struct SystemLogActorSection: View {
    let log: SystemLogEntry

    private let resolver: any SystemLogActorIdentityResolving
    @State private var lookupState: LookupState = .idle
    @State private var attemptedUserID: String?

    @MainActor
    init(
        log: SystemLogEntry,
        resolver: (any SystemLogActorIdentityResolving)? = nil
    ) {
        self.log = log
        self.resolver = resolver ?? LiveSystemLogActorIdentityResolver()
    }

    var body: some View {
        DetailCard {
            Text(AppStrings.SystemLogs.actorSection)
                .font(AppTheme.sectionTitleFont)
                .foregroundStyle(AppTheme.textPrimary)

            VStack(spacing: 10) {
                ActorDetailRow(
                    title: Strings.recordedName,
                    value: nonEmpty(log.actorDisplayName) ?? AppStrings.SystemLogs.notRecorded
                )

                ActorDetailRow(
                    title: AppStrings.SystemLogs.roleLabel,
                    value: SystemLogDisplayFormatting.actorRoleTitle(log.actorRole)
                )

                if let actorUserID {
                    ActorDetailRow(title: AppStrings.SystemLogs.userIdLabel, value: actorUserID)
                    resolvedProfileRows
                } else {
                    ActorDetailRow(
                        title: AppStrings.SystemLogs.userIdLabel,
                        value: AppStrings.SystemLogs.notRecorded
                    )
                }
            }
        }
        .task(id: actorUserID) {
            await resolveCurrentProfileOnce()
        }
    }

    @ViewBuilder
    private var resolvedProfileRows: some View {
        switch lookupState {
        case .idle, .loading:
            ActorDetailRow(title: Strings.currentProfile, value: Strings.loading)
        case let .resolved(identity):
            if let displayName = identity.displayName {
                ActorDetailRow(title: Strings.currentProfile, value: displayName)
            }
            if let email = identity.email {
                ActorDetailRow(title: Strings.email, value: email)
            }
            if identity.displayName == nil, identity.email == nil {
                ActorDetailRow(title: Strings.currentProfile, value: Strings.noDisplayData)
            }
        case .notFound:
            ActorDetailRow(title: Strings.currentProfile, value: Strings.notFound)
        case .unavailable:
            ActorDetailRow(title: Strings.currentProfile, value: Strings.unavailable)
        }
    }

    @MainActor
    private func resolveCurrentProfileOnce() async {
        guard let actorUserID, attemptedUserID != actorUserID else { return }
        attemptedUserID = actorUserID
        lookupState = .loading

        do {
            let identity = try await resolver.resolve(userID: actorUserID)
            guard !Task.isCancelled else {
                resetCancelledAttempt(for: actorUserID)
                return
            }
            guard actorUserID == self.actorUserID else { return }
            lookupState = identity.map(LookupState.resolved) ?? .notFound
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else {
                resetCancelledAttempt(for: actorUserID)
                return
            }
            guard actorUserID == self.actorUserID else { return }
            lookupState = .unavailable
        }
    }

    @MainActor
    private func resetCancelledAttempt(for userID: String) {
        guard attemptedUserID == userID else { return }
        attemptedUserID = nil
        lookupState = .idle
    }

    private var actorUserID: String? {
        nonEmpty(log.actorUserId)
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private extension SystemLogActorSection {
    enum LookupState {
        case idle
        case loading
        case resolved(SystemLogActorIdentity)
        case notFound
        case unavailable
    }

    enum Strings {
        static var recordedName: String {
            LocalizationStore.localizedString("system_logs.detail.actor.recorded_name", defaultValue: "Ім’я в записі")
        }

        static var currentProfile: String {
            LocalizationStore.localizedString("system_logs.detail.actor.current_profile", defaultValue: "Поточний профіль")
        }

        static var email: String {
            LocalizationStore.localizedString("system_logs.detail.actor.email", defaultValue: "Електронна пошта")
        }

        static var loading: String {
            LocalizationStore.localizedString("system_logs.detail.actor.loading", defaultValue: "Завантаження…")
        }

        static var notFound: String {
            LocalizationStore.localizedString("system_logs.detail.actor.not_found", defaultValue: "Поточний профіль не знайдено. Обліковий запис міг бути видалений.")
        }

        static var unavailable: String {
            LocalizationStore.localizedString("system_logs.detail.actor.unavailable", defaultValue: "Не вдалося завантажити поточний профіль.")
        }

        static var noDisplayData: String {
            LocalizationStore.localizedString("system_logs.detail.actor.no_display_data", defaultValue: "У поточному профілі немає імені або електронної пошти.")
        }
    }
}

private struct ActorDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                titleLabel.frame(width: 104, alignment: .leading)
                valueLabel
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                titleLabel
                valueLabel
            }
        }
    }

    private var titleLabel: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
    }

    private var valueLabel: some View {
        Text(value)
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}
