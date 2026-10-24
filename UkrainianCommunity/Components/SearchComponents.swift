import SwiftUI

/// Shared search input for catalog, administration and personal screens.
/// Search execution stays with the caller so local and server searches retain
/// their own pagination, cancellation and debounce behavior.
struct AppSearchField: View {
    let placeholder: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding? = nil
    var fieldID: String? = nil
    var isSearching = false
    var onClear: (() -> Void)? = nil
    @FocusState private var localFocus: Bool

    private var effectiveFocus: FocusState<Bool>.Binding { focus ?? $localFocus }

    var body: some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text,
                      prompt: Text(placeholder).foregroundStyle(AppTheme.textSecondary))
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
                .frame(minHeight: AppTheme.searchControlHeight)
                .tint(AppTheme.accentPrimaryForeground)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(effectiveFocus)
                .submitLabel(.search)
                .onSubmit { effectiveFocus.wrappedValue = false }
                .accessibilityIdentifier(fieldID ?? "")
            if isSearching { ProgressView().controlSize(.small) }
            if !text.isEmpty {
                AppSearchClearButton { text = ""; effectiveFocus.wrappedValue = true; onClear?() }
                    .accessibilityIdentifier(fieldID.map { $0 + ".clear" } ?? "")
            }
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(minHeight: AppTheme.searchControlHeight)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                .fill(AppTheme.surfaceControl)
                .contentShape(Rectangle())
                .onTapGesture { effectiveFocus.wrappedValue = true }
        }
        .preservesKeyboardFocusWithinBounds()
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        }
    }
}
