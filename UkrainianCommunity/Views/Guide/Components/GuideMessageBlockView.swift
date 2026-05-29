import SwiftUI

struct GuideMessageBlockView: View {
    let block: GuideContentBlock.MessageBlock
    let systemImage: String
    let tint: Color
    let fill: Color

    var body: some View {
        if !block.message.guideIsBlank {
            DetailCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 30, height: 30)
                        .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        GuideBlockTitleView(title: block.title)

                        Text(block.message)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
