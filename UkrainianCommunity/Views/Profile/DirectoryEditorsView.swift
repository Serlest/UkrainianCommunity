import FirebaseFirestore
import SwiftUI

struct DirectoryEditorsView: View {
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @EnvironmentObject private var authState: AuthState
    @StateObject private var users = DirectoryEditorCandidatesStore()
    @State private var editorIDs = Set<String>()
    @State private var editorNames: [String: String] = [:]
    @State private var searchText = ""
    @State private var busyIDs = Set<String>()
    @State private var errorMessage: String?
    @State private var isLoading = true
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
                    if isLoading { ProgressView() }
                    if !isLoading && editorIDs.isEmpty {
                        Text(DirectoryEditorText.value("Редакторів поки немає", "Noch keine Redakteure"))
                    }
                    ForEach(editorIDs.sorted(), id: \.self) { id in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(editorNames[id] ?? id)
                                if editorNames[id] != nil {
                                    Text(id).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                pendingRevocation = id
                            } label: {
                                Text(DirectoryEditorText.value("Зняти", "Entziehen"))
                            }
                            .disabled(busyIDs.contains(id))
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
        .scrollContentBackground(.hidden)
        .background(AppBackgroundView())
        .tint(AppTheme.accentPrimaryForeground)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(DirectoryEditorText.value("Редактори довідника", "Ratgeberredakteure"))
        .task(id: actor?.id) {
            guard isOwner else { return }
            async let candidates: Void = users.load()
            async let grants: Void = loadEditors()
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
        }
        .alert(DirectoryEditorText.value("Помилка доступу", "Zugriffsfehler"),
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button(DirectoryEditorText.value("Гаразд", "OK")) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
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
            if editorIDs.contains(user.id) {
                Label(DirectoryEditorText.value("Має доступ", "Zugriff aktiv"),
                      systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Button(DirectoryEditorText.value("Надати", "Freigeben")) {
                    Task { await setAccess(true, userID: user.id) }
                }
                .disabled(!usable || busyIDs.contains(user.id))
            }
        }
    }

    private func loadEditors() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snapshot = try await Firestore.firestore().collection("directoryEditors")
                .getDocuments(source: .server)
            editorIDs = Set(snapshot.documents.filter {
                $0.data()["enabled"] as? Bool == true
            }.map(\.documentID))
            for id in editorIDs {
                if let user = try? await UserManagementReads.live.user(id) {
                    editorNames[id] = user.preferredDisplayName
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setAccess(_ enabled: Bool, userID: String) async {
        guard isOwner, let actorID = actor?.id, !busyIDs.contains(userID) else { return }
        busyIDs.insert(userID)
        defer { busyIDs.remove(userID) }
        let reference = Firestore.firestore().collection("directoryEditors").document(userID)
        do {
            if enabled {
                try await reference.setData([
                    "enabled": true,
                    "grantedBy": actorID,
                    "grantedAt": FieldValue.serverTimestamp()
                ])
            } else {
                try await reference.delete()
            }
            let readback = try await reference.getDocument(source: .server)
            guard readback.exists == enabled else { throw AppError.network }
            if enabled { editorIDs.insert(userID) }
            else { editorIDs.remove(userID) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
