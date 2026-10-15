import SwiftUI

struct DirectoryEditorsView: View {
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @EnvironmentObject private var authState: AuthState
    @StateObject private var users = DirectoryEditorCandidatesStore()
    @StateObject private var access = DirectoryEditorAccessStore()
    @State private var searchText = ""
    @State private var pendingRevocation: String?

    private var actor: AppUser? { authState.user }
    private var isOwner: Bool { PermissionService.isAppOwner(user: actor) }
    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var candidates: [AppUser] {
        if normalizedSearch.count >= 2 { return users.searchResults }
        return users.users.filter { user in
            normalizedSearch.isEmpty ||
            [user.displayName, user.fullName, user.email].contains {
                $0.localizedStandardContains(normalizedSearch)
            }
        }
    }

    var body: some View {
        List {
            if !isOwner {
                ContentUnavailableView(
                    DirectoryEditorText.value("Лише для власника", "Nur für Eigentümer"),
                    systemImage: "lock"
                )
            } else {
                Section {
                    Text(DirectoryEditorText.value(
                        "Редактори можуть публікувати, змінювати й приховувати всі матеріали довідника. Власник завжди має цей доступ.",
                        "Redakteure können alle Ratgeberinhalte veröffentlichen, ändern und ausblenden. Der Eigentümer behält diesen Zugriff immer."
                    ))
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                Section(DirectoryEditorText.value("Мають доступ", "Mit Zugriff")) {
                    if access.isLoading { ProgressView() }
                    if !access.isLoading && !access.loadFailed && access.editorIDs.isEmpty {
                        Text(DirectoryEditorText.value("Редакторів поки немає", "Noch keine Redakteure"))
                    }
                    if access.loadFailed {
                        Button(DirectoryEditorText.value("Не вдалося завантажити права. Повторити", "Zugriffsrechte nicht geladen. Erneut versuchen")) {
                            guard let actorID = actor?.id, isOwner else { return }
                            Task { await access.load(actorID: actorID) }
                        }
                    }
                    ForEach(sortedEditorIDs, id: \.self) { id in
                        HStack {
                            editorIdentity(id)
                            Spacer()
                            Button(role: .destructive) {
                                pendingRevocation = id
                            } label: {
                                Text(DirectoryEditorText.value("Зняти", "Entziehen"))
                            }
                            .disabled(access.isLoading || access.busyIDs.contains(id))
                        }
                    }
                }
                Section(DirectoryEditorText.value("Зареєстровані користувачі", "Registrierte Nutzer")) {
                    TextField(DirectoryEditorText.value("Ім’я або email", "Name oder E-Mail"),
                              text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if users.isSearching { ProgressView() }
                    if users.isLoading { ProgressView() }
                    ForEach(candidates) { user in
                        if user.id != actor?.id && user.globalRole.authorizationRole != .owner {
                            userRow(user)
                        }
                    }
                    if normalizedSearch.isEmpty && users.canLoadMore {
                        Button(DirectoryEditorText.value("Показати ще", "Weitere anzeigen")) {
                            Task { await users.loadMore() }
                        }
                        .disabled(users.isLoadingMore)
                    }
                    if users.searchFailed {
                        Text(DirectoryEditorText.value("Пошук не вдався", "Suche fehlgeschlagen"))
                            .foregroundStyle(.red)
                    }
                    if users.loadFailed {
                        Button(DirectoryEditorText.value("Не вдалося завантажити. Повторити", "Laden fehlgeschlagen. Erneut versuchen")) {
                            Task { await users.load() }
                        }
                    }
                }
            }
        }
        .buttonStyle(.borderless)
        .scrollContentBackground(.hidden)
        .background(AppBackgroundView())
        .tint(AppTheme.accentPrimaryForeground)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(DirectoryEditorText.value("Редактори довідника", "Ratgeberredakteure"))
        .task(id: actor?.id) {
            guard isOwner, let actorID = actor?.id else { return }
            async let candidates: Void = users.load()
            async let grants: Void = access.load(actorID: actorID)
            _ = await (candidates, grants)
        }
        .task(id: normalizedSearch) {
            guard isOwner else { return }
            if normalizedSearch.count < 2 {
                users.clearSearch()
                return
            }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await users.search(normalizedSearch)
        }
        .confirmationDialog(
            DirectoryEditorText.value("Забрати доступ до довідника?", "Ratgeberzugriff entziehen?"),
            isPresented: Binding(
                get: { pendingRevocation != nil },
                set: { if !$0 { pendingRevocation = nil } }
            )
        ) {
            if let pendingRevocation {
                Button(DirectoryEditorText.value("Забрати доступ", "Zugriff entziehen"), role: .destructive) {
                    self.pendingRevocation = nil
                    Task { await setAccess(false, userID: pendingRevocation) }
                }
            }
            Button(DirectoryEditorText.value("Скасувати", "Abbrechen"), role: .cancel) { pendingRevocation = nil }
        } message: {
            if let id = pendingRevocation {
                Text(revocationDescription(id))
            }
        }
        .alert(DirectoryEditorText.value("Помилка доступу", "Zugriffsfehler"),
               isPresented: Binding(get: { access.errorMessage != nil },
                                    set: { if !$0 { access.errorMessage = nil } })) {
            Button(DirectoryEditorText.value("Гаразд", "OK")) { access.errorMessage = nil }
        } message: {
            Text(access.errorMessage ?? "")
        }
    }

    @ViewBuilder private func userRow(_ user: AppUser) -> some View {
        let usable = (user.accountStatus == .active || user.accountStatus == .warned) &&
            (user.blockState == .active || user.blockState == .warned)
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(user.preferredDisplayName)
                Text(user.email).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if access.editorIDs.contains(user.id) {
                Label(DirectoryEditorText.value("Має доступ", "Zugriff aktiv"),
                      systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Button(DirectoryEditorText.value("Надати", "Freigeben")) {
                    Task { await setAccess(true, userID: user.id, knownUser: user) }
                }
                .disabled(!usable || access.isLoading || access.busyIDs.contains(user.id))
            }
        }
    }

    private var sortedEditorIDs: [String] {
        access.editorIDs.sorted { lhs, rhs in
            let first = profile(lhs)?.preferredDisplayName ?? lhs
            let second = profile(rhs)?.preferredDisplayName ?? rhs
            let comparison = LocalizationStore.compareForSorting(first, second)
            return comparison == .orderedSame ? lhs < rhs : comparison == .orderedAscending
        }
    }

    private func profile(_ id: String) -> AppUser? {
        (users.searchResults + users.users).first { $0.id == id } ?? access.profiles[id]
    }

    @ViewBuilder
    private func editorIdentity(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let user = profile(id) {
                Text(user.preferredDisplayName).font(.body)
                Text(user.email).font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text(access.missingProfileIDs.contains(id)
                     ? DirectoryEditorText.value("Профіль користувача відсутній", "Nutzerprofil nicht vorhanden")
                     : DirectoryEditorText.value("Дані користувача не завантажено", "Nutzerdaten nicht geladen"))
                Text("ID: \(id)").font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if access.failedProfileIDs.contains(id) {
                    Button(DirectoryEditorText.value("Повторити", "Erneut versuchen")) {
                        guard let actorID = actor?.id, isOwner else { return }
                        Task { await access.loadProfile(id, actorID: actorID) }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func revocationDescription(_ id: String) -> String {
        let identity = profile(id).map { "\($0.preferredDisplayName) · \($0.email)" } ?? "ID: \(id)"
        return DirectoryEditorText.value(
            "\(identity) більше не зможе редагувати довідник.",
            "\(identity) kann den Ratgeber danach nicht mehr bearbeiten."
        )
    }

    private func setAccess(_ enabled: Bool, userID: String, knownUser: AppUser? = nil) async {
        guard isOwner, let actorID = actor?.id else { return }
        await access.setAccess(enabled, userID: userID, knownUser: knownUser, actorID: actorID)
    }
}
