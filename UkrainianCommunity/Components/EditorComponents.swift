import SwiftUI

struct AppEditorSectionCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        SoftContentCard(padding: AppTheme.detailCardPadding) {
            content
        }
    }
}

struct AppEditorSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppEditorField<Content: View>: View {
    let title: String
    let counterText: String?
    @ViewBuilder let content: Content

    init(title: String, counterText: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.counterText = counterText
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                if let counterText {
                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    Text(counterText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .monospacedDigit()
                }
            }

            content
        }
    }
}

struct AppEditorSubmitButton: View {
    let title: String
    let isEnabled: Bool
    let isLoading: Bool
    let loadingTitle: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                }

                Text(isLoading ? loadingTitle : title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppTheme.sectionSpacing)
            .frame(height: AppTheme.iconButtonSize)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                    .fill(isEnabled ? AppTheme.accentPrimary : AppTheme.accentPrimary.opacity(0.38))
            )
            .shadow(color: isEnabled ? AppTheme.glassShadow(for: colorScheme) : .clear, radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }
}

struct EditorTextField: View {
    let title: String
    @Binding var text: String
    let systemImage: String
    let keyboardType: UIKeyboardType
    let textContentType: UITextContentType?
    let autocapitalization: TextInputAutocapitalization
    let autocorrectionDisabled: Bool

    init(
        _ title: String,
        text: Binding<String>,
        systemImage: String,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        autocapitalization: TextInputAutocapitalization = .sentences,
        autocorrectionDisabled: Bool = false
    ) {
        self.title = title
        self._text = text
        self.systemImage = systemImage
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.autocapitalization = autocapitalization
        self.autocorrectionDisabled = autocorrectionDisabled
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: AppTheme.metadataIconSize)

            TextField(title, text: $text)
                .font(.subheadline)
                .textInputAutocapitalization(autocapitalization)
                .textContentType(textContentType)
                .keyboardType(keyboardType)
                .autocorrectionDisabled(autocorrectionDisabled)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(height: AppTheme.newsEditorInputHeight)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
    }
}

struct EditorSecureField: View {
    let title: String
    @Binding var text: String
    let systemImage: String
    let textContentType: UITextContentType?

    init(
        _ title: String,
        text: Binding<String>,
        systemImage: String = "lock",
        textContentType: UITextContentType? = nil
    ) {
        self.title = title
        self._text = text
        self.systemImage = systemImage
        self.textContentType = textContentType
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: AppTheme.metadataIconSize)

            SecureField(title, text: $text)
                .font(.subheadline)
                .textContentType(textContentType)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(height: AppTheme.newsEditorInputHeight)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
    }
}
