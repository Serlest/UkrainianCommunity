import SwiftUI

struct GuideChecklistBlockView: View {
    let block: GuideContentBlock.ChecklistBlock

    private var items: [String] {
        block.items.guideNonBlankValues
    }

    var body: some View {
        if !items.isEmpty {
            DetailCard {
                GuideBlockTitleView(title: block.title)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        checklistRow(item)
                    }
                }
            }
        }
    }

    private func checklistRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 24, height: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
