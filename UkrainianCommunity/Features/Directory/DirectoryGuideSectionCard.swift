import SwiftUI

struct DirectoryGuideSectionCard: View {
    let section: DirectoryGuideSection
    let language: AppLanguage

    var body: some View {
        AppGlassCard {
            Label(section.title.value(for: language), systemImage: section.symbol)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            DirectoryGuideBodyView(text: section.body.value(for: language))
            if let source = section.source {
                Link(destination: source.url) {
                    Label(source.name, systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityIdentifier("directory.source.\(section.id)")
            }
            if let number = section.phoneNumber,
               let url = URL(string: "tel:\(number.replacingOccurrences(of: " ", with: ""))") {
                Link(destination: url) {
                    Label(number, systemImage: "phone.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityIdentifier("directory.call.\(section.id)")
            }
        }
    }
}
