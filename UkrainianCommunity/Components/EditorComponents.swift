import SwiftUI

struct AppEditorSectionCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        SoftContentCard(padding: AppTheme.editorSectionCardPadding) {
            content
        }
    }
}

struct AppEditorSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppTheme.cardTitleFont)
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct AppEditorField<Content: View>: View {
    let title: String
    let counterText: String?
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(title: String, counterText: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.counterText = counterText
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            if let counterText {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        fieldTitle
                        fieldCounter(counterText)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        fieldTitle

                        Spacer(minLength: AppTheme.eventsMetadataSpacing)
                        fieldCounter(counterText)
                    }
                }
            } else {
                fieldTitle
            }

            content
        }
    }

    private var fieldTitle: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func fieldCounter(_ counterText: String) -> some View {
        Text(counterText)
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct EditorTextField: View {
    let title: String
    @Binding var text: String
    let systemImage: String
    let counterText: String?
    let keyboardType: UIKeyboardType
    let textContentType: UITextContentType?
    let autocapitalization: TextInputAutocapitalization
    let autocorrectionDisabled: Bool

    init(
        _ title: String,
        text: Binding<String>,
        systemImage: String,
        counterText: String? = nil,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        autocapitalization: TextInputAutocapitalization = .sentences,
        autocorrectionDisabled: Bool = false
    ) {
        self.title = title
        self._text = text
        self.systemImage = systemImage
        self.counterText = counterText
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.autocapitalization = autocapitalization
        self.autocorrectionDisabled = autocorrectionDisabled
    }

    var body: some View {
        if let counterText {
            AppEditorField(title: title, counterText: counterText) {
                fieldContent
            }
        } else {
            fieldContent
        }
    }

    private var fieldContent: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimaryForeground)
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
        .padding(.vertical, 10)
        .frame(minHeight: AppTheme.newsEditorInputHeight)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
    }
}

struct EditorTextArea: View {
    let title: String
    @Binding var text: String
    let counterText: String
    let minHeight: CGFloat

    init(
        _ title: String,
        text: Binding<String>,
        counterText: String,
        minHeight: CGFloat = 92
    ) {
        self.title = title
        self._text = text
        self.counterText = counterText
        self.minHeight = minHeight
    }

    var body: some View {
        AppEditorField(title: title, counterText: counterText) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
                        .padding(.vertical, AppTheme.eventsMetadataSpacing)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .textInputAutocapitalization(.sentences)
                    .padding(4)
                    .frame(minHeight: minHeight, alignment: .topLeading)
            }
            .background(
                AppTheme.surfaceSecondary,
                in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                    .strokeBorder(AppTheme.borderSubtle)
            )
            .accessibilityLabel(title)
        }
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
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .frame(width: AppTheme.metadataIconSize)

            SecureField(title, text: $text)
                .font(.subheadline)
                .textContentType(textContentType)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .padding(.vertical, 10)
        .frame(minHeight: AppTheme.newsEditorInputHeight)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
    }
}
