import SwiftUI

struct DirectoryGuideSectionCard: View {
    let section: DirectoryGuideSection
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: section.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                Text(section.title.value(for: language))
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            DirectoryGuideBodyView(text: section.body.value(for: language))
            if let source = section.source {
                Link(destination: source.url) {
                    Label(source.name, systemImage: "arrow.up.right.square")
                        .font(.footnote.weight(.semibold))
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Divider() }
    }
}
