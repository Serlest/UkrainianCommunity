import SwiftUI

struct AnnouncementOwnerView: View {
    let repository: any AnnouncementRepository
    @EnvironmentObject private var authState: AuthState
    @State private var items: [UserAnnouncement] = []
    @State private var cursor: String?
    @State private var editor: UserAnnouncement?
    @State private var error: String?
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var filter = "all"
    @State private var generation = 0
    @State private var loadedFilter = "all"
    @State private var pendingFilter: String?
    @State private var failedMore = false
    private let phases = ["draft", "scheduled", "active", "completed", "cancelled"]
    var body: some View {
        ProfileDestinationLayout(title: AnnouncementStrings.title, introSubtitle: AnnouncementStrings.subtitle) {
            Button(AnnouncementStrings.create, systemImage: "plus") { editor = UserAnnouncement() }
                .appActionButtonStyle(.primary).accessibilityIdentifier("announcements.create")
            Picker(AnnouncementStrings.mode, selection: $filter) {
                ForEach(["all"] + phases, id: \.self) { Text(AnnouncementManagementText.value($0)).tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("announcements.filter")
            if let error {
                InlineMessageCard(style: .error, message: error)
                Button(AnnouncementStrings.retry) { Task { await load(more: failedMore) } }.disabled(loading)
                    .accessibilityIdentifier("announcements.listRetry")
            }
            if loading || !hasLoaded && error == nil { ProgressView().accessibilityIdentifier("announcements.loading") }
            if items.isEmpty && hasLoaded && !loading && error == nil { Text(AnnouncementStrings.empty).foregroundStyle(AppTheme.textSecondary).accessibilityIdentifier("announcements.empty") }
            ForEach(phases.filter { filter == "all" || filter == $0 }, id: \.self) { phase in
                let matching = items.filter { $0.phase() == phase }
                if !matching.isEmpty {
                    Text(AnnouncementManagementText.value(phase)).font(.headline)
                    ForEach(matching) { item in
                        Button { editor = item } label: {
                            AppEditorSectionCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(item.title.localized().isEmpty ? AnnouncementStrings.draft : item.title.localized()).font(.headline)
                                    AnnouncementAudienceSummary(item: item, users: nil, compact: true)
                                    AnnouncementPeriodSummary(item: item)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("announcements.item.\(item.id)")
                    }
                }
            }
            if !items.isEmpty && filter != "all" && !items.contains(where: { $0.phase() == filter }) && !loading {
                Text(AnnouncementManagementText.value("empty")).foregroundStyle(AppTheme.textSecondary)
            }
            if cursor != nil { Button(AnnouncementStrings.loadMore) { Task { await load(more: true) } }.disabled(loading).accessibilityIdentifier("announcements.loadMore") }
        }
        .navigationTitle(AnnouncementStrings.title)
        .accessibilityIdentifier("screen.announcements.owner")
        .task { await load() }.refreshable { await load() }
        .onChange(of: filter) { _, _ in Task { await load() } }
        .onChange(of: ProfileAccessIdentity(user: authState.user)) { _, _ in
            generation += 1; editor = nil; items = []; cursor = nil; error = nil; loading = false
            hasLoaded = false
            pendingFilter = nil; failedMore = false
        }
        .sheet(item: $editor, onDismiss: {
            generation += 1; loading = false; pendingFilter = nil
            Task { await load() }
        }) { item in
            NavigationStack { AnnouncementEditorView(repository: repository, draft: item) }
        }
    }
    private func load(more: Bool = false) async {
        if loading && pendingFilter == filter { return }
        generation += 1; let version = generation
        let selectedFilter = filter
        if !more && selectedFilter != loadedFilter { items = []; cursor = nil }
        pendingFilter = selectedFilter; loading = true; failedMore = false
        defer { if version == generation { loading = false; pendingFilter = nil } }
        do {
            let targetCount = more ? 1 : max(1, items.count)
            var pageCursor = more ? cursor : nil
            var collected: [UserAnnouncement] = []
            var seenCursors = Set<String>()
            var response: AnnouncementResponse
            let started = ContinuousClock.now
            repeat {
                guard version == generation, selectedFilter == filter, !Task.isCancelled else { return }
                let remaining = Duration.seconds(20) - (ContinuousClock.now - started)
                guard remaining > .zero else { throw AppError.network }
                response = try await repository.read("manageAnnouncements", AnnouncementRequest(phase: selectedFilter == "all" ? nil : selectedFilter, operation: "list", cursor: pageCursor), timeout: remaining)
                collected += response.items ?? []
                pageCursor = response.cursor
                if let pageCursor, !seenCursors.insert(pageCursor).inserted { throw AnnouncementCommandError.missingResponse }
            } while collected.count < targetCount && pageCursor != nil
            guard version == generation, selectedFilter == filter, !Task.isCancelled else { return }
            let combined = (more ? items : []) + collected
            var seen = Set<String>()
            items = combined.filter { seen.insert($0.id).inserted }
            loadedFilter = selectedFilter; cursor = response.cursor; error = nil
            hasLoaded = true
        } catch { if version == generation, !Task.isCancelled { failedMore = more; self.error = AnnouncementErrorPresentation.message(error) } }
    }
}

struct AnnouncementEditorView: View {
    let repository: any AnnouncementRepository
    @State var draft: UserAnnouncement
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @State private var baseline: UserAnnouncement?
    @State private var language = "uk"
    @State private var reviewed = false
    @State private var busy = false
    @State private var message: String?
    @State private var failed = false
    @State private var preview = false
    @State private var users = false
    @State private var reviewSend = false
    @State private var discard = false
    @State private var stop = false
    @State private var count: Int?
    @State private var selectedUsers: [AnnouncementUser] = []
    @State private var selectedError: String?
    @State private var statistics: AnnouncementResponse?
    @State private var saveAttempts = AnnouncementSaveAttempts()
    @State private var operationTask: Task<Void, Never>?
    @State private var operationGeneration = 0
    @State private var reviewedDraft: UserAnnouncement?
    @State private var reviewedCount: Int?
    @State private var cancellationTarget: UserAnnouncement?
    @State private var reloadConfirmation = false
    private var editable: Bool { draft.status == "draft" }
    private var dirty: Bool { editable && baseline.map { $0 != draft } == true }
    var body: some View {
        ScrollViewReader { proxy in
            EditorScreenShell(title: AnnouncementStrings.title, subtitle: AnnouncementStrings.subtitle,
                              closeStyle: .cancel, closeAction: close) {
                if let message {
                    InlineMessageCard(style: failed ? .error : .info, message: message).accessibilityIdentifier("announcements.message").id("announcements.message")
                    if failed {
                        Button(NotificationAuditCopy.reload) { reloadConfirmation = true }
                            .disabled(busy).accessibilityIdentifier("announcements.reloadSaved")
                    }
                }
                if busy { ProgressView() }
                textSection.disabled(busy)
                if editable {
                    audienceSection.disabled(busy)
                    optionsSection.disabled(busy)
                    publicationSection.disabled(busy)
                } else {
                    AnnouncementSection(AnnouncementManagementText.value(draft.phase())) {
                        AnnouncementAudienceSummary(item: draft, users: selectedUsers)
                        if let selectedError { InlineMessageCard(style: .error, message: selectedError) }
                        AnnouncementPeriodSummary(item: draft)
                        Button(AnnouncementStrings.preview) { preview = true }.accessibilityIdentifier("announcements.preview")
                        if ["active", "scheduled"].contains(draft.phase()) {
                            Button(AnnouncementStrings.cancel, role: .destructive) { cancellationTarget = draft; stop = true }
                                .accessibilityIdentifier("announcements.cancel")
                        }
                        Button(AnnouncementStrings.stats) { run { try await loadStatistics() } }.accessibilityIdentifier("announcements.stats")
                    }.disabled(busy)
                    if let statistics { AnnouncementStatisticsView(item: draft, statistics: statistics) }
                }
            }
            .onChange(of: message) { _, value in
                if value != nil { withAnimation { proxy.scrollTo("announcements.message", anchor: .top) } }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(AnnouncementStrings.title)
            .interactiveDismissDisabled(busy || dirty)
            .onAppear { if baseline == nil { baseline = draft; if editable { draft.groups.removeAll { $0 == "guests" } } } }
            .task(id: draft.userIds) { await resolveSelected() }
            .onChange(of: draft.reviewedContent) { _, _ in reviewed = false; count = nil }
            .onChange(of: ProfileAccessIdentity(user: authState.user)) { _, _ in cancelOperation(); dismiss() }
            .onDisappear { cancelOperation() }
            .sheet(isPresented: $preview) { AnnouncementPreviewView(item: draft, selectedUsers: selectedUsers) }
            .sheet(isPresented: $users) { NavigationStack { AnnouncementUserPicker(repository: repository, selected: $draft.userIds) } }
            .sheet(isPresented: $reviewSend) { reviewSheet }
            .sheet(isPresented: $discard) {
                NotificationConfirmationSheet(title: AnnouncementManagementText.value("discardTitle"), cancel: { discard = false }) {
                    NotificationConfirmationAction(title: AnnouncementStrings.save, id: "announcements.saveBeforeClose") {
                        discard = false; run { try await save(); dismiss() }
                    }.disabled(!draft.saveIssues.isEmpty)
                    NotificationConfirmationAction(title: AnnouncementManagementText.value("discard"), id: "announcements.discard", role: .destructive) { discard = false; dismiss() }
                    NotificationConfirmationAction(title: AnnouncementManagementText.value("continue"), id: "announcements.continueEditing", role: .cancel) { discard = false }
                }
            }
            .sheet(isPresented: $stop) {
                NotificationConfirmationSheet(title: AnnouncementManagementText.value("stopTitle"),
                    message: AnnouncementManagementText.value("stopHelp"), cancel: { stop = false }) {
                    NotificationConfirmationAction(title: AnnouncementStrings.cancel, id: "announcements.confirmCancel", role: .destructive) {
                        stop = false; run { try await cancelAnnouncement() }
                    }
                    NotificationConfirmationAction(title: AppStrings.Common.cancel, id: "announcements.cancelStop", role: .cancel) { stop = false }
                }
            }
            .sheet(isPresented: $reloadConfirmation) {
                NotificationConfirmationSheet(title: NotificationAuditCopy.reloadTitle,
                    message: NotificationAuditCopy.reloadMessage, cancel: { reloadConfirmation = false }) {
                    NotificationConfirmationAction(title: NotificationAuditCopy.reload, id: "announcements.confirmReload", role: .destructive) {
                        reloadConfirmation = false; run { try await reloadSaved() }
                    }
                    NotificationConfirmationAction(title: AppStrings.Common.cancel, id: "announcements.cancelReload", role: .cancel) { reloadConfirmation = false }
                }
            }
        }
    }
    private var publicationSection: some View {
        AnnouncementSection {
            ForEach(draft.publicationIssues, id: \.self) { Text($0).font(.callout).foregroundStyle(AppTheme.textSecondary) }
            Button(AnnouncementStrings.preview) { preview = true }.accessibilityIdentifier("announcements.preview")
            Button(AnnouncementStrings.countAudience) { run { try await countAudience() } }
            if let count { LabeledContent(AnnouncementManagementText.value("recipientCount"), value: String(count)) }
            Toggle(AnnouncementStrings.review, isOn: $reviewed).accessibilityIdentifier("announcements.review")
            Button(AnnouncementStrings.save) { run { try await save(); dismiss() } }
                .appActionButtonStyle(.secondary).disabled(!draft.saveIssues.isEmpty).accessibilityIdentifier("announcements.save")
            Button(AnnouncementStrings.test) { run {
                _ = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "test", draft: draft))
                message = AnnouncementStrings.tested
            } }.disabled(!draft.canPublish || !reviewed)
            Button(AnnouncementStrings.send) { run {
                let snapshot = draft
                try await countAudience(snapshot)
                guard snapshot.reviewedContent == draft.reviewedContent else { throw AnnouncementCommandError.reviewedContentChanged }
                reviewedDraft = snapshot; reviewedCount = count; reviewSend = true
            } }
                .appActionButtonStyle(.primary).disabled(!draft.canPublish || !reviewed).accessibilityIdentifier("announcements.send")
        }
    }
    private var reviewSheet: some View {
        let snapshot = reviewedDraft ?? draft
        return NavigationStack {
            EditorScreenShell(title: AnnouncementManagementText.value("reviewTitle"), closeStyle: .cancel) {
                AnnouncementSection(AnnouncementStrings.preview) {
                    Text(snapshot.title.localized()).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(snapshot.body.localized()).fixedSize(horizontal: false, vertical: true)
                }
                AnnouncementSection(AnnouncementStrings.audience) {
                    AnnouncementAudienceSummary(item: snapshot, users: selectedUsers)
                    LabeledContent(AnnouncementManagementText.value("recipientCount"), value: reviewedCount.map(String.init) ?? "—")
                    Text(AnnouncementManagementText.value("countHelp")).font(.caption).foregroundStyle(AppTheme.textSecondary).lineLimit(nil).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    if reviewedCount == 0 { InlineMessageCard(style: .info, message: AnnouncementManagementText.value("noRecipients")) }
                }
                AnnouncementSection {
                    AnnouncementPeriodSummary(item: snapshot)
                    LabeledContent(AnnouncementStrings.mode, value: snapshot.mode == "once" ? AnnouncementStrings.once : AnnouncementStrings.acknowledge)
                    LabeledContent(AnnouncementStrings.push, value: AnnouncementManagementText.value(snapshot.push ? "yes" : "no"))
                    LabeledContent(AnnouncementStrings.feedback, value: AnnouncementManagementText.value(snapshot.feedback ? "yes" : "no"))
                    Button(AnnouncementStrings.send) { reviewSend = false; run {
                        guard snapshot.reviewedContent == draft.reviewedContent else { throw AnnouncementCommandError.reviewedContentChanged }
                        try await save(snapshot)
                        if draft.status == "published" { message = AnnouncementStrings.sent; return }
                        guard draft.status == "draft" else { throw AnnouncementCommandError.reviewedContentChanged }
                        do {
                            _ = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "publish", id: draft.id, revision: draft.revision))
                        } catch {
                            try Task.checkCancellation()
                            let stored = try? await repository.read("manageAnnouncements", AnnouncementRequest(operation: "get", id: snapshot.id)).item
                            guard let stored, stored.status == "published", stored.reviewedContent == snapshot.reviewedContent else { throw error }
                            draft = stored
                        }
                        try Task.checkCancellation()
                        draft.status = "published"; baseline = draft; message = AnnouncementStrings.sent
                    } }.appActionButtonStyle(.primary).disabled(busy || reviewedCount == nil || reviewedCount == 0 || snapshot.reviewedContent != draft.reviewedContent).accessibilityIdentifier("announcements.confirmSend")
                }
            }
        }
    }
    private var textSection: some View {
        AnnouncementSection {
            Picker(AnnouncementStrings.body, selection: $language) { Text(AppLanguage.ukrainian.title).tag("uk"); Text(AppLanguage.german.title).tag("de") }.pickerStyle(.segmented)
            if editable {
                EditorTextField(AnnouncementStrings.headline, text: textBinding(title: true), systemImage: "textformat").accessibilityIdentifier("announcements.headline")
                Text("\((language == "uk" ? draft.title.uk : draft.title.de).utf16.count)/160").font(.caption).foregroundStyle(AppTheme.textSecondary)
                EditorTextArea(AnnouncementStrings.body, text: textBinding(title: false), counterText: "\((language == "uk" ? draft.body.uk : draft.body.de).utf16.count)/6000", minHeight: 140).accessibilityIdentifier("announcements.body")
                ContentTranslationButton(kind: "announcement", fields: [
                    .init("title", AnnouncementStrings.headline, source: language == "uk" ? draft.title.uk : draft.title.de, target: language == "uk" ? $draft.title.de : $draft.title.uk, limit: 160),
                    .init("body", AnnouncementStrings.body, source: language == "uk" ? draft.body.uk : draft.body.de, target: language == "uk" ? $draft.body.de : $draft.body.uk, limit: 6000)
                ], sourceLanguage: language == "uk" ? .ukrainian : .german).id(language)
            } else {
                Text(language == "uk" ? draft.title.uk : draft.title.de).font(.title2.bold()).textSelection(.enabled)
                Text(language == "uk" ? draft.body.uk : draft.body.de).textSelection(.enabled)
            }
        }
    }
    private var audienceSection: some View {
        AnnouncementSection(AnnouncementStrings.audience) {
            ForEach(["registered", "organizationOwners", "appAdmins", "organizationAdmins", "organizationModerators"], id: \.self) { group in
                Toggle(AnnouncementStrings.group(group), isOn: selection(group, in: $draft.groups))
            }
            Text(AnnouncementManagementText.value("union")).font(.caption).foregroundStyle(AppTheme.textSecondary).lineLimit(nil).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Button("\(AnnouncementManagementText.value("addPeople")) (\(draft.userIds.count))") { users = true }.accessibilityIdentifier("announcements.people")
            if !draft.userIds.isEmpty {
                AnnouncementAudienceSummary(item: draft, users: selectedUsers, peopleOnly: true)
                if let selectedError {
                    InlineMessageCard(style: .error, message: selectedError)
                    Button(AnnouncementStrings.retry) { Task { await resolveSelected() } }
                }
            }
            DisclosureGroup(AnnouncementStrings.regions) {
                Toggle(AnnouncementStrings.austria, isOn: Binding(get: { draft.regions.isEmpty }, set: { draft.regions = $0 ? [] : ["wien"] }))
                ForEach(AustrianFederalState.allCases) { region in Toggle(region.displayName, isOn: selection(region.rawValue, in: $draft.regions)) }
                Text(AnnouncementStrings.regionHelp).font(.caption)
            }
        }
    }
    private var optionsSection: some View {
        AnnouncementSection(AnnouncementStrings.mode) {
            Picker(AnnouncementStrings.mode, selection: $draft.mode) {
                Text(AnnouncementStrings.once).tag("once"); Text(AnnouncementStrings.acknowledge).tag("acknowledge")
            }
            Toggle(AnnouncementStrings.push, isOn: $draft.push)
            Toggle(AnnouncementStrings.feedback, isOn: $draft.feedback)
            AnnouncementSchedulePicker(title: AnnouncementStrings.start, selection: dateBinding($draft.startsAt))
            AnnouncementSchedulePicker(title: AnnouncementStrings.expiry, selection: dateBinding($draft.expiresAt))
            Text(AnnouncementStrings.scheduleHelp).font(.caption).fixedSize(horizontal: false, vertical: true)
        }.environment(\.timeZone, TimeZone(identifier: "Europe/Vienna")!)
    }
    private func close() { guard !busy else { return }; if dirty { discard = true } else { dismiss() } }
    private func selection(_ value: String, in binding: Binding<[String]>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue.contains(value) }, set: { selected in binding.wrappedValue.removeAll { $0 == value }; if selected { binding.wrappedValue.append(value) } })
    }
    private func dateBinding(_ value: Binding<Double>) -> Binding<Date> { Binding(get: { Date(timeIntervalSince1970: value.wrappedValue / 1000) }, set: { value.wrappedValue = ($0.timeIntervalSince1970 * 1000).rounded() }) }
    private func textBinding(title: Bool) -> Binding<String> {
        Binding(get: { title ? (language == "uk" ? draft.title.uk : draft.title.de) : (language == "uk" ? draft.body.uk : draft.body.de) }, set: {
            if title { if language == "uk" { draft.title.uk = $0 } else { draft.title.de = $0 } }
            else { if language == "uk" { draft.body.uk = $0 } else { draft.body.de = $0 } }
        })
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; message = nil; failed = false
        operationGeneration += 1
        let generation = operationGeneration, identity = ProfileAccessIdentity(user: authState.user)
        operationTask = Task {
            defer { if operationGeneration == generation { busy = false; operationTask = nil } }
            do { try Task.checkCancellation(); try await operation() }
            catch {
                guard !Task.isCancelled, operationGeneration == generation,
                      ProfileAccessIdentity(user: authState.user) == identity else { return }
                failed = true; message = AnnouncementErrorPresentation.message(error)
            }
        }
    }
    private func cancelOperation() {
        operationGeneration += 1; operationTask?.cancel(); operationTask = nil; busy = false
    }
    private func save(_ snapshot: UserAnnouncement? = nil) async throws {
        let value = snapshot ?? draft
        let operationID = saveAttempts.operationID(for: value)
        do {
            let response = try await repository.call("manageAnnouncements", AnnouncementRequest(operationId: operationID, operation: "save", revision: value.revision, draft: value))
            try Task.checkCancellation()
            guard let item = response.item else { throw AnnouncementCommandError.missingResponse }
            draft = item; baseline = item; saveAttempts.complete(operationID)
        } catch {
            try Task.checkCancellation()
            // A committed save/publication can outlive its lost response. Only
            // identical reviewed content is accepted; different edits stay intact.
            if let saved = try? await repository.read("manageAnnouncements", AnnouncementRequest(operation: "get", id: value.id)).item,
               saved.reviewedContent == value.reviewedContent, saved.revision >= value.revision {
                try Task.checkCancellation()
                draft = saved; baseline = saved; saveAttempts.complete(operationID)
                return
            }
            throw error
        }
    }
    private func reloadSaved() async throws {
        let response = try await repository.read("manageAnnouncements", AnnouncementRequest(operation: "get", id: draft.id))
        try Task.checkCancellation()
        guard let item = response.item else { throw AnnouncementCommandError.missingResponse }
        draft = item; baseline = item; reviewed = false; count = nil; statistics = nil; saveAttempts = AnnouncementSaveAttempts()
    }
    private func cancelAnnouncement() async throws {
        let target = cancellationTarget ?? draft
        do {
            _ = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "cancel", id: target.id, revision: target.revision))
        } catch {
            try Task.checkCancellation()
            let stored = try? await repository.read("manageAnnouncements", AnnouncementRequest(operation: "get", id: target.id)).item
            guard stored?.status == "cancelled" else { throw error }
        }
        try Task.checkCancellation()
        draft.status = "cancelled"; baseline = draft; statistics = nil
    }
    private func countAudience(_ snapshot: UserAnnouncement? = nil) async throws {
        let value = snapshot ?? draft
        var cursor: String?, total = 0
        var seenCursors = Set<String>()
        repeat {
            let result = try await repository.read("manageAnnouncements", AnnouncementRequest(operation: "preview", draft: value, cursor: cursor))
            total += result.accounts ?? 0; cursor = result.cursor
            try Task.checkCancellation()
            if let cursor, !seenCursors.insert(cursor).inserted { throw AnnouncementCommandError.missingResponse }
        } while cursor != nil
        count = total
    }
    private func resolveSelected() async {
        let ids = draft.userIds
        guard !ids.isEmpty else { selectedUsers = []; selectedError = nil; return }
        do {
            let response = try await repository.read("manageAnnouncements", AnnouncementRequest(userIds: ids, operation: "resolveUsers"))
            guard !Task.isCancelled, ids == draft.userIds else { return }
            selectedUsers = response.users ?? []; selectedError = nil
        } catch { if !Task.isCancelled, ids == draft.userIds { selectedError = AnnouncementErrorPresentation.message(error) } }
    }
    private func loadStatistics() async throws {
        statistics = try await repository.read("manageAnnouncements", AnnouncementRequest(operation: "stats", id: draft.id))
    }
}
