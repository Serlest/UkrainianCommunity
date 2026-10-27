import SwiftUI

/// A wrapping SwiftUI label avoids the native picker title's clipped
/// intrinsic height at accessibility text sizes; options remain a native picker.
struct AnalyticsReportFilterMenu<Options: View>: View {
    let title: String
    let selectedTitle: String
    let identifier: String
    let options: Options

    init(title: String, selectedTitle: String, identifier: String, @ViewBuilder options: () -> Options) {
        self.title = title
        self.selectedTitle = selectedTitle
        self.identifier = identifier
        self.options = options()
    }

    var body: some View {
        Menu { options } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(selectedTitle)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: AppTheme.iconButtonSize, alignment: .leading)
            .contentShape(Rectangle())
            .foregroundStyle(AppTheme.accentPrimaryForeground)
        }
        .buttonStyle(.plain)
        .tint(AppTheme.accentPrimaryForeground)
        .accessibilityLabel(title)
        .accessibilityValue(selectedTitle)
        .accessibilityIdentifier(identifier)
    }
}
