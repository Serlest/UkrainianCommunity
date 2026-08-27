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
    private var loadedUserID: String?

    init(repository: OrganizationRepository) { self.repository = repository }

    func load(for user: AppUser?) async {
        generation &+= 1
        let request = generation
        error = nil
        guard let user, PermissionService.isUsableAccount(user: user) else {
            loadedUserID = nil
            organizations = []
            isLoading = false
            contentVersion &+= 1
            return
        }

        // Keep the last verified permissions visible during a same-account
        // refresh. Clearing them here made quick-create controls disappear and
        // reappear every time the app became active. Never retain permissions
        // across account boundaries.
        if loadedUserID != user.id {
            loadedUserID = user.id
            organizations = []
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
