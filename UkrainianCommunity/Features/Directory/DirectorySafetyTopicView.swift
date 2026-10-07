import SwiftUI

struct DirectorySafetyTopicView: View {
    let topic: DirectoryTopic
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }
    private var isEmergency: Bool { topic.id == "emergency" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
                Text(topic.title.value(for: language))
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                Text(isEmergency
                     ? text("Короткі дії та важливі номери для екстрених ситуацій в Австрії.", "Schnelle Schritte und wichtige Nummern für Notfälle in Österreich.")
                     : text("Допомога при насильстві вдома або з боку близької людини.", "Hilfe bei Gewalt zu Hause oder durch eine nahestehende Person."))
                    .foregroundStyle(AppTheme.textSecondary)

                if isEmergency { emergencyContent } else { violenceContent }
                DirectorySourceListView(
                    sources: isEmergency
                        ? [DirectorySafetyContent.emergencySource]
                        : [DirectorySafetyContent.violenceSource, DirectorySafetyContent.supportSource],
                    language: language,
                    checkedOn: DirectorySafetyContent.reviewedOn
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

    private var emergencyContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
            SafetyInfoCard(title: text("Кого викликати", "Wen anrufen"), symbol: "phone.fill") {
                ForEach([DirectorySafetyContent.police, DirectorySafetyContent.ambulance,
                         DirectorySafetyContent.fire, DirectorySafetyContent.europeanEmergency]) { contact in
                    SafetyCallButton(contact: contact, language: language)
                }
            }
            SafetyInfoCard(title: text("Під час дзвінка", "Beim Anruf"), symbol: "text.bubble.fill") {
                Text(text("Назвіть точну адресу або місце, що сталося, скільки людей потребують допомоги та чи є безпосередня небезпека. Залишайтеся на лінії й виконуйте вказівки диспетчера.",
                          "Nennen Sie den genauen Ort, was passiert ist, wie viele Menschen Hilfe brauchen und ob unmittelbare Gefahr besteht. Bleiben Sie am Telefon und folgen Sie den Anweisungen."))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Text(text("Екстрені номери безкоштовні. Для дзвінка на 112 в Австрії не потрібен PIN-код.",
                      "Notrufnummern sind kostenlos. Die 112 ist in Österreich auch ohne PIN-Code erreichbar."))
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var violenceContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
            SafetyInfoCard(title: text("Якщо загроза зараз", "Bei akuter Gefahr"), symbol: "exclamationmark.shield.fill") {
                Text(text("Перейдіть у безпечне місце, якщо можете. Зателефонуйте до поліції за номером 133 або на 112. Якщо говорити небезпечно, скористайтеся безпечним для вас способом звернутися по допомогу.",
                          "Gehen Sie, wenn möglich, an einen sicheren Ort. Rufen Sie die Polizei unter 133 oder den Euro-Notruf 112. Wenn Sprechen gefährlich ist, nutzen Sie einen für Sie sicheren Weg, Hilfe zu holen."))
                    .foregroundStyle(AppTheme.textSecondary)
                SafetyCallButton(contact: DirectorySafetyContent.police, language: language)
                SafetyCallButton(contact: DirectorySafetyContent.europeanEmergency, language: language)
            }
            SafetyInfoCard(title: text("Підтримка та захист", "Beratung und Schutz"), symbol: "hand.raised.heart.fill") {
                Text(text("Можна звернутися по пораду, навіть якщо ви ще не вирішили, що робити далі. Фахівці допоможуть знайти підтримку й безпечне місце.",
                          "Sie können sich beraten lassen, auch wenn Sie noch nicht wissen, wie es weitergeht. Fachstellen helfen bei der Suche nach Unterstützung und Schutz."))
                    .foregroundStyle(AppTheme.textSecondary)
                SafetyCallButton(contact: DirectorySafetyContent.womenHelpline, language: language)
                SafetyCallButton(contact: DirectorySafetyContent.protectionCentre, language: language)
            }
            Text(text("Якщо хтось контролює ваш телефон, відкривайте посилання та телефонуйте з пристрою, яким можете безпечно користуватися.",
                      "Wenn jemand Ihr Telefon kontrolliert, nutzen Sie Links und Anrufe nur über ein Gerät, das Sie sicher verwenden können."))
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func text(_ uk: String, _ de: String) -> String {
        DirectoryText(ukrainian: uk, german: de).value(for: language)
    }
}
