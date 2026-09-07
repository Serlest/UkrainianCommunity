import SwiftUI

struct AnnouncementOwnerView: View {
    let repository: any AnnouncementRepository
    @State private var items: [UserAnnouncement] = []
    @State private var cursor: String?
    @State private var editor: UserAnnouncement?
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        ProfileDestinationLayout(title: AnnouncementStrings.title, introSubtitle: AnnouncementStrings.subtitle) {
            Button(AnnouncementStrings.create, systemImage: "plus") { editor = UserAnnouncement() }
                .appActionButtonStyle(.primary)
                .accessibilityIdentifier("announcements.create")
            if let error { InlineMessageCard(style: .error, message: error) }
            if loading { ProgressView() }
            ForEach(items) { item in
                Button { editor = item } label: {
                    AppEditorSectionCard { VStack(alignment: .leading, spacing: 8) {
                        Text(item.title.localized().isEmpty ? AnnouncementStrings.draft : item.title.localized())
                        Text(AnnouncementStrings.group(item.status)).font(.caption).foregroundStyle(AppTheme.textSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading) }
                }.buttonStyle(.plain)
            }
            if cursor != nil { Button(AnnouncementStrings.loadMore) { Task { await load(more: true) } } }
        }
        .navigationTitle(AnnouncementStrings.title)
        .accessibilityIdentifier("screen.announcements.owner")
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editor, onDismiss: { Task { await load() } }) { item in
            NavigationStack { AnnouncementEditorView(repository: repository, draft: item) }
        }
    }
    private func load(more: Bool = false) async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do {
            let response = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "list", cursor: more ? cursor : nil))
            items = (more ? items : []) + (response.items ?? []); cursor = response.cursor; error = nil
        } catch { self.error = AnnouncementStrings.error }
    }
}

struct AnnouncementEditorView: View {
    let repository: any AnnouncementRepository
    @State var draft: UserAnnouncement
    @Environment(\.dismiss) private var dismiss
    @State private var language = "uk"
    @State private var reviewed = false
    @State private var busy = false
    @State private var message: String?
    @State private var preview = false
    @State private var users = false
    @State private var confirmSend = false
    @State private var count: Int?
    @State private var statistics: AnnouncementResponse?
    private var editable: Bool { draft.status == "draft" }
    var body: some View {
        EditorScreenShell(title: AnnouncementStrings.title, subtitle: AnnouncementStrings.subtitle,
                          closeStyle: .cancel, closeAction: { if !busy { dismiss() } }) {
            if let message { InlineMessageCard(style: .info, message: message).accessibilityIdentifier("announcements.message") }
            if busy { ProgressView() }
            textSection.disabled(!editable || busy)
            if editable {
                audienceSection.disabled(busy)
                optionsSection.disabled(busy)
                AnnouncementSection {
                    Button(AnnouncementStrings.preview) { preview = true }.accessibilityIdentifier("announcements.preview")
                    Button(AnnouncementStrings.countAudience) { run { try await countAudience() } }
                    if let count { Text("\(AnnouncementStrings.count): \(count)") }
                    if draft.groups.contains("guests") { Text(AnnouncementStrings.guestsUnknown).font(.caption) }
                    Toggle(AnnouncementStrings.review, isOn: $reviewed).accessibilityIdentifier("announcements.review")
                    Button(AnnouncementStrings.save) { run { try await save(); dismiss() } }.appActionButtonStyle(.secondary).accessibilityIdentifier("announcements.save").accessibilityValue(message == AnnouncementStrings.saved ? AnnouncementStrings.saved : "")
                    Button(AnnouncementStrings.test) { run { _ = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "test", draft: draft)); message = AnnouncementStrings.tested } }
                        .disabled(!draft.canPublish || !reviewed)
                    Button(AnnouncementStrings.send) { confirmSend = true }.appActionButtonStyle(.primary)
                        .disabled(!draft.canPublish || !reviewed)
                        .accessibilityIdentifier("announcements.send")
                }.disabled(busy)
            } else {
                AnnouncementSection {
                    Button(AnnouncementStrings.preview) { preview = true }.accessibilityIdentifier("announcements.preview")
                    if draft.status == "published" {
                        Button(AnnouncementStrings.cancel, role: .destructive) { run {
                            _ = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "cancel", id: draft.id))
                            draft.status = "cancelled"
                        } }
                    }
                    Button(AnnouncementStrings.stats) { run { statistics = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "stats", id: draft.id)) } }.accessibilityIdentifier("announcements.stats")
                    if let statistics {
                        stat(AnnouncementStrings.shown, statistics.presented)
                        stat(AnnouncementStrings.confirmed, statistics.acknowledged)
                        stat(AnnouncementStrings.action, statistics.action)
                        stat(AnnouncementStrings.pushSent, statistics.pushSuccess)
                        stat(AnnouncementStrings.pushFailed, statistics.pushFailure)
                        stat(AnnouncementStrings.guestShown, statistics.guestPresented)
                        stat(AnnouncementStrings.guestAck, statistics.guestAcknowledged)
                    }
                }.disabled(busy)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(AnnouncementStrings.title)
        .interactiveDismissDisabled(busy)
        .onChange(of: draft) { _, _ in reviewed = false; count = nil }
        .sheet(isPresented: $preview) { AnnouncementPreviewView(item: draft) }
        .sheet(isPresented: $users) { NavigationStack { AnnouncementUserPicker(repository: repository, selected: $draft.userIds) } }
        .confirmationDialog(AnnouncementStrings.sendConfirm, isPresented: $confirmSend) {
            Button(AnnouncementStrings.send) { run {
                try await save()
                _ = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "publish", id: draft.id, revision: draft.revision))
                draft.status = "published"; message = AnnouncementStrings.sent
            } }.accessibilityIdentifier("announcements.confirmSend")
        }
    }
    private var textSection: some View {
        AnnouncementSection {
            Picker(AnnouncementStrings.body, selection: $language) { Text(AppLanguage.ukrainian.title).tag("uk"); Text(AppLanguage.german.title).tag("de") }.pickerStyle(.segmented)
            EditorTextField(AnnouncementStrings.headline, text: textBinding(title: true), systemImage: "textformat").accessibilityIdentifier("announcements.headline")
            EditorTextArea(AnnouncementStrings.body, text: textBinding(title: false), counterText: "\((language == "uk" ? draft.body.uk : draft.body.de).count)/6000", minHeight: 140).accessibilityIdentifier("announcements.body")
            if editable {
                ContentTranslationButton(kind: "announcement", fields: [
                    .init("title", AnnouncementStrings.headline, source: language == "uk" ? draft.title.uk : draft.title.de, target: language == "uk" ? $draft.title.de : $draft.title.uk, limit: 160),
                    .init("body", AnnouncementStrings.body, source: language == "uk" ? draft.body.uk : draft.body.de, target: language == "uk" ? $draft.body.de : $draft.body.uk, limit: 6000)
                ], sourceLanguage: language == "uk" ? .ukrainian : .german).id(language)
            }
        }
    }
    private var audienceSection: some View {
        AnnouncementSection(AnnouncementStrings.audience) {
            ForEach(["registered", "guests", "organizationOwners", "appAdmins", "organizationAdmins", "organizationModerators"], id: \.self) { group in
                Toggle(AnnouncementStrings.group(group), isOn: selection(group, in: $draft.groups))
            }
            Button("\(AnnouncementStrings.people) (\(draft.userIds.count))") { users = true }
            DisclosureGroup(AnnouncementStrings.regions) {
                Toggle(AnnouncementStrings.austria, isOn: Binding(get: { draft.regions.isEmpty }, set: { if $0 { draft.regions = [] } else { draft.regions = ["wien"] } }))
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
            DatePicker(AnnouncementStrings.start, selection: dateBinding($draft.startsAt))
            DatePicker(AnnouncementStrings.expiry, selection: dateBinding($draft.expiresAt))
            Text(AnnouncementStrings.scheduleHelp).font(.caption)
        }.environment(\.timeZone, TimeZone(identifier: "Europe/Vienna")!)
    }
    private func stat(_ label: String, _ value: Int?) -> some View { LabeledContent(label, value: String(value ?? 0)) }
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
        guard !busy else { return }; busy = true; message = nil
        Task { defer { busy = false }; do { try await operation() } catch { message = AnnouncementStrings.error } }
    }
    private func save() async throws {
        let response = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "save", revision: draft.revision, draft: draft))
        if let item = response.item { draft = item }
    }
    private func countAudience() async throws {
        var cursor: String?, total = 0
        repeat {
            let result = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "preview", draft: draft, cursor: cursor))
            total += result.accounts ?? 0; cursor = result.cursor
        } while cursor != nil
        count = total
    }
}

