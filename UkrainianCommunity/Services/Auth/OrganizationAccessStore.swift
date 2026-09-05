import Combine
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

@MainActor
final class OrganizationAccessStore: ObservableObject {
    static let shared = OrganizationAccessStore()
    @Published private(set) var revision = 0
    private var principalID: String?
    private var generation = 0
    private var records: [String: (actions: Set<String>, expires: Date)] = [:]
    private var pending = Set<String>()
    private var refreshTask: Task<Void, Never>?
    private var unavailableUntil: Date?
    private var enforced = false
    private var commandsEnabled = false
    private var actionModes: [String: String] = [:]
    private var commands: [String: Bool] = [:]
    private var legacyDecisions: [String: [String: Bool]] = [:]
    private let currentUID: () -> String?
    private let call: (String, [String: Any]) async throws -> [String: Any]

    init(currentUID: @escaping () -> String? = { Auth.auth().currentUser?.uid },
         call: @escaping (String, [String: Any]) async throws -> [String: Any] = { name, payload in
             let result = try await Functions.functions(region: "europe-west3").httpsCallable(name).call(payload)
             guard let data = result.data as? [String: Any] else { throw AppError.unknown }
             return data
         }) {
        self.currentUID = currentUID
        self.call = call
    }

    private var clientVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown" }
    private func isEnforced(_ action: String) -> Bool { actionModes[action].map { $0 == "enforced" } ?? enforced }


    func transition(to principalID: String?) {
        guard self.principalID != principalID else { return }
        self.principalID = principalID
        generation &+= 1
        refreshTask?.cancel(); refreshTask = nil
        records.removeAll(); pending.removeAll(); unavailableUntil = nil
        enforced = false; commandsEnabled = false
        actionModes.removeAll(); commands.removeAll(); legacyDecisions.removeAll()
        revision &+= 1
    }

    func allows(_ action: String, organizationID: String, userID: String?, legacy: Bool) -> Bool {
        guard let userID, userID == principalID else { return legacy }
        legacyDecisions[organizationID, default: [:]][action] = legacy
        if let entry = records[organizationID], entry.expires > Date() {
            return isEnforced(action) ? entry.actions.contains(action) : legacy
        }
        requestRefresh(organizationID)
        return isEnforced(action) ? false : legacy
    }

    private func requestRefresh(_ organizationID: String) {
        guard unavailableUntil.map({ $0 > Date() }) != true else { return }
        pending.insert(organizationID)
        guard refreshTask == nil else { return }
        let expected = generation
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(30))
            guard let self, !Task.isCancelled else { return }
            let ids = Array(self.pending.prefix(50))
            self.pending.subtract(ids)
            defer {
                if self.generation == expected {
                    self.refreshTask = nil
                    if let next = self.pending.first { self.requestRefresh(next) }
                }
            }
            try? await self.refresh(ids)
        }
    }

    private func refresh(_ ids: [String]) async throws {
        guard let uid = principalID, currentUID() == uid else { throw CancellationError() }
        let expected = generation
        do {
            let response = try await call("getOrganizationAccess", ["organizationIds": ids,
                "legacyDecisions": legacyDecisions.filter { ids.contains($0.key) }, "clientVersion": clientVersion])
            guard generation == expected, principalID == uid, currentUID() == uid else { throw CancellationError() }
            guard response["principalId"] as? String == uid,
                  response["schemaVersion"] as? Int == 1, let entries = response["records"] as? [[String: Any]] else { throw AppError.unknown }
            enforced = response["mode"] as? String == "enforced"
            commandsEnabled = response["commandsEnabled"] as? Bool == true
            actionModes = response["actionModes"] as? [String: String] ?? [:]
            commands = response["commands"] as? [String: Bool] ?? [:]
            for entry in entries {
                guard let id = entry["organizationId"] as? String, ids.contains(id), let actions = entry["actions"] as? [String] else { throw AppError.unknown }
                records[id] = (Set(actions), Date().addingTimeInterval(30))
            }
            revision &+= 1
        } catch {
            guard generation == expected else { throw CancellationError() }
            // Absence of the new endpoint means this server still uses v1.
            // A permission denial is never a reason to retry a write via v1.
            if (error as NSError).domain == FunctionsErrorDomain,
               FunctionsErrorCode(rawValue: (error as NSError).code) == .notFound {
                unavailableUntil = Date().addingTimeInterval(60)
                enforced = false; commandsEnabled = false
                actionModes.removeAll(); commands.removeAll()
                return
            }
            unavailableUntil = Date().addingTimeInterval(5)
            throw OrganizationAccessFailure(error)
        }
    }

    func saveIfEnabled(_ organization: Organization, fields: [String: Any]) async throws -> Bool {
        guard let uid = currentUID() else { throw AppError.permissionDenied }
        if principalID != uid { transition(to: uid) }
        let sessionGeneration = generation
        try await refresh([organization.id])
        guard generation == sessionGeneration, principalID == uid, currentUID() == uid else { throw CancellationError() }
        let isResubmitting = fields["submittedAt"] != nil
        let action = isResubmitting ? "resubmitRequest" : "editInfo"
        guard isEnforced(action) && (commands["updateOrganizationInfo"] ?? commandsEnabled) else { return false }
        let actions = records[organization.id]?.actions ?? []
        guard actions.contains("editInfo") || (actions.contains("resubmitRequest") && organization.moderationStatus == .pendingReview) else { throw AppError.permissionDenied }
        var payload = fields
        for key in ["updatedAt", "moderationStatus", "submittedAt", "reviewMessage", "rejectionReason"] { payload.removeValue(forKey: key) }
        let wire = payload.mapValues(Self.wireValue)
        let material = try JSONSerialization.data(withJSONObject: ["user": uid, "organization": organization.id,
            "fields": wire, "revision": organization.accessRevision as Any? ?? NSNull(),
            "targetStatus": organization.moderationStatus.rawValue], options: [.sortedKeys])
        let operationID = SHA256.hash(data: material).map { String(format: "%02x", $0) }.joined()
        let expected = generation
        do {
            _ = try await call("updateOrganizationInfo", ["clientVersion": clientVersion,
                "organizationId": organization.id, "operationId": operationID, "fields": wire, "principalId": uid,
                "expectedRevision": organization.accessRevision as Any? ?? NSNull(),
                "targetStatus": organization.moderationStatus.rawValue,
            ])
        } catch { throw OrganizationAccessFailure(error) }

        guard generation == expected, currentUID() == uid else { throw CancellationError() }
        records.removeValue(forKey: organization.id)
        return true
    }

    func preparePhotoCommand(organizationID: String) async throws -> Bool {
        guard let uid = currentUID() else { throw AppError.permissionDenied }
        if principalID != uid { transition(to: uid) }
        let expected = generation
        try await refresh([organizationID])
        guard generation == expected, principalID == uid, currentUID() == uid else { throw CancellationError() }
        guard isEnforced("managePhotos") && commands["saveOrganizationPhoto"] == true else { return false }
        guard records[organizationID]?.actions.contains("managePhotos") == true else {
            throw OrganizationAccessFailure(reason: "role_missing")
        }
        return true
    }

    private static func wireValue(_ value: Any) -> Any {
        if value is FieldValue { return NSNull() }
        if let time = value as? Timestamp { return ["__timestamp": ["seconds": time.seconds, "nanoseconds": Int64(time.nanoseconds)]] }
        if let object = value as? [String: Any] { return object.mapValues(wireValue) }
        if let list = value as? [Any] { return list.map(wireValue) }
        return value
    }
}

