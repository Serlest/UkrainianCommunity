import SwiftUI

struct DirectoryGuideSectionCard: View {
    let section: DirectoryGuideSection
    let language: AppLanguage
    var compactBody: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: section.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 11))
                    .accessibilityHidden(true)
                Text(section.title.value(for: language))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            DirectoryGuideBodyView(text: section.body.value(for: language), compact: compactBody)
            if let source = section.source {
                Divider()
                Link(destination: source.url) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "arrow.up.right.square")
                        Text(source.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.subheadline.weight(.medium))
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
        .padding(16)
        .appGlassCard(material: .regularMaterial)
    }
}
