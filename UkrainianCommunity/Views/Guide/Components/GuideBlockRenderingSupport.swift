import SwiftUI

struct GuideBlockTitleView: View {
    let title: String?

    var body: some View {
        if let title, !title.guideIsBlank {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension String {
    var guideIsBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension Array where Element == String {
    var guideNonBlankValues: [String] {
        map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