private struct AnnouncementUserPicker: View {
    let repository: any AnnouncementRepository
    @Binding var selected: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var items: [AnnouncementUser] = []
    @State private var cursor: String?
    @State private var query = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        EditorScreenShell(title: AnnouncementStrings.people, closeStyle: .cancel) {
            if let error { InlineMessageCard(style: .error, message: error) }
            ForEach(items.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { user in
                Toggle(user.name, isOn: Binding(get: { selected.contains(user.id) }, set: { on in
                    selected.removeAll { $0 == user.id }; if on && selected.count < 100 { selected.append(user.id) }
                }))
            }
            if cursor != nil { Button(AnnouncementStrings.loadMore) { Task { await load() } }.disabled(busy) }
        }
        .searchable(text: $query, prompt: AnnouncementStrings.search)
        .navigationTitle(AnnouncementStrings.people)
        .toolbar { Button(AnnouncementStrings.close) { dismiss() } }
        .task { await load() }
    }
    private func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { let page = try await repository.users(cursor: cursor); items += page.items; cursor = page.cursor; error = nil }
        catch { self.error = AnnouncementStrings.error }
    }
}
struct AnnouncementPreviewView: View {
    let item: UserAnnouncement
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            EditorScreenShell(title: AnnouncementStrings.preview, closeStyle: .cancel) {
                ForEach(["uk", "de"], id: \.self) { lang in
                    AnnouncementSection(lang == "uk" ? AppLanguage.ukrainian.title : AppLanguage.german.title) {
                        Text(lang == "uk" ? item.title.uk : item.title.de).font(.headline)
                        Text(lang == "uk" ? item.body.uk : item.body.de)
                    }
                }
                AnnouncementSection(AnnouncementStrings.audience) {
                    ForEach(item.groups, id: \.self) { Text(AnnouncementStrings.group($0)) }
                    Text("\(AnnouncementStrings.people): \(item.userIds.count)")
                    Text(item.regions.isEmpty ? AnnouncementStrings.austria : item.regions.compactMap(AustrianFederalState.init(rawValue:)).map(\.displayName).joined(separator: ", "))
                    Text(AnnouncementStrings.regionHelp)
                }
            }.navigationTitle(AnnouncementStrings.preview).toolbar { Button(AnnouncementStrings.close) { dismiss() }.accessibilityIdentifier("announcements.previewClose") }
        }
    }
}

struct AnnouncementSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                if let title { AppEditorSectionTitle(title: title) }
                content
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
