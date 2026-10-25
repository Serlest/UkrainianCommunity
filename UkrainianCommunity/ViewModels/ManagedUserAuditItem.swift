import FirebaseFirestore
import Foundation

struct ManagedUserAuditItem: Identifiable {
    let id: String
    let actionType: String
    let reason: String
    let performedBy: String
    let previousValue: [String: Any]
    let newValue: [String: Any]
    let createdAt: Date

    var title: String {
        switch actionType {
        case "userWarned": AppStrings.UserManagement.actionWarn
        case "userSuspended": AppStrings.UserManagement.actionSuspend
        case "userBanned": AppStrings.UserManagement.actionBan
        case "userDeactivated": AppStrings.UserManagement.actionDeactivate
        case "userRestored", "userSuspensionExpired": AppStrings.UserManagement.actionUnblock
        case "appAdminAssigned": AppStrings.UserManagement.assignAppAdmin
        case "appAdminRemoved": AppStrings.UserManagement.removeAppAdmin
        case "directoryEditorGranted": DirectoryEditorText.value("Надано доступ до довідника", "Ratgeberzugriff erteilt")
        case "directoryEditorRevoked": DirectoryEditorText.value("Відкликано доступ до довідника", "Ratgeberzugriff entzogen")
        case "organizationRoleAssigned": AppStrings.UserManagement.assignRoleButton
        case "organizationRoleRemoved": AppStrings.UserManagement.removeOrganizationRoleButton
        case "organizationOwnerChanged": AppStrings.UserManagement.changeOwnerButton
        default: AppStrings.UserManagement.actionFallbackTitle
        }
    }

    var changeSummary: String? {
        let keys = ["accountStatus", "blockState", "globalRole", "role", "organizationId", "directoryEditorEnabled", "banExpiresAt"]
        let changes = keys.compactMap { key -> String? in
            let previous = displayValue(previousValue[key], key: key)
            let next = displayValue(newValue[key], key: key)
            guard previous != next, previous != nil || next != nil else { return nil }
            let label: String = switch key {
            case "accountStatus", "blockState": AppStrings.Common.status
            case "banExpiresAt": AppStrings.UserManagement.blockedUntil
            case "globalRole": AppStrings.UserManagement.currentPlatformRole
            case "role": AppStrings.Profile.role
            case "directoryEditorEnabled": DirectoryEditorText.value("Редагування довідника", "Ratgeber bearbeiten")
            default: AppStrings.Organizations.title
            }
            return "\(label): \(previous ?? "—") → \(next ?? "—")"
        }
        var seen = Set<String>()
        let unique = changes.filter { seen.insert($0).inserted }
        return unique.isEmpty ? nil : unique.joined(separator: " · ")
    }

    private func displayValue(_ value: Any?, key: String) -> String? {
        if let date = (value as? Timestamp)?.dateValue() {
            return LocalizationStore.dateString(from: date, dateStyle: .medium, timeStyle: .short)
        }
        if key == "directoryEditorEnabled", let enabled = value as? Bool {
            return enabled ? DirectoryEditorText.value("Доступ надано", "Zugriff erteilt") : DirectoryEditorText.value("Без доступу", "Kein Zugriff")
        }
        if let raw = value as? String {
            if key == "accountStatus", let status = AccountStatus(rawValue: raw) { return status.title }
            if key == "blockState", let status = UserBlockState(rawValue: raw) { return status.title }
            if key == "globalRole", let role = GlobalRole(rawValue: raw) { return role.title }
            if key == "role", let role = CommunityRole(rawValue: raw) {
                return switch role {
                case .communityOwner: AppStrings.Organizations.communityOwner
                case .communityAdmin: AppStrings.Organizations.communityAdmin
                case .communityModerator: AppStrings.Organizations.communityModerator
                case .member: AppStrings.Organizations.communityMember
                }
            }
        }
        return switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        case nil: nil
        default: String(describing: value!)
        }
    }
}
