import SwiftUI

struct GuideCategoryManagementActionPanel: View {
    let onAddRootNode: () -> Void

    var body: some View {
        AppEditorSectionCard {
            HStack {
                Button(GuideAuthoringPresentation.createSection, action: onAddRootNode)
                    .appActionButtonStyle(.primary)

                Spacer(minLength: 0)
            }
        }
    }
}

func readableDeleteMessage(for error: AppError) -> String {
    switch error {
    case .permissionDenied:
        return GuideAuthoringPresentation.deletePermissionDenied
    case .notFound:
        return GuideAuthoringPresentation.localized(
            uk: "Елемент уже не існує.",
            de: "Dieses Element existiert nicht mehr.",
            en: "This item no longer exists."
        )
    case .network:
        return GuideAuthoringPresentation.localized(
            uk: "Помилка мережі. Спробуйте ще раз.",
            de: "Netzwerkfehler. Bitte versuchen Sie es erneut.",
            en: "Network error. Please try again."
        )
    case .validationFailed:
        return GuideAuthoringPresentation.deleteSectionBlockedMessage
    case .unknown:
        return GuideAuthoringPresentation.deleteUnknownError
    }
}
