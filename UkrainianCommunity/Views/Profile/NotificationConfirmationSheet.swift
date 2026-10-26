import SwiftUI

/// A system alert can clip its warning at large accessibility sizes. Keep the
/// complete warning and every action in one scrollable, explicitly cancellable view.
struct NotificationConfirmationSheet<Actions: View>: View {
    let title: String
    var message = ""
    let cancel: () -> Void
    @ViewBuilder let actions: Actions

    init(title: String, message: String = "", cancel: @escaping () -> Void, @ViewBuilder actions: () -> Actions) {
        self.title = title; self.message = message; self.cancel = cancel; self.actions = actions()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    Text(title).font(.title2.bold()).foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !message.isEmpty {
                        AppEditorSectionCard {
                            Text(message).foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    actions
                }.padding(AppTheme.pageHorizontal).appCenteredContent()
            }
            .background(AppBackgroundView())
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                AppGlassIconButton(systemImage: "xmark", accessibilityLabel: AppStrings.Common.cancel, action: cancel)
            } }
        }.tint(AppTheme.accentPrimaryForeground).presentationDetents([.large])
    }
}

struct NotificationConfirmationAction: View {
    let title: String
    let id: String
    var role: ButtonRole? = nil
    let action: () -> Void
    @ViewBuilder
    var body: some View {
        if role == .cancel {
            button.buttonStyle(.bordered).tint(AppTheme.accentPrimaryForeground)
        } else {
            button.buttonStyle(.borderedProminent)
                .tint(role == .destructive ? AppTheme.accentDestructive : AppTheme.accentPrimary)
        }
    }
    private var button: some View {
        Button(role: role, action: action) {
            Text(title).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: AppTheme.minimumInteractiveTarget)
        }
        .controlSize(.large)
        .accessibilityIdentifier(id)
    }
}
