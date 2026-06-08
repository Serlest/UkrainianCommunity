import SwiftUI

struct AppErrorDialog: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let okTitle: String

    init(
        title: String = AppStrings.Dialogs.errorTitle,
        message: String,
        okTitle: String = AppStrings.Common.ok
    ) {
        self.title = title
        self.message = message
        self.okTitle = okTitle
    }
}

struct AppSuccessDialog: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let okTitle: String

    init(
        title: String = AppStrings.Dialogs.successTitle,
        message: String,
        okTitle: String = AppStrings.Common.ok
    ) {
        self.title = title
        self.message = message
        self.okTitle = okTitle
    }
}

struct AppDestructiveActionDialog {
    let title: String
    let message: String
    let destructiveActionTitle: String
    let cancelTitle: String
    let action: () -> Void

    init(
        title: String,
        message: String,
        destructiveActionTitle: String,
        cancelTitle: String = AppStrings.Common.cancel,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.destructiveActionTitle = destructiveActionTitle
        self.cancelTitle = cancelTitle
        self.action = action
    }
}

struct AppGuestAccessDialog {
    let action: GuestAccessAction

    var title: String { AppStrings.Auth.requiredTitle }
    var message: String { AppStrings.authRequiredMessage(for: action.capabilityTitle) }
    var signInTitle: String { AppStrings.Auth.signIn }
    var createAccountTitle: String { AppStrings.Auth.createAccount }
    var dismissTitle: String { AppStrings.Common.ok }
}

extension View {
    func appErrorDialog(_ dialog: Binding<AppErrorDialog?>) -> some View {
        alert(
            dialog.wrappedValue?.title ?? AppStrings.Dialogs.errorTitle,
            isPresented: appDialogIsPresented(dialog),
            presenting: dialog.wrappedValue
        ) { currentDialog in
            Button(currentDialog.okTitle, role: .cancel) {
                dialog.wrappedValue = nil
            }
        } message: { currentDialog in
            Text(currentDialog.message)
        }
    }

    func appSuccessDialog(_ dialog: Binding<AppSuccessDialog?>) -> some View {
        alert(
            dialog.wrappedValue?.title ?? AppStrings.Dialogs.successTitle,
            isPresented: appDialogIsPresented(dialog),
            presenting: dialog.wrappedValue
        ) { currentDialog in
            Button(currentDialog.okTitle, role: .cancel) {
                dialog.wrappedValue = nil
            }
        } message: { currentDialog in
            Text(currentDialog.message)
        }
    }

    func appDestructiveActionDialog(_ dialog: Binding<AppDestructiveActionDialog?>) -> some View {
        confirmationDialog(
            dialog.wrappedValue?.title ?? "",
            isPresented: appDialogIsPresented(dialog),
            titleVisibility: .visible
        ) {
            if let currentDialog = dialog.wrappedValue {
                Button(currentDialog.destructiveActionTitle, role: .destructive) {
                    let action = currentDialog.action
                    dialog.wrappedValue = nil
                    action()
                }

                Button(currentDialog.cancelTitle, role: .cancel) {
                    dialog.wrappedValue = nil
                }
            }
        } message: {
            if let currentDialog = dialog.wrappedValue {
                Text(currentDialog.message)
            }
        }
    }
}

private func appDialogIsPresented<Dialog>(_ dialog: Binding<Dialog?>) -> Binding<Bool> {
    Binding(
        get: { dialog.wrappedValue != nil },
        set: { isPresented in
            if !isPresented {
                dialog.wrappedValue = nil
            }
        }
    )
}
