import SwiftUI

struct GuideStepsBlockView: View {
    let block: GuideContentBlock.StepsBlock

    private var steps: [String] {
        block.steps.guideNonBlankValues
    }

    var body: some View {
        if !steps.isEmpty {
            DetailCard {
                GuideBlockTitleView(title: block.title)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        numberedRow(number: index + 1, text: step)
                    }
                }
            }
        }
    }

    private func numberedRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 24, height: 24)
                .background(AppTheme.badgeBlueFill, in: Circle())

            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
