import SwiftUI

struct AnnouncementPopup: View {
    let item: UserAnnouncement
    @ObservedObject var coordinator: AnnouncementCoordinator
    let feedback: (UserAnnouncement) -> Void
    @State private var busy = false
    var body: some View {
        NavigationStack {
            EditorScreenShell(title: AnnouncementStrings.history, closeStyle: .cancel,
                              closeAction: { Task { await coordinator.close(item, acknowledge: false) } }) {
                AnnouncementSection {
                    Text(item.title.localized()).font(.title2.bold())
                    Text(item.body.localized()).textSelection(.enabled)
                    if let error = coordinator.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                    if item.feedback {
                        Button(AnnouncementStrings.writeFeedback) {
                            busy = true
                            Task { await coordinator.mark(item, event: "action"); await coordinator.close(item, acknowledge: false); feedback(item) }
                        }.appActionButtonStyle(.primary)
                    }
                    if item.mode == "acknowledge" {
                        Button(AnnouncementStrings.ack) { busy = true; Task { await coordinator.close(item, acknowledge: true) } }
                            .appActionButtonStyle(.primary).accessibilityIdentifier("announcements.acknowledge")
                    }
                    Button(item.mode == "acknowledge" ? AnnouncementStrings.later : AnnouncementStrings.close) {
                        Task { await coordinator.close(item, acknowledge: false) }
                    }.appActionButtonStyle(.secondary).accessibilityIdentifier("announcements.close")
                }
            }.navigationTitle(AnnouncementStrings.history).navigationBarTitleDisplayMode(.inline)
        }
        .disabled(busy)
        .interactiveDismissDisabled()
        .task { await coordinator.didPresent(item) }
        .accessibilityIdentifier("screen.announcements.popup")
    }
}

struct AnnouncementHistoryView: View {
    @EnvironmentObject private var authState: AuthState
    @AppStorage("announcements.guestPushEnabled") private var guestPushEnabled = false
    @ObservedObject var coordinator: AnnouncementCoordinator
    var body: some View {
        ProfileDestinationLayout(title: AnnouncementStrings.history, introSubtitle: AnnouncementStrings.subtitle) {
            if let error = coordinator.error { InlineMessageCard(style: .error, message: error) }
            if coordinator.isLoading { ProgressView() }
            if authState.isGuest {
                Toggle(AnnouncementStrings.guestPush, isOn: $guestPushEnabled)
                    .onChange(of: guestPushEnabled) { _, enabled in Task {
                        if enabled { await AnnouncementPushBridge.shared.requestPermission() }
                        else { await AnnouncementPushBridge.shared.disableGuestPush() }
                    } }
                Text(AnnouncementStrings.guestPushHelp).font(.caption)
            }
            if coordinator.items.isEmpty && !coordinator.isLoading { Text(AnnouncementStrings.empty) }
            ForEach(coordinator.items) { item in
                NavigationLink {
                    ProfileDestinationLayout(title: AnnouncementStrings.history, introSubtitle: "") { AnnouncementSection {
                        Text(item.title.localized()).font(.title2.bold())
                        Text(item.body.localized()).textSelection(.enabled)
                        if item.feedback && item.active(at: coordinator.now) {
                            Button(AnnouncementStrings.writeFeedback) { Task {
                                await coordinator.mark(item, event: "action")
                                coordinator.requestedFeedback = item
                            } }
                        }
                        if item.mode == "acknowledge" && !coordinator.isAcknowledged(item) && item.active(at: coordinator.now) {
                            Button(AnnouncementStrings.ack) { Task { await coordinator.mark(item, event: "acknowledged"); await coordinator.refresh() } }
                        }
                    } }.navigationTitle(AnnouncementStrings.history)
                } label: {
                    AnnouncementSection {
                        Text(item.title.localized()).font(.headline)
                        Text(Date(timeIntervalSince1970: item.startsAt / 1000), style: .date).font(.caption)
                    }
                }
            }
        }.navigationTitle(AnnouncementStrings.history)
            .task { await coordinator.refresh() }.refreshable { await coordinator.refresh() }
            .accessibilityIdentifier("screen.announcements.history")
    }
}

struct AnnouncementFeedbackView: View {
    let item: UserAnnouncement
    let user: AppUser
    @ObservedObject var viewModel: ProfileViewModel
    @State private var message = ""
    @State private var type: FeedbackType = .question
    var body: some View {
        ProfileFeedbackComposerView(selectedFeedbackType: $type, feedbackMessage: $message,
            statusMessage: viewModel.feedbackMessage, isSubmitting: viewModel.isSubmittingFeedback,
            onSubmit: { Task {
                if await viewModel.submitFeedback(type: type, message: message, user: user, subject: "[UAC \(item.id)] \(item.title.localized())") { message = "" }
            } })
    }
}
