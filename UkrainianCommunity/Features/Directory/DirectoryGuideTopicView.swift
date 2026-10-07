import SwiftUI

struct DirectoryGuideTopicView: View {
    let categoryID: String
    let topic: DirectoryTopic
    let guide: DirectoryGuide
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
                Text(topic.title.value(for: language))
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                Text(guide.introduction.value(for: language))
                    .foregroundStyle(AppTheme.textSecondary)

                ForEach(guide.sections) { section in
                    AppGlassCard {
                        Label(section.title.value(for: language), systemImage: section.symbol)
                            .font(.headline)
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(section.body.value(for: language))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let number = section.phoneNumber,
                           let url = URL(string: "tel:\(number.replacingOccurrences(of: " ", with: ""))") {
                            Link(destination: url) {
                                Label("BBU · \(number)", systemImage: "phone.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .accessibilityIdentifier("directory.call.bbu")
                        }
                    }
                }

                if categoryID == "first-steps" {
                    NavigationLink(value: DirectoryRoute.category("registration")) {
                        Label(DirectoryText(ukrainian: "Детально про реєстрацію", german: "Mehr zur Anmeldung").value(for: language),
                              systemImage: "arrow.right.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .appGlassCard()
                    }
                    .buttonStyle(.plain)
                }

                DirectorySourceListView(
                    sources: guide.sources,
                    language: language,
                    checkedOn: DirectoryGuideCatalog.checkedOn
                )
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.top, AppTheme.homeSectionSpacing)
            .padding(.bottom, AppTheme.homeBottomContentPadding)
            .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
        }
        .background(AppBackgroundView())
        .navigationTitle(topic.title.value(for: language))
        .navigationBarTitleDisplayMode(.inline)
    }
}
