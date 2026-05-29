import SwiftUI

struct ProfileSettingsPickerRow<PickerContent: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let picker: PickerContent

    init(title: String, subtitle: String, systemImage: String, @ViewBuilder picker: () -> PickerContent) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.picker = picker()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 30, height: 30)
                .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            picker
                .controlSize(.small)
        }
        .padding(.vertical, 3)
    }
}

struct ProfileSettingsToggleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 30, height: 30)
                .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.vertical, 3)
    }
}
