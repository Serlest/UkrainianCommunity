import Combine
import Foundation

@MainActor
final class OrganizationBlockingCoordinator: ObservableObject {
    @Published private(set) var blockedOrganizations: [BlockedOrganization] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isMutating = false
    @Published var pendingTarget: OrganizationBlockTarget?
    @Published private(set) var errorMessage: String?

    private let repository: OrganizationBlockingRepository
    private let cache: UserDefaults?
    private var userID: String?
    private var generation = 0

    init(repository: OrganizationBlockingRepository, cache: UserDefaults? = .standard) {
        self.repository = repository
        self.cache = cache
    }

    var blockedOrganizationIDs: Set<String> { Set(blockedOrganizations.map(\.organizationID)) }

    func configure(userID: String?) async {
        guard self.userID != userID else { return }
        self.userID = userID
        generation += 1
        pendingTarget = nil
        errorMessage = nil
        isLoading = false
        isMutating = false
        blockedOrganizations = userID.flatMap { cache?.data(forKey: cacheKey($0)) }
            .flatMap { try? JSONDecoder().decode([BlockedOrganization].self, from: $0) } ?? []
        await reload()
    }

    func reload() async {
        guard let userID, !isMutating else { return }
        generation += 1
        let requestGeneration = generation
        isLoading = true
        defer { if generation == requestGeneration { isLoading = false } }
        do {
            let blocks = try await repository.fetchBlockedOrganizations()
            guard generation == requestGeneration, self.userID == userID else { return }
            blockedOrganizations = blocks
            saveCache(for: userID)
            errorMessage = nil
        } catch {
            guard generation == requestGeneration else { return }
            errorMessage = AppStrings.Safety.organizationBlockFailed
        }
    }

    func present(_ organization: Organization) {
        guard userID != nil, !blockedOrganizationIDs.contains(organization.id) else { return }
        errorMessage = nil
        pendingTarget = OrganizationBlockTarget(organization)
    }

    @discardableResult
    func setBlocked(organizationID: String, isBlocked: Bool) async -> Bool {
        guard let userID, !isMutating else { return false }
        generation += 1
        let requestGeneration = generation
        isLoading = false
        isMutating = true
        errorMessage = nil
        defer { if generation == requestGeneration { isMutating = false } }
        do {
            let block = try await repository.setBlocked(organizationID: organizationID, isBlocked: isBlocked)
            guard generation == requestGeneration, self.userID == userID else { return false }
            guard isBlocked == (block != nil), block == nil || block?.organizationID == organizationID else {
                throw AppError.validationFailed
            }
            blockedOrganizations.removeAll { $0.organizationID == organizationID }
            if let block { blockedOrganizations.append(block) }
            saveCache(for: userID)
            pendingTarget = nil
            return true
        } catch {
            guard generation == requestGeneration else { return false }
            errorMessage = AppStrings.Safety.organizationBlockFailed
            return false
        }
    }

    private func cacheKey(_ userID: String) -> String { "uac.blockedOrganizations.v1.\(userID)" }

    private func saveCache(for userID: String) {
        guard let data = try? JSONEncoder().encode(blockedOrganizations) else { return }
        cache?.set(data, forKey: cacheKey(userID))
    }
}
