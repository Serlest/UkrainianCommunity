import SwiftUI

struct DirectoryGuideCategoryView: View {
    let category: DirectoryCategory
    let feedbackRepository: FeedbackRepository
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
                DirectoryPageHeading(title: category.title.value(for: language),
                                     summary: category.summary.value(for: language),
                                     symbol: category.symbol)

                if category.id == "safety" { emergencyCard }
                DirectoryFeedbackView(kind: .question(categoryID: category.id, title: category.title.value(for: language)), repository: feedbackRepository)

                ForEach(DirectoryTopicGroups.forCategory(category)) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.title.value(for: language))
                            .font(.title3.bold())
                            .foregroundStyle(AppTheme.textPrimary)
                        ForEach(group.topicIDs, id: \.self) { topicID in
                            if let topic = category.topics.first(where: { $0.id == topicID }) {
                                topicLink(topic)
                            }
                        }
                    }
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

    private var emergencyCard: some View {
        AppGlassCard {
            Label(DirectoryText(ukrainian: "Небезпека зараз?", german: "Akute Gefahr?").value(for: language),
                  systemImage: "exclamationmark.shield.fill")
                .font(.headline)
            Text(DirectoryText(
                ukrainian: "Якщо не знаєте, яку службу викликати, телефонуйте 112. При загрозі насильства — поліції 133.",
                german: "Wenn unklar ist, welche Stelle zuständig ist, wählen Sie 112. Bei drohender Gewalt: Polizei 133."
            ).value(for: language))
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
            SafetyCallButton(contact: DirectorySafetyContent.europeanEmergency, language: language)
            SafetyCallButton(contact: DirectorySafetyContent.police, language: language)
        }
    }

    private func topicLink(_ topic: DirectoryTopic) -> some View {
        let guide = DirectoryGuideCatalog.guide(categoryID: category.id, topicID: topic.id)
        let safetyGuide = DirectorySafetyContent.guides[topic.id]
        return NavigationLink(value: DirectoryRoute.topic(categoryID: category.id, topicID: topic.id)) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: guide?.sections.first?.symbol ?? safetyGuide?.sections.first?.symbol ?? category.symbol)
                    .font(.title3)
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(topic.title.value(for: language))
                        .font(AppTheme.cardTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                    if let summary = guide?.cardSummary ?? safetyGuide?.summary {
                        Text(summary.value(for: language))
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .appGlassCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("directory.topic.\(topic.id)")
    }
}
