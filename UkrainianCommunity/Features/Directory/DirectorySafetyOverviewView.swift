import SwiftUI

struct DirectorySafetyOverviewView: View {
    let category: DirectoryCategory
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
                Text(category.title.value(for: language))
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                Text(category.summary.value(for: language))
                    .foregroundStyle(AppTheme.textSecondary)

                AppGlassCard {
                    Label(text("Небезпека зараз?", "Akute Gefahr?"), systemImage: "exclamationmark.shield.fill")
                        .font(.headline)
                    Text(text("Якщо не знаєте, яку службу викликати, телефонуйте 112. При загрозі насильства — поліції 133.",
                              "Wenn unklar ist, welche Stelle zuständig ist, wählen Sie 112. Bei drohender Gewalt: Polizei 133."))
                        .foregroundStyle(AppTheme.textSecondary)
                    SafetyCallButton(contact: DirectorySafetyContent.europeanEmergency, language: language)
                    SafetyCallButton(contact: DirectorySafetyContent.police, language: language)
                }

                Text(text("Теми", "Themen"))
                    .font(.title3.bold())
                ForEach(category.topics) { topic in
                    NavigationLink(value: DirectoryRoute.topic(categoryID: category.id, topicID: topic.id)) {
                        HStack(spacing: 12) {
                            Text(topic.title.value(for: language))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .padding(16)
                        .appGlassCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("directory.topic.\(topic.id)")
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.top, AppTheme.homeSectionSpacing)
            .padding(.bottom, AppTheme.homeBottomContentPadding)
            .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
        }
        .background(AppBackgroundView())
        .navigationTitle(category.title.value(for: language))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func text(_ uk: String, _ de: String) -> String {
        DirectoryText(ukrainian: uk, german: de).value(for: language)
    }
}
