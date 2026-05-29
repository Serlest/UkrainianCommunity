import SwiftUI

extension ProfileView {
    var notificationsSection: some View {
        NotificationSettingsSectionView(viewModel: viewModel, userID: authState.user?.id)
    }
}
