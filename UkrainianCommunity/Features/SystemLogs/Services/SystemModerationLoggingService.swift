import FirebaseAuth
import FirebaseFirestore
import Foundation

struct SystemModerationLogContext {
    let moduleName: String
    let operationName: String
    let eventType: SystemLogEventType
    let targetType: SystemLogTargetType
    let targetId: String?
    let targetTitle: String?
    let organizationId: String?
    let organizationName: String?
    let outcome: SystemLogOutcome
    let summary: String
    let metadata: [String: String]

    init(
        moduleName: String = "Moderation",
        operationName: String,
        eventType: SystemLogEventType,
        targetType: SystemLogTargetType,
        targetId: String? = nil,
        targetTitle: String? = nil,
        organizationId: String? = nil,
        organizationName: String? = nil,
        outcome: SystemLogOutcome,
        summary: String,
        metadata: [String: String] = [:]
    ) {
        self.moduleName = moduleName
        self.operationName = operationName
        self.eventType = eventType
        self.targetType = targetType
        self.targetId = targetId
        self.targetTitle = targetTitle
        self.organizationId = organizationId
        self.organizationName = organizationName
        self.outcome = outcome
        self.summary = summary
        self.metadata = metadata
    }
}

final class SystemModerationLoggingService {
    static let shared = SystemModerationLoggingService()

    private let loggingService: SystemLoggingServiceProtocol
    private let actorResolver: SystemModerationActorResolving
    private let deduplicator: SystemModerationLogDeduplicator

    init(
        loggingService: SystemLoggingServiceProtocol = FirestoreSystemLogRepository(),
        actorResolver: SystemModerationActorResolving = FirebaseSystemModerationActorResolver(),
        deduplicator: SystemModerationLogDeduplicator = SystemModerationLogDeduplicator()
    ) {
        self.loggingService = loggingService
        self.actorResolver = actorResolver
        self.deduplicator = deduplicator
    }

    func logSuccess(_ context: SystemModerationLogContext) async {
        guard let actor = await actorResolver.resolveModerationActor() else { return }
        let dedupeKey = [
            actor.userId,
            context.moduleName,
            context.operationName,
            context.targetType.rawValue,
            context.targetId ?? "none",
            context.outcome.rawValue
        ].joined(separator: "|")

        guard await deduplicator.shouldLog(key: dedupeKey) else { return }

        var draft = SystemLogDraft.moderation(
            eventType: context.eventType,
            targetType: context.targetType,
            summary: context.summary,
            actorUserId: actor.userId,
            actorDisplayName: actor.displayName,
            actorRole: actor.role,
            targetId: context.targetId,
            targetTitle: context.targetTitle,
            organizationId: context.organizationId,
            organizationName: context.organizationName,
            outcome: context.outcome,
            metadata: context.metadata
        )
        draft.moduleName = context.moduleName
        draft.operationName = context.operationName

        do {
            try await loggingService.logModeration(draft)
        } catch {
            // Best-effort moderation logging only: logging must never block the moderated action.
        }
    }
}

struct SystemModerationActor {
    let userId: String
    let displayName: String?
    let role: SystemLogActorRole
}

protocol SystemModerationActorResolving {
    func resolveModerationActor() async -> SystemModerationActor?
}

struct FirebaseSystemModerationActorResolver: SystemModerationActorResolving {
    func resolveModerationActor() async -> SystemModerationActor? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        do {
            let snapshot = try await Firestore.firestore().collection("users").document(uid).getDocument()
            let data = snapshot.data() ?? [:]
            guard let role = moderationRole(from: data["globalRole"] as? String) else { return nil }

            return SystemModerationActor(
                userId: uid,
                displayName: displayName(from: data),
                role: role
            )
        } catch {
            return nil
        }
    }

    private func moderationRole(from rawValue: String?) -> SystemLogActorRole? {
        switch rawValue {
        case GlobalRole.owner.rawValue:
            return .owner
        case GlobalRole.admin.rawValue:
            return .admin
        case GlobalRole.moderator.rawValue:
            return .moderator
        default:
            return nil
        }
    }

    private func displayName(from data: [String: Any]) -> String? {
        let candidates = [
            data["displayName"] as? String,
            data["fullName"] as? String
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

actor SystemModerationLogDeduplicator {
    private var recentKeys: [String: Date] = [:]
    private let interval: TimeInterval
    private let nowProvider: () -> Date

    init(interval: TimeInterval = 10, nowProvider: @escaping () -> Date = Date.init) {
        self.interval = interval
        self.nowProvider = nowProvider
    }

    func shouldLog(key: String) -> Bool {
        let now = nowProvider()
        recentKeys = recentKeys.filter { now.timeIntervalSince($0.value) < interval }

        if let lastLoggedAt = recentKeys[key], now.timeIntervalSince(lastLoggedAt) < interval {
            return false
        }

        recentKeys[key] = now
        return true
    }
}
