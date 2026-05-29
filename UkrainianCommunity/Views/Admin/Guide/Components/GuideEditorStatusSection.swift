import SwiftUI

struct GuideEditorStatusSection: View {
    @ObservedObject var viewModel: GuideEditorViewModel
    let statusMessage: String?

    var body: some View {
        if !viewModel.validationMessages.isEmpty || statusMessage != nil || viewModel.saveStatusMessage != nil {
            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    if let statusMessage {
                        Label(statusMessage, systemImage: "info.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.accentPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let saveStatusMessage = viewModel.saveStatusMessage {
                        Label(saveStatusMessage, systemImage: saveStatusSystemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(saveStatusTint)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(viewModel.validationMessages, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.accentDestructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var saveStatusSystemImage: String {
        switch viewModel.saveState {
        case .idle:
            "info.circle"
        case .saving:
            "clock"
        case .saved:
            "checkmark.circle"
        case .failed:
            "exclamationmark.circle"
        }
    }

    private var saveStatusTint: Color {
        switch viewModel.saveState {
        case .idle, .saving:
            AppTheme.accentPrimary
        case .saved:
            Color.green
        case .failed:
            AppTheme.accentDestructive
        }
    }
}
