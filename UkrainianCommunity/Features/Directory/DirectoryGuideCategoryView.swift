import SwiftUI

struct DirectoryGuideCategoryView: View {
    let category: DirectoryCategory
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }
    private var groups: [DirectoryTopicGroup] { DirectoryTopicGroups.forCategory(category) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
                DirectoryPageHeading(title: category.title.value(for: language),
                                     summary: category.summary.value(for: language),
                                     symbol: category.symbol)

                if category.id == "safety" { emergencyCard }
                if category.id == "health" { healthHelpCard }
                if category.id == "mental-health" { mentalHealthHelpCard }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        if groups.count > 1 {
                            Text(group.title.value(for: language))
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                        AppGlassCard(padding: 0, spacing: 0) {
                            ForEach(Array(group.topicIDs.enumerated()), id: \.element) { index, topicID in
                                if let topic = category.topics.first(where: { $0.id == topicID }) {
                                    if index > 0 { Divider().padding(.leading, 56) }
                                    topicLink(topic)
                                }
                            }
                        }
                    }
                }
                if category.id == "first-steps" { firstStepsNext }
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.top, AppTheme.homeSectionSpacing)
            .padding(.bottom, AppTheme.homeBottomContentPadding)
            .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
        }
        .background(AppBackgroundView())
        .navigationTitle("")
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

    private var healthHelpCard: some View {
        AppGlassCard {
            Label(DirectoryText(ukrainian: "Потрібна допомога зараз?", german: "Brauchen Sie jetzt Hilfe?").value(for: language),
                  systemImage: "cross.case.fill")
                .font(.headline)
            Text(DirectoryText(
                ukrainian: "Загроза життю — швидка 144. Не впевнені, куди звернутися з проблемою здоров’я — медична консультація 1450.",
                german: "Lebensgefahr: Rettung 144. Unklar, wohin mit einem Gesundheitsproblem? Gesundheitsberatung 1450."
            ).value(for: language))
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
            SafetyCallButton(contact: DirectorySafetyContent.ambulance, language: language)
            SafetyCallButton(contact: HealthGuides.healthAdvice, language: language)
        }
    }

    private var mentalHealthHelpCard: some View {
        AppGlassCard {
            Label(DirectoryText(ukrainian: "Потрібна допомога зараз?", german: "Brauchen Sie jetzt Hilfe?").value(for: language),
                  systemImage: "heart.text.square.fill")
                .font(.headline)
            Text(DirectoryText(
                ukrainian: "Якщо є безпосередня небезпека — 144. Для анонімної розмови цілодобово — 142; дітям і підліткам — 147.",
                german: "Bei unmittelbarer Gefahr 144. Für ein anonymes Gespräch rund um die Uhr 142; für Kinder und Jugendliche 147."
            ).value(for: language))
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
            SafetyCallButton(contact: DirectorySafetyContent.ambulance, language: language)
            SafetyCallButton(contact: DirectorySafetyContent.crisis, language: language)
            SafetyCallButton(contact: DirectorySafetyContent.children, language: language)
        }
    }

    private func topicLink(_ topic: DirectoryTopic) -> some View {
        let guide = DirectoryGuideCatalog.guide(categoryID: category.id, topicID: topic.id)
        let safetyGuide = DirectorySafetyContent.guides[topic.id]
        return NavigationLink(value: DirectoryRoute.topic(categoryID: category.id, topicID: topic.id)) {
            HStack(spacing: 12) {
                Image(systemName: guide?.sections.first?.symbol ?? safetyGuide?.sections.first?.symbol ?? category.symbol)
                    .font(.body)
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(topic.title.value(for: language))
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: AppTheme.minimumInteractiveTarget)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("directory.topic.\(topic.id)")
    }

    private var firstStepsNext: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(DirectoryText(ukrainian: "Далі за вашою ситуацією", german: "Danach, je nach Situation").value(for: language))
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            AppGlassCard(padding: 0, spacing: 0) {
                ForEach(Array(["registration", "housing", "social-support", "insurance", "education", "work"].enumerated()), id: \.element) { index, id in
                    if let destination = DirectoryCatalog.categories.first(where: { $0.id == id }) {
                        if index > 0 { Divider().padding(.leading, 56) }
                        NavigationLink(value: DirectoryRoute.category(id)) {
                            HStack(spacing: 12) {
                                Image(systemName: destination.symbol)
                                    .font(.body)
                                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                                    .frame(width: 24)
                                Text(destination.title.value(for: language))
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .frame(minHeight: AppTheme.minimumInteractiveTarget)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
