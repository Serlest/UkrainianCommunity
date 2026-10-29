import Combine
import Foundation

@MainActor final class SubscriptionsViewModel: ObservableObject {
    @Published private(set) var records: [SavedContentRecord<Organization>] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published private(set) var pending = Set<String>()
    @Published private(set) var cursor: String?
    @Published private(set) var hasLoaded = false
    private var userID: String?
    private var generation = 0
    private let repository: OrganizationRepository
    private let shared: OrganizationsViewModel
    private let recordActivity: @MainActor (ActivityLogItem, String) -> Void
    init(repository: OrganizationRepository, shared: OrganizationsViewModel,
         recordActivity: @escaping @MainActor (ActivityLogItem, String) -> Void = { ActivityLogRecorder.record($0, userID: $1) }) {
        self.repository = repository; self.shared = shared; self.recordActivity = recordActivity
    }

    func bind(_ userID: String?) {
        guard self.userID != userID else { return }
        self.userID = userID; generation += 1
        records = []; cursor = nil; pending = []; isLoading = false; error = nil; hasLoaded = false
    }
    func load(append: Bool = false) async {
        guard userID != nil, !isLoading, pending.isEmpty, !append || cursor != nil else { return }
        let token = generation
        let baseline = Dictionary(shared.organizations.map { ($0.id, $0.isSubscribed) }, uniquingKeysWith: { _, new in new })
        isLoading = true
        defer { if token == generation { isLoading = false } }
        do {
            let after = append ? cursor : nil
            let page = try await RefreshRequest.run { [repository] in try await repository.fetchSubscriptionPage(limit: 20, after: after) }
            guard token == generation, !Task.isCancelled else { return }
            let combined = (append ? records : []) + page.items
            records = Array(Dictionary(combined.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new }).values)
            cursor = page.nextCursor
            for organization in page.items.compactMap(\.content) where !shared.visibilityPolicy.visibleOrganizations([organization]).isEmpty {
                if let index = shared.organizations.firstIndex(where: { $0.id == organization.id }) {
                    if baseline[organization.id] == shared.organizations[index].isSubscribed { shared.organizations[index].isSubscribed = true }
                } else { shared.organizations.append(organization) }
            }
            reconcile()
            hasLoaded = true
            error = nil
        } catch is CancellationError {} catch {
            guard token == generation else { return }
            self.error = FirebaseReadErrorMapper.map(error)
        }
    }
    func reconcile() {
        let byID = Dictionary(shared.organizations.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        records.removeAll { record in
            guard let organization = byID[record.id], !shared.visibilityPolicy.visibleOrganizations([organization]).isEmpty else { return false }
            return !shared.pendingOrganizationSubscriptionIDs.contains(record.id) && organization.isSubscribed == false
        }
    }
    func remove(_ id: String) async {
        guard let requestedUserID = userID, !isLoading, !pending.contains(id) else { return }
        let token = generation
        let organization = records.first { $0.id == id }?.content ?? shared.organizations.first { $0.id == id }
        pending.insert(id); error = nil
        defer { if token == generation { pending.remove(id) } }
        do {
            try await repository.unsubscribeOrganization(id: id, actionCapture: nil)
            guard token == generation, !Task.isCancelled else { return }
            recordActivity(ActivityLogItem(id: UUID().uuidString, actionType: .unfollowedOrganization,
                targetId: id, targetType: .organization,
                title: organization?.localizedName ?? AppStrings.Profile.unavailableSubscriptionTitle,
                subtitle: organization?.city, imageURL: organization?.logoURL, createdAt: Date()), requestedUserID)
            records.removeAll { $0.id == id }
            if let index = shared.organizations.firstIndex(where: { $0.id == id }) {
                if shared.organizations[index].isSubscribed {
                    shared.organizations[index].subscriberCount = max(0, shared.organizations[index].subscriberCount - 1)
                }
                shared.organizations[index].isSubscribed = false
            }
        } catch {
            guard token == generation else { return }
            self.error = FirebaseReadErrorMapper.map(error)
        }
    }
}
