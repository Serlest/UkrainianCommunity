import SwiftUI

/// Keeps a directory request linked to the section or article that prompted it.
struct DirectoryFeedbackView: View {
    enum Kind {
        case question(categoryID: String?, title: String)
        case correction(categoryID: String, topicID: String, title: String)

        var type: FeedbackType { switch self { case .question: .question; case .correction: .report } }
        func subject(_ language: AppLanguage) -> String {
            switch self {
            case let .question(categoryID, title):
                let prefix = DirectoryText(ukrainian: "Довідник · питання", german: "Wegweiser · Frage").value(for: language)
                return "\(prefix) · \(categoryID ?? "home") · \(title)"
            case let .correction(categoryID, topicID, title):
                let prefix = DirectoryText(ukrainian: "Довідник · неточність", german: "Wegweiser · Unstimmigkeit").value(for: language)
                return "\(prefix) · \(categoryID)/\(topicID) · \(title)"
            }
        }
        func title(_ language: AppLanguage) -> String {
            switch self {
            case .question: DirectoryText(ukrainian: "Поставити запитання", german: "Frage stellen").value(for: language)
            case .correction: DirectoryText(ukrainian: "Повідомити про неточність", german: "Unstimmigkeit melden").value(for: language)
            }
        }
        func explanation(_ language: AppLanguage) -> String {
            switch self {
            case .question:
                DirectoryText(ukrainian: "Не знайшли відповіді? Напишіть нам. Команда перевірить офіційні джерела, поглибить тему й додасть відповідь до довідника. Статус запиту можна переглянути тут.", german: "Keine Antwort gefunden? Schreiben Sie uns. Unser Team prüft offizielle Quellen, vertieft das Thema und ergänzt den Wegweiser. Den Status sehen Sie hier.").value(for: language)
            case .correction:
                DirectoryText(ukrainian: "Помітили застарілу або неправильну інформацію? Опишіть, що саме потрібно перевірити. Ми розглянемо повідомлення та покажемо його статус.", german: "Veraltete oder falsche Information entdeckt? Beschreiben Sie, was geprüft werden soll. Wir prüfen Ihre Meldung und zeigen ihren Status.").value(for: language)
            }
        }
    }

    @EnvironmentObject private var authState: AuthState
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    let kind: Kind
    let repository: FeedbackRepository
    @State private var showingComposer = false
    @State private var showingHistory = false
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }

    var body: some View {
        AppGlassCard {
            Label(kind.title(language), systemImage: kind.type == .question ? "questionmark.bubble" : "exclamationmark.bubble")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            Text(kind.explanation(language))
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if authState.user == nil { authState.presentAuthFlow(.login) }
                else { showingComposer = true }
            } label: {
                Label(kind.title(language), systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("directory.feedback.compose")
            if authState.user != nil {
                Button {
                    showingHistory = true
                } label: {
                    Label(DirectoryText(ukrainian: "Мої звернення та їхній статус", german: "Meine Anfragen und ihr Status").value(for: language), systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("directory.feedback.status")
            }
        }
        .sheet(isPresented: $showingComposer) {
            DirectoryFeedbackComposer(kind: kind, repository: repository)
                .environmentObject(authState)
        }
        .sheet(isPresented: $showingHistory) {
            if let user = authState.user {
                DirectoryFeedbackHistory(repository: repository, userID: user.id)
                .environmentObject(authState)
            }
        }
    }
}

private struct DirectoryFeedbackHistory: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MyFeedbackViewModel
    let userID: String

    init(repository: FeedbackRepository, userID: String) {
        _viewModel = StateObject(wrappedValue: MyFeedbackViewModel(repository: repository))
        self.userID = userID
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(AppStrings.Common.done) { dismiss() }
                    .padding(AppTheme.pageHorizontal)
            }
            NavigationStack {
                MyFeedbackView(viewModel: viewModel, currentUserID: userID)
            }
        }
    }
}

private struct DirectoryFeedbackComposer: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    let kind: DirectoryFeedbackView.Kind
    let repository: FeedbackRepository
    @State private var message = ""
    @State private var isSending = false
    @State private var error: String?
    @State private var sent = false
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }
    private var trimmed: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
                    if sent {
                        Label(DirectoryText(ukrainian: "Дякуємо за звернення!", german: "Vielen Dank für Ihre Nachricht!").value(for: language), systemImage: "checkmark.circle.fill")
                            .font(.title3.bold())
                        Text(DirectoryText(ukrainian: "Ми отримали його. Статус можна відстежувати у «Моїх зверненнях». Після перевірки ми доповнимо або виправимо матеріал.", german: "Wir haben Ihre Nachricht erhalten. Den Status finden Sie unter „Meine Anfragen“. Nach der Prüfung ergänzen oder korrigieren wir den Beitrag.").value(for: language))
                            .font(.body)
                    } else {
                        Text(kind.explanation(language))
                            .font(.body)
                            .foregroundStyle(AppTheme.textSecondary)
                        Text(kind.subject(language))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                        TextEditor(text: $message)
                            .frame(minHeight: 150)
                            .padding(8)
                            .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("directory.feedback.message")
                        Text("\(trimmed.count)/2000")
                            .font(.caption)
                            .foregroundStyle(trimmed.count > 2000 ? AppTheme.accentDestructiveForeground : AppTheme.textSecondary)
                        if let error { InlineMessageCard(style: .error, message: error) }
                        PrimaryActionButton(title: AppStrings.Feedback.submit, isEnabled: !isSending && !trimmed.isEmpty && trimmed.count <= 2000, isLoading: isSending, systemImage: "paperplane") {
                            Task { await submit() }
                        }
                    }
                }
                .padding(AppTheme.pageHorizontal)
                .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
            }
            .background(AppBackgroundView())
            .navigationTitle(kind.title(language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(AppStrings.Common.done) { dismiss() } } }
        }
    }

    private func submit() async {
        guard let user = authState.user, !isSending, !trimmed.isEmpty, trimmed.count <= 2000 else { return }
        isSending = true
        error = nil
        let now = Date()
        let item = FeedbackItem(id: UUID().uuidString, type: kind.type, subject: kind.subject(language),
            message: trimmed, status: .open, createdAt: now, updatedAt: now,
            userId: user.id, userDisplayName: user.preferredDisplayName,
            ownerReply: nil, repliedAt: nil, repliedByUserId: nil,
            lastMessageText: trimmed, lastMessageAt: now, lastMessageByUserId: user.id,
            lastMessageByRole: .user, unreadForOwner: true, unreadForUser: false)
        do {
            try await repository.submitFeedback(item)
            sent = true
        } catch {
            self.error = DirectoryText(ukrainian: "Не вдалося надіслати. Перевірте з’єднання та повторіть спробу.", german: "Senden fehlgeschlagen. Prüfen Sie die Verbindung und versuchen Sie es erneut.").value(for: language)
        }
        isSending = false
    }
}
