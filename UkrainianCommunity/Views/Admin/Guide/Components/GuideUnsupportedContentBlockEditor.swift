import SwiftUI

struct GuideUnsupportedContentBlockEditor: View {
    var body: some View {
        Text(AppStrings.GuideEditor.unsupportedBlockPlaceholder)
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

