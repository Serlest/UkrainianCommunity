import SwiftUI

enum QuickCreationKind: String, Identifiable {
    case news, event
    var id: String { rawValue }
    var title: String { self == .news ? AppStrings.Profile.createNews : AppStrings.Events.editorTitle }
}

struct QuickCreationActions {
    var news: (() -> Void)?
    var event: (() -> Void)?
    func action(for kind: QuickCreationKind) -> (() -> Void)? { kind == .news ? news : event }
}

private struct QuickCreationActionsKey: EnvironmentKey {
    static let defaultValue = QuickCreationActions()
}

extension EnvironmentValues {
    var quickCreationActions: QuickCreationActions {
        get { self[QuickCreationActionsKey.self] }
        set { self[QuickCreationActionsKey.self] = newValue }
    }
}

struct QuickCreationButton: View {
    @Environment(\.quickCreationActions) private var actions
    let kind: QuickCreationKind

    var body: some View {
        if let action = actions.action(for: kind) {
            AppGlassIconButton(systemImage: "plus", accessibilityLabel: kind.title, action: action)
                .accessibilityIdentifier("quickCreate.\(kind.rawValue)")
        }
    }
}
