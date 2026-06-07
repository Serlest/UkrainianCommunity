import Foundation

struct SystemTechnicalErrorContext {
    let moduleName: String
    let operationName: String
    let screenName: String?
    let targetType: SystemLogTargetType
    let targetId: String?
    let targetTitle: String?
    let organizationId: String?
    let organizationName: String?
    let metadata: [String: String]
    let isDestructiveAccountOperation: Bool

    init(
        moduleName: String,
        operationName: String,
        screenName: String? = nil,
        targetType: SystemLogTargetType = .none,
        targetId: String? = nil,
        targetTitle: String? = nil,
        organizationId: String? = nil,
        organizationName: String? = nil,
        metadata: [String: String] = [:],
        isDestructiveAccountOperation: Bool = false
    ) {
        self.moduleName = moduleName
        self.operationName = operationName
        self.screenName = screenName
        self.targetType = targetType
        self.targetId = targetId
        self.targetTitle = targetTitle
        self.organizationId = organizationId
        self.organizationName = organizationName
        self.metadata = metadata
        self.isDestructiveAccountOperation = isDestructiveAccountOperation
    }
}

final class SystemTechnicalErrorLoggingService {
    static let shared = SystemTechnicalErrorLoggingService()

    private let loggingService: SystemLoggingServiceProtocol
    private let deduplicator: SystemTechnicalErrorDeduplicator

    init(
        loggingService: SystemLoggingServiceProtocol = FirestoreSystemLogRepository(),
        deduplicator: SystemTechnicalErrorDeduplicator = SystemTechnicalErrorDeduplicator()
    ) {
        self.loggingService = loggingService
        self.deduplicator = deduplicator
    }

    func logFailure(_ error: Error, context: SystemTechnicalErrorContext) async {
        let classification = SystemTechnicalErrorClassifier.classify(error, context: context)
        let dedupeKey = [
            context.moduleName,
            context.operationName,
            context.targetType.rawValue,
            context.targetId ?? "none",
            classification.errorCode
        ].joined(separator: "|")

        guard await deduplicator.shouldLog(key: dedupeKey) else { return }

        var draft = SystemLogDraft.error(
            eventType: .technicalError,
            summary: "Technical failure in \(context.moduleName).\(context.operationName)",
            technicalMessage: classification.technicalMessage,
            errorCode: classification.errorCode,
            moduleName: context.moduleName,
            operationName: context.operationName,
            targetType: context.targetType,
            targetId: context.targetId,
            targetTitle: context.targetTitle,
            metadata: classification.metadata
        )
        draft.severity = classification.severity
        draft.screenName = context.screenName
        draft.organizationId = context.organizationId
        draft.organizationName = context.organizationName
        draft.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        draft.osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        do {
            try await loggingService.logError(draft)
        } catch {
            // Best-effort diagnostics only: logging must never block the user flow.
        }
    }
}

actor SystemTechnicalErrorDeduplicator {
    private var recentKeys: [String: Date] = [:]
    private let interval: TimeInterval
    private let nowProvider: () -> Date

    init(interval: TimeInterval = 60, nowProvider: @escaping () -> Date = Date.init) {
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
