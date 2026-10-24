import SwiftUI

enum AuthInput: Hashable { case email, password, repeatedPassword, displayName, telegram }

struct AuthFormField: View {
    let title: String
    @Binding var text: String
    let icon: String
    let field: AuthInput
    let focus: Binding<AuthInput?>
    let identifier: String
    var secure = false
    var preservesCredentialsOnRemoval = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var capitalization: TextInputAutocapitalization = .never
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}
    var returnKey: UIReturnKeyType = .next
    @State private var revealsPassword = false
    @FocusState private var textIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                input

            }
            .padding(.horizontal, AppTheme.inputHorizontalPadding)
            .padding(.vertical, secure ? 2 : 12)
            .frame(minHeight: 50)
            .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.inputRadius)
                    .strokeBorder(focus.wrappedValue == field ? AppTheme.accentPrimaryForeground : AppTheme.borderSubtle,
                                  lineWidth: focus.wrappedValue == field ? 1.5 : 1)
            }
        }
        .onChange(of: focus.wrappedValue) { _, value in
            if !secure { textIsFocused = value == field }
        }
        .onChange(of: textIsFocused) { _, value in
            if value { focus.wrappedValue = field }
            else if focus.wrappedValue == field { focus.wrappedValue = nil }
        }
    }

    @ViewBuilder private var input: some View {
        if secure {
            AuthPasswordInput(text: $text, revealed: $revealsPassword, contentType: contentType,
                              focus: focus, field: field, identifier: identifier, title: title,
                              returnKey: returnKey, preservesCredentialsOnRemoval: preservesCredentialsOnRemoval, onSubmit: onSubmit)
        } else {
            TextField(title, text: $text, prompt: Text(title).foregroundStyle(AppTheme.textSecondary))
                .font(.body)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled()
                .focused($textIsFocused)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
    }
}

/// Keep one native password field while revealing text. Replacing SecureField
/// with TextField can trigger Password AutoFill's save sheet before submission.
private struct AuthPasswordInput: UIViewRepresentable {
    @Binding var text: String
    @Binding var revealed: Bool
    let contentType: UITextContentType?
    let focus: Binding<AuthInput?>
    let field: AuthInput
    let identifier: String
    let title: String
    let returnKey: UIReturnKeyType
    let preservesCredentialsOnRemoval: Bool
    let onSubmit: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let view = UITextField()
        view.delegate = context.coordinator
        view.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .label
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let reveal = UIButton(type: .system)
        reveal.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        reveal.addTarget(context.coordinator, action: #selector(Coordinator.toggleVisibility), for: .touchUpInside)
        view.rightView = reveal
        view.rightViewMode = .always
        return view
    }
    func updateUIView(_ view: UITextField, context: Context) {
        context.coordinator.parent = self
        view.isEnabled = isEnabled
        view.accessibilityIdentifier = identifier
        view.accessibilityLabel = title
        view.placeholder = title
        if view.textContentType != contentType { view.textContentType = contentType }
        view.returnKeyType = returnKey
        if let reveal = view.rightView as? UIButton {
            reveal.setImage(UIImage(systemName: revealed ? "eye.slash" : "eye"), for: .normal)
            reveal.accessibilityLabel = revealed ? AuthPresentationStrings.hidePassword : AuthPresentationStrings.showPassword
            reveal.accessibilityIdentifier = identifier + ".visibility"
            reveal.isEnabled = isEnabled
        }
        if view.isSecureTextEntry == revealed {
            let value = view.text
            view.isSecureTextEntry = !revealed
            view.text = value
        }
        if view.text != text { view.text = text }
        if focus.wrappedValue == field, !view.isFirstResponder, view.window != nil { view.becomeFirstResponder() }
        if focus.wrappedValue != field, view.isFirstResponder { view.resignFirstResponder() }
    }
    static func dismantleUIView(_ view: UITextField, coordinator: Coordinator) {
        // Abandoning a draft is not a completed sign-in. Remove credential
        // semantics before UIKit removes the field from the hierarchy.
        guard !coordinator.parent.preservesCredentialsOnRemoval else { return }
        view.delegate = nil
        view.removeTarget(coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        view.textContentType = nil
        view.text = nil
        view.resignFirstResponder()
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AuthPasswordInput
        init(_ parent: AuthPasswordInput) { self.parent = parent }
        @objc func changed(_ view: UITextField) { parent.text = view.text ?? "" }
        @objc func toggleVisibility() { parent.revealed.toggle() }
        func textFieldDidBeginEditing(_ textField: UITextField) {
            if parent.focus.wrappedValue != parent.field { parent.focus.wrappedValue = parent.field }
        }
        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.focus.wrappedValue == parent.field { parent.focus.wrappedValue = nil }
        }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool { parent.onSubmit(); return true }
    }
}

struct AuthFederalStatePicker: View {
    @Binding var selection: AustrianFederalState?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Button(AppStrings.Auth.selectFederalState) { selection = nil; dismiss() }
                .accessibilityIdentifier("auth.register.region.none")
            ForEach(AustrianFederalState.allCases) { state in
                Button {
                    selection = state
                    dismiss()
                } label: {
                    HStack {
                        Text(AppStrings.FederalStates.title(for: state)).foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if selection == state { Image(systemName: "checkmark").foregroundStyle(AppTheme.accentPrimaryForeground) }
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("auth.register.region." + state.rawValue)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackgroundView())
        .navigationTitle(AppStrings.Auth.federalState)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auth.register.regionPicker")
    }
}

struct AuthRegistrationProgress: View {
    let step: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(step == 1 ? AuthPresentationStrings.stepOne : AuthPresentationStrings.stepTwo)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            HStack(spacing: 8) {
                Capsule().fill(AppTheme.accentPrimary).frame(height: 3)
                Capsule().fill(step == 2 ? AppTheme.accentPrimary : AppTheme.borderSubtle).frame(height: 3)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum AuthPresentationStrings {
    private static func text(_ key: String, _ fallback: String) -> String {
        LocalizationStore.localizedString("auth.presentation." + key, defaultValue: fallback, table: "AuthFlow")
    }
    static var showPassword: String { text("show_password", "Показати пароль") }
    static var hidePassword: String { text("hide_password", "Приховати пароль") }
    static var stepOne: String { text("step_one", "Крок 1 з 2 · Дані облікового запису") }
    static var stepTwo: String { text("step_two", "Крок 2 з 2 · Документи й налаштування") }
    static var continueAction: String { text("continue", "Далі") }
    static var confirmationTitle: String { text("confirmation_title", "Документи й налаштування") }
    static var optionalDetails: String { text("optional_details", "Додаткова інформація · необов’язково") }
    static var passwordHelp: String { text("password_help", "Від 10 до 128 символів. Не використовуйте пароль від іншого облікового запису.") }
    static var backToSignIn: String { text("back_to_sign_in", "Повернутися до входу") }
}
