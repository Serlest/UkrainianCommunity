import Foundation
import Combine

final class AuthState: ObservableObject {
    @Published var user: AppUser?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @MainActor
    func loadUser(uid: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let result = await UserProfileService.shared.fetchUserProfile(uid: uid)
        user = result

        if result == nil {
            errorMessage = "Failed to load user profile."
            print("AuthState failed to load user: \(uid)")
            return
        }

        print("AuthState loaded user successfully: \(uid)")
        #if DEBUG
        if let result {
            print("AuthState debug uid=\(result.id)")
            print("AuthState debug globalRole=\(result.globalRole.rawValue)")
            print("AuthState debug accountStatus=\(result.accountStatus.rawValue)")
            print("AuthState debug isBlocked=\(result.blockState == .blocked)")
        }
        #endif
    }
}
