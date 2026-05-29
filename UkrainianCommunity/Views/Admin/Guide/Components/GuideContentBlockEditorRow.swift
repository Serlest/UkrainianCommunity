import SwiftUI

struct GuideContentBlockEditorRow: View {
    @Binding var block: GuideContentBlock
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SoftContentCard(padding: AppTheme.detailCardPadding) {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                header
                editorFields
            }
        }
    }

    private var header: some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            AppInfoChip(
                title: block.editorTitle,
                systemImage: block.editorSystemImage,
                tint: block.editorTint,
                fill: block.editorFill,
                size: .small
            )

            Spacer(minLength: AppTheme.eventsMetadataSpacing)

            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
            }
            .disabled(!canMoveUp)
            .accessibilityLabel(AppStrings.GuideEditor.moveBlockUp)

            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
            }
            .disabled(!canMoveDown)
            .accessibilityLabel(AppStrings.GuideEditor.moveBlockDown)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityLabel(AppStrings.GuideEditor.deleteBlock)
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var editorFields: some View {
        switch block {
        case .text:
            GuideTextContentBlockEditor(block: $block)
        case .steps:
            GuideStepsContentBlockEditor(block: $block)
        case .checklist:
            GuideChecklistContentBlockEditor(block: $block)
        case .links:
            GuideLinksContentBlockEditor(block: $block)
        case .contacts:
            GuideContactsContentBlockEditor(block: $block)
        case .warning, .infoBox:
            GuideMessageContentBlockEditor(block: $block)
        }
    }
}

private extension GuideContentBlock {
    var editorTitle: String {
        switch self {
        case .text:
            AppStrings.GuideEditor.blockTypeText
        case .warning:
            AppStrings.GuideEditor.blockTypeWarning
        case .infoBox:
            AppStrings.GuideEditor.blockTypeInfoBox
        case .steps:
            AppStrings.GuideEditor.blockTypeSteps
        case .checklist:
            AppStrings.GuideEditor.blockTypeChecklist
        case .links:
            AppStrings.GuideEditor.blockTypeLinks
        case .contacts:
            AppStrings.GuideEditor.blockTypeContacts
        }
    }

    var editorSystemImage: String {
        switch self {
        case .text:
            "text.alignleft"
        case .warning:
            "exclamationmark.triangle"
        case .infoBox:
            "info.circle"
        case .steps:
            "list.number"
        case .checklist:
            "checklist"
        case .links:
            "link"
        case .contacts:
            "person.crop.circle"
        }
    }

    var editorTint: Color {
        switch self {
        case .warning:
            AppTheme.accentDestructive
        default:
            AppTheme.accentPrimary
        }
    }

    var editorFill: Color {
        switch self {
        case .warning:
            AppTheme.badgeRedFill
        default:
            AppTheme.badgeBlueFill
        }
    }
}
