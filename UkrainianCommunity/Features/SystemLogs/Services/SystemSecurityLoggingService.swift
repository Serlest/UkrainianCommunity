import FirebaseAuth
import FirebaseFirestore
import Foundation

struct SystemSecurityLogContext {
    let moduleName: String
    let operationName: String
    let eventType: SystemLogEventType
    let severity: SystemLogSeverity
    let targetType: SystemLogTargetType
    let targetId: String?
    let targetTitle: String?
    let outcome: SystemLogOutcome
    let summary: String
    let metadata: [String: String]

    init(
        moduleName: String,
        operationName: String,
        eventType: SystemLogEventType,
        severity: SystemLogSeverity,
        targetType: SystemLogTargetType,
        targetId: String? = nil,
        targetTitle: String? = nil,
        outcome: SystemLogOutcome,
        summary: String,
        metadata: [String: String] = [:]
    ) {
        self.moduleName = moduleName
        self.operationName = operationName
        self.eventType = eventType
        self.severity = severity
        self.targetType = targetType
        self.targetId = targetId
        self.targetTitle = targetTitle
        self.outcome = outcome
        self.summary = summary
        self.metadata = metadata
    }
}

final class SystemSecurityLoggingService {
    static let shared = SystemSecurityLoggingService()

    private let loggingService: SystemLoggingServiceProtocol
    private let actorResolver: SystemSecurityActorResolving
    private let deduplicator: SystemSecurityLogDeduplicator

    init(
        loggingService: SystemLoggingServiceProtocol = FirestoreSystemLogRepository(),
        actorResolver: SystemSecurityActorResolving = FirebaseSystemSecurityActorResolver(),
        deduplicator: SystemSecurityLogDeduplicator = SystemSecurityLogDeduplicator()
    ) {
        self.loggingService = loggingService
        self.actorResolver = actorResolver
        self.deduplicator = deduplicator
    }

    func log(_ context: SystemSecurityLogContext) async {
        guard let actor = await actorResolver.resolveSecurityActor() else { return }
        let dedupeKey = [
            actor.userId,
            context.moduleName,
            context.operationName,
            context.targetType.rawValue,
            context.targetId ?? "none",
            context.outcome.rawValue
        ].joined(separator: "|")

        guard await deduplicator.shouldLog(key: dedupeKey) else { return }

        var draft = SystemLogDraft.security(
            eventType: context.eventType,
            summary: context.summary,
            severity: context.severity,
            actorUserId: actor.userId,
            actorDisplayName: actor.displayName,
            actorRole: actor.role,
            targetType: context.targetType,
            targetId: context.targetId,
            targetTitle: context.targetTitle,
            outcome: context.outcome,
            metadata: context.metadata
        )
        draft.moduleName = context.moduleName
        draft.operationName = context.operationName

        do {
            try await loggingService.logSecurity(draft)
        } catch {
            // Best-effort security logging only: logging must never alter the protected operation result.
        }
    }
}

struct SystemSecurityActor {
    let userId: String
    let displayName: String?
    let role: SystemLogActorRole
}

protocol SystemSecurityActorResolving {
    func resolveSecurityActor() async -> SystemSecurityActor?
}

struct FirebaseSystemSecurityActorResolver: SystemSecurityActorResolving {
    func resolveSecurityActor() async -> SystemSecurityActor? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        do {
            let snapshot = try await Firestore.firestore().collection("users").document(uid).getDocument()
            let data = snapshot.data() ?? [:]
            guard let role = securityRole(from: data["globalRole"] as? String) else { return nil }

            return SystemSecurityActor(
                userId: uid,
                displayName: displayName(from: data),
                role: role
            )
        } catch {
            return nil
        }
    }

    private func securityRole(from rawValue: String?) -> SystemLogActorRole? {
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

actor SystemSecurityLogDeduplicator {
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
