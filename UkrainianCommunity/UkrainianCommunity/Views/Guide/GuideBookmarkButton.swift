import SwiftUI

struct GuideBookmarkButton: View {
    let isSaved: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        AppGlassIconButton(
            systemImage: isSaved ? "bookmark.fill" : "bookmark",
            accessibilityLabel: AppStrings.Action.save
        ) {
            action()
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .disabled(isDisabled)
    }
}
