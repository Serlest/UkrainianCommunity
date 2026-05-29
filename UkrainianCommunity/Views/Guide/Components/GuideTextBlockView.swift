import SwiftUI

struct GuideTextBlockView: View {
    let block: GuideContentBlock.TextBlock

    var body: some View {
        if !block.text.guideIsBlank {
            DetailCard {
                GuideBlockTitleView(title: block.title)

                Text(block.text)
                    .font(AppTheme.detailBodyFont)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineSpacing(AppTheme.detailBodyLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
