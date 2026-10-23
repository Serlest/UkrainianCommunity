import SwiftUI

struct DirectoryEditorsView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var users: DirectoryEditorCandidatesStore
    @StateObject private var access: DirectoryEditorAccessStore
    @State private var searchText = ""
    @State private var pending: Review?

    private struct Review: Identifiable {
        let id = UUID()
        let actorID: String
        let grant: DirectoryEditorGrant
        let enabled: Bool
        let identity: String
        let user: AppUser?
    }
    @MainActor init(users: DirectoryEditorCandidatesStore? = nil, access: DirectoryEditorAccessStore? = nil) {
        _users = StateObject(wrappedValue: users ?? DirectoryEditorCandidatesStore()); _access = StateObject(wrappedValue: access ?? DirectoryEditorAccessStore())
    }
    private var actor: AppUser? { authState.user }
    private var isOwner: Bool { PermissionService.isAppOwner(user: actor) && PermissionService.isUsableAccount(user: actor) }
    private var principal: String { isOwner ? actor?.id ?? "" : "" }
    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searchKey: String { principal + "|" + query }
    private func text(_ uk: String, _ de: String) -> String { DirectoryEditorText.value(uk, de) }

    var body: some View {
        AdminScreenShell(title: OwnerProfileText.directoryEditors, subtitle: text("Керуйте доступом до всіх матеріалів довідника.", "Verwalten Sie den Zugriff auf alle Ratgeberinhalte.")) {
            if !isOwner {
                ContentUnavailableView(text("Лише для власника", "Nur für Eigentümer"), systemImage: "lock")
            } else {
                AppEditorSectionCard {
                    Label(text("Доступ до всього довідника", "Zugriff auf den gesamten Ratgeber"), systemImage: "book.closed")
                        .font(.headline)
                    Text(text("Редактори можуть публікувати, змінювати й приховувати всі матеріали. Власник застосунку завжди має цей доступ. Зміни прав записуються в журнал, користувач отримує сповіщення.", "Redakteure können alle Inhalte veröffentlichen, ändern und ausblenden. Der App-Eigentümer behält diesen Zugriff immer. Änderungen werden protokolliert und dem Nutzer mitgeteilt."))
                        .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                }
                AppEditorSectionCard {
                    VStack(alignment: .leading, spacing: 16) {
                        AppEditorSectionTitle(title: text("Мають доступ", "Mit Zugriff"))
                        if access.isLoading { ProgressView() }
                        if !access.isLoading && !access.loadFailed && access.editorIDs.isEmpty {
                            Text(text("Доступ іншим користувачам ще не надано.", "Noch kein Zugriff für andere Nutzer erteilt.")).foregroundStyle(AppTheme.textSecondary)
                        }
                        if access.loadFailed { retryButton { await access.load(actorID: principal) } }
                        ForEach(sortedEditorIDs, id: \.self) { id in
                            VStack(alignment: .leading, spacing: 10) {
                                adaptiveRow {
                                    editorIdentity(id)
                                } action: {
                                    Button(role: .destructive) { review(id, enabled: false) } label: { Text(text("Відкликати доступ", "Zugriff entziehen")) }
                                        .disabled(access.busyIDs.contains(id) || access.grants[id] == nil)
                                        .accessibilityIdentifier("directoryAccess.revoke.\(id)")
                                }
                                if let milliseconds = access.grants[id]?.grantedAt {
                                    Text(text("Надано: ", "Erteilt: ") + Date(timeIntervalSince1970: milliseconds / 1000).formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(LocalizationStore.locale)))
                                        .font(.caption).foregroundStyle(AppTheme.textSecondary)
                                }
                                Divider()
                            }
                        }
                        if access.canLoadMore {
                            Button(text("Показати ще", "Weitere anzeigen")) { Task { await access.loadMore(actorID: principal) } }.disabled(access.isLoadingMore)
                        }
                    }
                }
                AppEditorSectionCard {
                    VStack(alignment: .leading, spacing: 16) {
                        AppEditorSectionTitle(title: text("Зареєстровані користувачі", "Registrierte Nutzer"))
                        AppSearchField(placeholder: text("Ім’я або email", "Name oder E-Mail"),
                                       text: $searchText, fieldID: "directoryAccess.search")
                        Text(text("Знайдено: ", "Gefunden: ") + String(users.total)).font(.caption).foregroundStyle(AppTheme.textSecondary)
                        if users.isLoading { ProgressView() }
                        if users.loadFailed { retryButton { await users.load(actorID: principal, query: query) } }
                        if !users.isLoading && !users.loadFailed && users.users.isEmpty {
                            Text(text("Користувачів не знайдено. Спробуйте інше ім’я або email.", "Keine Nutzer gefunden. Versuchen Sie einen anderen Namen oder eine E-Mail-Adresse.")).foregroundStyle(AppTheme.textSecondary)
                        }
                        ForEach(users.users.filter { $0.id != actor?.id && $0.globalRole.authorizationRole != .owner }) { user in
                            userRow(user)
                            Divider()
                        }
                        if users.canLoadMore {
                            Button(text("Показати ще", "Weitere anzeigen")) { Task { await users.loadMore() } }.disabled(users.isLoadingMore)
                        }
                        if users.isLoadingMore { ProgressView() }
                    }
                }
            }
        }
        .tint(AppTheme.accentPrimaryForeground)
        .refreshable { await refresh() }
        .task(id: principal) {
            pending = nil; users.reset(); access.reset()
            guard !principal.isEmpty else { return }
            await access.load(actorID: principal)
        }
        .task(id: searchKey) {
            let id = principal, requestedQuery = query
            guard !id.isEmpty else { return }
            users.invalidate(actorID: id, query: requestedQuery)
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard !Task.isCancelled else { return }
            await users.load(actorID: id, query: requestedQuery)
        }
        .task(id: users.users.map(\.id).joined(separator: "|") + "|" + String(access.isLoading)) {
            guard !principal.isEmpty, !access.isLoading else { return }
            await access.inspect(users.users.map(\.id), actorID: principal)
        }
        .confirmationDialog(text("Змінити доступ до довідника?", "Ratgeberzugriff ändern?"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            if let item = pending {
                Button(item.enabled ? text("Надати доступ", "Zugriff erteilen") : text("Відкликати доступ", "Zugriff entziehen"), role: item.enabled ? nil : .destructive) {
                    pending = nil
                    guard principal == item.actorID, isOwner else { return }
                    Task { await access.setAccess(item.enabled, userID: item.grant.id, knownUser: item.user, actorID: item.actorID, reviewed: item.grant) }
                }
            }
            Button(text("Скасувати", "Abbrechen"), role: .cancel) { pending = nil }
        } message: {
            if let item = pending {
                Text(item.identity + "\n" + (item.enabled ? text("Зможе публікувати, змінювати й приховувати всі матеріали довідника. Користувач отримає сповіщення.", "Kann alle Ratgeberinhalte veröffentlichen, ändern und ausblenden. Der Nutzer wird benachrichtigt.") : text("Більше не зможе редагувати довідник. Користувач отримає сповіщення.", "Kann den Ratgeber nicht mehr bearbeiten. Der Nutzer wird benachrichtigt.")))
            }
        }
        .alert(text("Помилка доступу", "Zugriffsfehler"), isPresented: Binding(get: { access.errorMessage != nil }, set: { if !$0 { access.errorMessage = nil } })) {
            Button(text("Гаразд", "OK")) { access.errorMessage = nil }
        } message: { Text(access.errorMessage ?? "") }
    }
    @ViewBuilder private func adaptiveRow<Identity: View, Action: View>(@ViewBuilder identity: () -> Identity, @ViewBuilder action: () -> Action) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) { identity().fixedSize(); Spacer(minLength: 12); action().fixedSize() }
            VStack(alignment: .leading, spacing: 12) { identity(); action() }
        }
    }
    private func retryButton(_ action: @escaping () async -> Void) -> some View {
        Button(text("Не вдалося завантажити. Повторити", "Laden fehlgeschlagen. Erneut versuchen")) { Task { await action() } }
    }
    @ViewBuilder private func userRow(_ user: AppUser) -> some View {
        let usable = (user.accountStatus == .active || user.accountStatus == .warned) && (user.blockState == .active || user.blockState == .warned)
        adaptiveRow {
            VStack(alignment: .leading, spacing: 4) {
                Text(user.preferredDisplayName).font(.headline)
                Text(user.email).font(.caption).foregroundStyle(AppTheme.textSecondary).textSelection(.enabled)
                if !usable { Text(text("Обмежений акаунт — доступ надати не можна", "Eingeschränktes Konto – keine Freigabe möglich")).font(.caption).foregroundStyle(AppTheme.textSecondary) }
            }
        } action: {
            if access.grants[user.id]?.enabled == true {
                Label(text("Має доступ", "Zugriff aktiv"), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            } else if access.grants[user.id] == nil {
                Button(text("Перевірити доступ", "Zugriff prüfen")) { Task { await access.inspect([user.id], actorID: principal) } }.font(.caption)
            } else {
                Button(text("Надати доступ", "Zugriff erteilen")) { review(user.id, enabled: true, user: user) }
                    .disabled(!usable || access.busyIDs.contains(user.id))
                    .accessibilityIdentifier("directoryAccess.grant.\(user.id)")
            }
        }
    }
    private var sortedEditorIDs: [String] {
        access.editorIDs.sorted { lhs, rhs in
            let comparison = LocalizationStore.compareForSorting(profile(lhs)?.preferredDisplayName ?? lhs, profile(rhs)?.preferredDisplayName ?? rhs)
            return comparison == .orderedSame ? lhs < rhs : comparison == .orderedAscending
        }
    }
    private func profile(_ id: String) -> AppUser? { access.profiles[id] ?? users.users.first { $0.id == id } }
    @ViewBuilder private func editorIdentity(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let user = profile(id) {
                Text(user.preferredDisplayName).font(.headline)
                Text(user.email).font(.caption).foregroundStyle(AppTheme.textSecondary).textSelection(.enabled)
            } else {
                Text(access.missingProfileIDs.contains(id) ? text("Профіль користувача відсутній", "Nutzerprofil nicht vorhanden") : text("Дані користувача не завантажено", "Nutzerdaten nicht geladen"))
                Text(verbatim: "ID: \(id)").font(.caption).foregroundStyle(AppTheme.textSecondary).textSelection(.enabled)
                if access.failedProfileIDs.contains(id) {
                    Button(text("Повторити", "Erneut versuchen")) { Task { await access.loadProfile(id, actorID: principal) } }
                }
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func review(_ id: String, enabled: Bool, user: AppUser? = nil) {
        guard isOwner, let grant = access.grants[id] else { return }
        let target = user ?? profile(id)
        pending = Review(actorID: principal, grant: grant, enabled: enabled, identity: target.map { "\($0.preferredDisplayName) · \($0.email)" } ?? "ID: \(id)", user: target)
    }
    private func refresh() async {
        guard !principal.isEmpty else { return }
        async let grants: Void = access.load(actorID: principal)
        async let candidates: Void = users.load(actorID: principal, query: query)
        _ = await (grants, candidates)
    }
}
