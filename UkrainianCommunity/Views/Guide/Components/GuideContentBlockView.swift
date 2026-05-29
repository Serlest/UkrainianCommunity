import SwiftUI

struct GuideContentBlockView: View {
    let block: GuideContentBlock

    var body: some View {
        switch block {
        case .text(let block):
            GuideTextBlockView(block: block)
        case .steps(let block):
            GuideStepsBlockView(block: block)
        case .checklist(let block):
            GuideChecklistBlockView(block: block)
        case .warning(let block):
            GuideMessageBlockView(
                block: block,
                systemImage: "exclamationmark.triangle.fill",
                tint: AppTheme.accentDestructive,
                fill: AppTheme.badgeRedFill
            )
        case .infoBox(let block):
            GuideMessageBlockView(
                block: block,
                systemImage: "info.circle.fill",
                tint: AppTheme.accentPrimary,
                fill: AppTheme.badgeBlueFill
            )
        case .links(let block):
            GuideLinksBlockView(block: block)
        case .contacts(let block):
            GuideContactBlockView(block: block)
        }
    }
}
