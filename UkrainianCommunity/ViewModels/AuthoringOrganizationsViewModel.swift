import Combine
import Foundation

@MainActor
final class AuthoringOrganizationsViewModel: ObservableObject {
    @Published private(set) var organizations: [Organization] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published private(set) var contentVersion = 0
    private let repository: OrganizationRepository
    private var generation = 0

    init(repository: OrganizationRepository) { self.repository = repository }

    func load(for user: AppUser?) async {
        generation &+= 1
        let request = generation
        organizations = []
        error = nil
        guard let user, PermissionService.isUsableAccount(user: user) else {
            isLoading = false
            contentVersion &+= 1
            return
        }
        isLoading = true
        do {
            let result = try await RefreshRequest.run { [repository] in
                try await repository.fetchAuthoringOrganizations(user: user)
            }
            guard request == generation, !Task.isCancelled else { return }
            organizations = PermissionService.manageableOrganizations(from: result, user: user)
                .filter { $0.moderationStatus == .approved }
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            self.error = (error as? AppError) ?? .unknown
        }
        guard request == generation else { return }
        isLoading = false
        contentVersion &+= 1
    }
}
