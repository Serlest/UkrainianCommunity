import FirebaseAuth
import FirebaseFirestore
import Foundation

struct SystemAuditLogContext {
    let moduleName: String
    let operationName: String
    let eventType: SystemLogEventType
    let targetType: SystemLogTargetType
    let targetId: String?
    let targetTitle: String?
    let organizationId: String?
    let organizationName: String?
    let summary: String

    init(
        moduleName: String,
        operationName: String,
        eventType: SystemLogEventType,
        targetType: SystemLogTargetType,
        targetId: String? = nil,
        targetTitle: String? = nil,
        organizationId: String? = nil,
        organizationName: String? = nil,
        summary: String
    ) {
        self.moduleName = moduleName
        self.operationName = operationName
        self.eventType = eventType
        self.targetType = targetType
        self.targetId = targetId
        self.targetTitle = targetTitle
        self.organizationId = organizationId
        self.organizationName = organizationName
        self.summary = summary
    }
}

final class SystemAuditLoggingService {
    static let shared = SystemAuditLoggingService()

    private let loggingService: SystemLoggingServiceProtocol
    private let actorResolver: SystemAuditActorResolving
    private let deduplicator: SystemAuditLogDeduplicator

    init(
        loggingService: SystemLoggingServiceProtocol = FirestoreSystemLogRepository(),
        actorResolver: SystemAuditActorResolving = FirebaseSystemAuditActorResolver(),
        deduplicator: SystemAuditLogDeduplicator = SystemAuditLogDeduplicator()
    ) {
        self.loggingService = loggingService
        self.actorResolver = actorResolver
        self.deduplicator = deduplicator
    }

    func logSuccess(_ context: SystemAuditLogContext) async {
        guard let actor = await actorResolver.resolveOwnerOrAdminActor() else { return }
        let dedupeKey = [
            actor.userId,
            context.moduleName,
            context.operationName,
            context.targetType.rawValue,
            context.targetId ?? "none"
        ].joined(separator: "|")

        guard await deduplicator.shouldLog(key: dedupeKey) else { return }

        var draft = SystemLogDraft.audit(
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
            outcome: .success
        )
        draft.moduleName = context.moduleName
        draft.operationName = context.operationName

        do {
            try await loggingService.logAudit(draft)
        } catch {
            // Best-effort audit logging only: logging must never block the user action.
        }
    }
}

struct SystemAuditActor {
    let userId: String
    let displayName: String?
    let role: SystemLogActorRole
}

protocol SystemAuditActorResolving {
    func resolveOwnerOrAdminActor() async -> SystemAuditActor?
}

struct FirebaseSystemAuditActorResolver: SystemAuditActorResolving {
    func resolveOwnerOrAdminActor() async -> SystemAuditActor? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        do {
            let snapshot = try await Firestore.firestore().collection("users").document(uid).getDocument()
            let data = snapshot.data() ?? [:]
            guard let role = auditRole(from: data["globalRole"] as? String) else { return nil }

            return SystemAuditActor(
                userId: uid,
                displayName: displayName(from: data),
                role: role
            )
        } catch {
            return nil
        }
    }

    private func auditRole(from rawValue: String?) -> SystemLogActorRole? {
        switch rawValue {
        case GlobalRole.owner.rawValue:
            return .owner
        case GlobalRole.admin.rawValue:
            return .admin
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

actor SystemAuditLogDeduplicator {
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
