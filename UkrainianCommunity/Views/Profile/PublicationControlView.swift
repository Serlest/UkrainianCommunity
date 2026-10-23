import SwiftUI
import Combine
import FirebaseFunctions

nonisolated struct PublicationControlItem: Decodable, Sendable, Identifiable {
    let id: String
    let kind: String
    let contentId: String
    let titleUK: String
    let titleDE: String
    let region: String
    let firstPublicAt: Double?
    let sourceState: String
    let timingSource: String
    var title: String { LocalizationStore.language == .german ? titleDE : titleUK }
}
nonisolated struct PublicationControlIssue: Decodable, Sendable { let code: String; let detail: String }
nonisolated struct PublicationControlRun: Decodable, Sendable, Identifiable {
    let id: String
    let kind: String
    let region: String
    let runId: String
    let status: String
    let endedAt: Double?
    let timestampBasis: String
    let published: Int?
    let candidates: Int?
    let rejected: Int?
    let sourcesExpected: Int?
    let sourcesChecked: Int?
    let issues: [PublicationControlIssue]
    let issueCount: Int
    let publicationOnly: Bool
    var lastCompleteAt: Double? = nil
}
nonisolated struct PublicationControlRegion: Decodable, Sendable, Identifiable {
    let region: String
    let news: Int
    let events: Int
    var id: String { region }
}
nonisolated struct PublicationControlOverview: Decodable, Sendable {
    let day: String
    let serverTime: Double
    let news: Int
    let events: Int
    let regions: [PublicationControlRegion]
    let sources: [PublicationControlRun]
    let syncedAt: Double?
    var syncErrors: Int? = nil
    var legacyTimeCount: Int? = nil
}
nonisolated struct PublicationControlItemsPage: Decodable, Sendable { let items: [PublicationControlItem]; let cursor: String?; let total: Int }
nonisolated struct PublicationControlRunsPage: Decodable, Sendable { let runs: [PublicationControlRun]; let cursor: String? }
nonisolated private struct PublicationControlRequest: Encodable {
    let action: String
    let principalId: String
    var day: String? = nil
    var region: String? = nil
    var kind: String? = nil
    var cursor: String? = nil
}
@MainActor struct PublicationControlAPI {
    var overview: (String, String) async throws -> PublicationControlOverview
    var items: (String, String, String?, String?) async throws -> PublicationControlItemsPage
    var runs: (String, String?) async throws -> PublicationControlRunsPage
    private static func call<T: Decodable & Sendable>(_ request: PublicationControlRequest, as: T.Type) async throws -> T {
        var callable: Callable<PublicationControlRequest, T> = Functions.functions(region: "europe-west3").httpsCallable("getPublicationControl")
        callable.timeoutInterval = 30
        return try await callable.call(request)
    }
    static let live = Self(overview: { actor, day in try await call(.init(action: "overview", principalId: actor, day: day), as: PublicationControlOverview.self) },
        items: { actor, day, region, cursor in try await call(.init(action: "items", principalId: actor, day: day, region: region, cursor: cursor), as: PublicationControlItemsPage.self) },
        runs: { actor, cursor in try await call(.init(action: "runs", principalId: actor, cursor: cursor), as: PublicationControlRunsPage.self) })
}
@MainActor final class PublicationControlStore: ObservableObject {
    @Published private(set) var overview: PublicationControlOverview?
    private(set) var receivedAt = Date.now
    @Published private(set) var items: [PublicationControlItem] = []
    @Published private(set) var runs: [PublicationControlRun] = []
    @Published private(set) var loading = false
    @Published private(set) var loadingItems = false
    @Published private(set) var loadingRuns = false
    @Published private(set) var itemCursor: String?
    @Published private(set) var runCursor: String?
    @Published private(set) var error: String?
    @Published private(set) var itemsError: String?
    @Published private(set) var runsError: String?
    private let api: PublicationControlAPI
    private var generation = UUID()
    private var itemGeneration = UUID()
    private var actor: String?
    private var day = ""
    private var region: String?
    private var hasLoadedItems = false
    init(api: PublicationControlAPI? = nil) { self.api = api ?? .live }
    func reset() {
        generation = UUID(); itemGeneration = UUID(); actor = nil
        overview = nil; items = []; runs = []; itemCursor = nil; runCursor = nil
        loading = false; loadingItems = false; loadingRuns = false; error = nil; itemsError = nil; runsError = nil
        hasLoadedItems = false
    }
    func load(actor: String, day: String) async {
        if self.actor != actor || self.day != day { reset() }
        self.actor = actor; self.day = day; generation = UUID(); itemGeneration = UUID(); loadingItems = false; loadingRuns = false
        hasLoadedItems = false
        let token = generation
        loading = true; error = nil
        defer { if generation == token { loading = false } }
        do {
            let response = try await api.overview(actor, day)
            guard self.actor == actor, generation == token, !Task.isCancelled else { return }
            receivedAt = .now; overview = response
        } catch { if generation == token, !Task.isCancelled { self.error = PublicationControlText.loadFailed } }
    }
    func reportNow(at date: Date = .now) -> Double {
        guard let overview else { return date.timeIntervalSince1970 * 1000 }
        return overview.serverTime + max(0, date.timeIntervalSince(receivedAt)) * 1000
    }
    func loadItems(region: String?, more: Bool = false) async {
        guard let actor, !more || !loadingItems && itemCursor != nil else { return }
        if !more, self.region == region, loadingItems || (hasLoadedItems && itemsError == nil) { return }
        if !more {
            itemGeneration = UUID()
            if self.region != region { items = [] }
            itemCursor = nil
            hasLoadedItems = false
        }
        self.region = region
        let token = generation, itemToken = itemGeneration
        loadingItems = true; itemsError = nil
        defer { if generation == token, itemGeneration == itemToken { loadingItems = false } }
        do {
            let response = try await api.items(actor, day, region, more ? itemCursor : nil)
            guard self.actor == actor, generation == token, itemGeneration == itemToken, !Task.isCancelled else { return }
            if !more { items = [] }
            let known = Set(items.map(\.id)); items += response.items.filter { !known.contains($0.id) }; itemCursor = response.cursor
            hasLoadedItems = true
        } catch { if generation == token, itemGeneration == itemToken, !Task.isCancelled { itemsError = PublicationControlText.loadFailed } }
    }
    func loadRuns(more: Bool = false) async {
        guard let actor, !loadingRuns, !more || runCursor != nil else { return }
        let token = generation
        loadingRuns = true; runsError = nil
        defer { if generation == token { loadingRuns = false } }
        do {
            let response = try await api.runs(actor, more ? runCursor : nil)
            guard self.actor == actor, generation == token, !Task.isCancelled else { return }
            if !more { runs = [] }
            let known = Set(runs.map(\.id)); runs += response.runs.filter { !known.contains($0.id) }; runCursor = response.cursor
        } catch { if generation == token, !Task.isCancelled { runsError = PublicationControlText.loadFailed } }
    }
}
enum PublicationControlText {
    static func value(_ uk: String, _ de: String) -> String { DirectoryEditorText.value(uk, de) }
    static var title: String { value("Контроль публікацій", "Publikationsübersicht") }
    static var subtitle: String { value("Новини, події та результати автоматичних проходів.", "Nachrichten, Termine und Ergebnisse der automatischen Durchläufe.") }
    static var loadFailed: String { value("Не вдалося оновити дані. Перевірте з’єднання та спробуйте ще раз.", "Daten konnten nicht aktualisiert werden. Prüfen Sie die Verbindung und versuchen Sie es erneut.") }
    static var retry: String { value("Спробувати ще раз", "Erneut versuchen") }
    static func region(_ code: String) -> String {
        if code == "austria" { return value("Уся Австрія", "Ganz Österreich") }
        if code == "unknown" { return value("Регіон не вказано", "Region nicht angegeben") }
        return AustrianFederalState(rawValue: code)?.displayName ?? code
    }
    static func kind(_ code: String) -> String { code == "news" ? value("Новини", "Nachrichten") : value("Події", "Termine") }
    static func status(_ code: String) -> String {
        switch code {
        case "complete": value("Прохід завершено", "Durchlauf abgeschlossen")
        case "partial": value("Перевірено частково", "Teilweise geprüft")
        case "blocked": value("Прохід заблоковано", "Durchlauf blockiert")
        case "failed": value("Помилка проходу", "Durchlauf fehlgeschlagen")
        default: value("Немає підтвердженого результату", "Kein bestätigtes Ergebnis")
        }
    }
    static func issue(_ code: String) -> String {
        switch code {
        case "capacity": value("Технічна затримка або зайнятий ресурс", "Technische Verzögerung oder belegte Ressource")
        case "restrictedSource": value("Джерело обмежує доступ", "Quelle beschränkt den Zugriff")
        case "sourceUnavailable": value("Джерело не вдалося перевірити", "Quelle konnte nicht geprüft werden")
        case "uncertainPublication": value("Публікація потребує звірки", "Publikation muss abgeglichen werden")
        case "invalidReportTime": value("Час завершення звіту некоректний", "Ungültige Abschlusszeit im Bericht")
        case "unsupportedReport": value("Формат звіту потребує перевірки", "Berichtsformat muss geprüft werden")
        default: value("Покриття джерел неповне", "Quellenabdeckung ist unvollständig")
        }
    }
    static func date(_ ms: Double?) -> String {
        guard let ms else { return value("Немає даних", "Keine Daten") }
        return Date(timeIntervalSince1970: ms / 1000).formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(LocalizationStore.locale))
    }
}
struct PublicationControlView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var store: PublicationControlStore
    @State private var section = "items"
    @State private var selectedRegion = "all"
    @State private var date = Date()
    @State private var clockDate = Date.now
    private let onOpen: (OwnerContentDraftKind, String) -> Void
    private var actor: String { PermissionService.isAppOwner(user: authState.user) ? authState.user?.id ?? "" : "" }
    private var day: String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Europe/Vienna"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    private var region: String? { selectedRegion == "all" ? nil : selectedRegion }
    private var key: String { actor + "|" + day }
    @MainActor init(api: PublicationControlAPI? = nil, onOpen: @escaping (OwnerContentDraftKind, String) -> Void) {
        _store = StateObject(wrappedValue: PublicationControlStore(api: api ?? MockContentBuilder.publicationControlFixture() ?? .live)); self.onOpen = onOpen
    }
    private func text(_ uk: String, _ de: String) -> String { PublicationControlText.value(uk, de) }
    var body: some View {
        AdminScreenShell(title: PublicationControlText.title, subtitle: PublicationControlText.subtitle) {
            if actor.isEmpty { ContentUnavailableView(text("Лише для власника", "Nur für Eigentümer"), systemImage: "lock") }
            else {
                if let error = store.error {
                    InlineMessageCard(style: .error, message: error)
                    Button(PublicationControlText.retry) { Task { await refresh() } }
                }
                if store.loading { ProgressView().frame(maxWidth: .infinity) }
                if let overview = store.overview {
                    overviewCard(overview)
                    filters
                    switch section {
                    case "regions": regionCards(overview)
                    case "issues": issueCards(overview)
                    case "history": historyCards
                    default: itemCards
                    }
                }
            }
        }
        .accessibilityIdentifier("screen.publicationControl")
        .task(id: key) {
            guard !actor.isEmpty else { store.reset(); return }
            await refresh()
        }
        .task(id: selectedRegion + "|" + section) {
            guard !actor.isEmpty, store.overview != nil else { return }
            if section == "items" { await store.loadItems(region: region) }
            if section == "history", store.runs.isEmpty { await store.loadRuns() }
        }
        .appRefreshable { await refresh() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                clockDate = .now
            }
        }
    }
    private func overviewCard(_ value: PublicationControlOverview) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text("Дата публікацій", "Publikationsdatum")).font(.headline)
                    DatePicker(text("Дата публікацій", "Publikationsdatum"), selection: $date, in: Date.now.addingTimeInterval(-29 * 86400)...Date.now, displayedComponents: .date).tint(AppTheme.accentPrimary)
                        .labelsHidden().datePickerStyle(.compact)
                        .environment(\.timeZone, TimeZone(identifier: "Europe/Vienna")!)
                }
                HStack(spacing: 24) {
                    metric(PublicationControlText.kind("news"), count: value.news, icon: "newspaper")
                    metric(PublicationControlText.kind("event"), count: value.events, icon: "calendar")
                }
                DisclosureGroup(text("Як рахуються публікації", "So werden Publikationen gezählt")) {
                    Text(text("За датою першої публікації у застосунку. Загальноавстрійські матеріали враховано один раз.", "Nach der ersten Veröffentlichung in der App. Österreichweite Inhalte werden einmal gezählt.")).font(.caption).foregroundStyle(AppTheme.textSecondary)
                    if (value.legacyTimeCount ?? 0) > 0 {
                        Text(text("Для перенесеної історії використано дату додавання матеріалу: точний час першої публікації раніше не завжди зберігався.", "Für übernommene Inhalte wird das Erstellungsdatum verwendet: Der genaue Zeitpunkt der ersten Veröffentlichung wurde früher nicht immer gespeichert.")).font(.caption).foregroundStyle(AppTheme.textSecondary)
                    }
                }
                if (value.syncErrors ?? 0) > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(text("Частину звітів не отримано", "Einige Berichte fehlen"), systemImage: "exclamationmark.triangle")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accentWarningForeground)
                            .accessibilityIdentifier("publicationControl.syncWarning")
                        Text(text("Неповні результати. Звітів з помилкою: ", "Unvollständige Ergebnisse. Fehlerhafte Berichte: ") + String(value.syncErrors ?? 0))
                            .font(.caption).foregroundStyle(AppTheme.textSecondary)
                            .accessibilityIdentifier("publicationControl.syncWarning.count")
                        Button(PublicationControlText.retry) { Task { await refresh() } }
                            .disabled(store.loading)
                            .accessibilityIdentifier("publicationControl.syncWarning.retry")
                    }
                }
                Divider()
                Text(text("Звіти оновлено: ", "Berichte aktualisiert: ") + PublicationControlText.date(value.syncedAt)).font(.caption).foregroundStyle(AppTheme.textSecondary)
                if value.syncedAt == nil || store.reportNow(at: clockDate) - (value.syncedAt ?? 0) > 2 * 3600000 {
                    Label(text("Звіти застаріли. Останні зміни можуть бути відсутні.", "Berichte sind veraltet. Neueste Änderungen können fehlen."), systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(AppTheme.accentWarningForeground)
                }
            }
        }
    }
    private func metric(_ title: String, count: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Label(title, systemImage: icon).font(.subheadline); Text(count.formatted()).font(.largeTitle.bold()).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppChoiceStrip(options: ["items", "regions", "issues", "history"], selection: $section,
                           title: { code in
                switch code {
                case "regions": text("Регіони", "Regionen")
                case "issues": text("Проблеми", "Probleme")
                case "history": text("Проходи", "Durchläufe")
                default: text("Публікації", "Publikationen")
                }
            }, identifier: { "publicationControl.tab." + $0 })
            Menu {
                Picker(text("Регіон", "Region"), selection: $selectedRegion) {
                Text(text("Усі регіони", "Alle Regionen")).tag("all")
                ForEach(["austria", "burgenland", "kaernten", "niederoesterreich", "oberoesterreich", "salzburg", "steiermark", "tirol", "vorarlberg", "wien", "unknown"], id: \.self) { Text(PublicationControlText.region($0)).tag($0) }
                }
            } label: {
                AppFilterChip(title: selectedRegion == "all" ? text("Усі регіони", "Alle Regionen") : PublicationControlText.region(selectedRegion),
                              systemImage: "mappin.and.ellipse", isSelected: selectedRegion != "all", trailingSystemImage: "chevron.down")
            }.buttonStyle(.plain).accessibilityIdentifier("publicationControl.region")
        }
    }
    @ViewBuilder private var itemCards: some View {
        if let error = store.itemsError { InlineMessageCard(style: .error, message: error); Button(PublicationControlText.retry) { Task { await store.loadItems(region: region) } } }
        if store.loadingItems { ProgressView() }
        if store.items.isEmpty && !store.loadingItems && store.itemsError == nil { empty(text("За цю дату публікацій немає", "Keine Publikationen an diesem Tag")) }
        ForEach(store.items) { item in
            Button {
                guard item.sourceState == "approved", let kind = OwnerContentDraftKind(rawValue: item.kind) else { return }
                onOpen(kind, item.contentId)
            } label: {
                AppEditorSectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.title).font(.headline).foregroundStyle(AppTheme.textPrimary)
                        Text(PublicationControlText.kind(item.kind) + " · " + PublicationControlText.region(item.region)).font(.caption).foregroundStyle(AppTheme.textSecondary)
                        Text((item.timingSource == "legacyCreation" ? text("Додано: ", "Erstellt: ") : "") + PublicationControlText.date(item.firstPublicAt)).font(.caption).foregroundStyle(AppTheme.textSecondary)
                        if item.sourceState != "approved" { Label(text("Більше не у відкритому доступі", "Nicht mehr öffentlich verfügbar"), systemImage: "archivebox").font(.caption).foregroundStyle(AppTheme.textSecondary) }
                        else { Label(text("Відкрити матеріал", "Inhalt öffnen"), systemImage: "arrow.up.right").font(.subheadline) }
                    }
                }
            }.buttonStyle(.plain).disabled(item.sourceState != "approved").accessibilityIdentifier("publicationControl.item.\(item.contentId)")
        }
        if store.itemCursor != nil { Button(text("Показати ще", "Weitere anzeigen")) { Task { await store.loadItems(region: region, more: true) } }.disabled(store.loadingItems) }
    }
    @ViewBuilder private func regionCards(_ overview: PublicationControlOverview) -> some View {
        ForEach(overview.regions.filter { (region == nil || $0.region == region) && ($0.region != "unknown" || $0.news + $0.events > 0 || region == "unknown") }) { item in
            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    AppEditorSectionTitle(title: PublicationControlText.region(item.region))
                    Text(text("Новини: \(item.news) · Події: \(item.events)", "Nachrichten: \(item.news) · Termine: \(item.events)"))
                    if item.region != "unknown" { sourceRows(overview, region: item.region) }
                    Button(text("Переглянути публікації", "Publikationen anzeigen")) { selectedRegion = item.region; section = "items" }
                }
            }
        }
    }
    @ViewBuilder private func sourceRows(_ overview: PublicationControlOverview, region: String) -> some View {
        ForEach(region == "austria" ? ["news"] : ["news", "event"], id: \.self) { kind in
            if let run = overview.sources.first(where: { $0.region == region && $0.kind == kind }) { runSummary(run, now: store.reportNow(at: clockDate)) }
            else { Label(PublicationControlText.kind(kind) + ": " + text("звіт ще не отримано", "noch kein Bericht eingegangen"), systemImage: "questionmark.circle").font(.subheadline).foregroundStyle(AppTheme.textSecondary) }
        }
    }
    @ViewBuilder private func issueCards(_ overview: PublicationControlOverview) -> some View {
        Text(text("Останні перевірки джерел. Часткова перевірка означає, що перевірено не всі джерела.", "Letzte Quellenprüfungen. Teilweise geprüft bedeutet: Nicht alle Quellen wurden geprüft.")).font(.footnote).foregroundStyle(AppTheme.textSecondary)
        let affected = overview.sources.filter { (region == nil || $0.region == region) && ($0.status != "complete" || isStale($0, now: store.reportNow(at: clockDate))) }
        let expected = ["austria", "burgenland", "kaernten", "niederoesterreich", "oberoesterreich", "salzburg", "steiermark", "tirol", "vorarlberg", "wien"].filter { region == nil || $0 == region }
        let missing = expected.flatMap { code in (code == "austria" ? ["news"] : ["news", "event"]).filter { kind in !overview.sources.contains(where: { $0.region == code && $0.kind == kind }) }.map { code + "|" + $0 } }
        if !missing.isEmpty {
            AppEditorSectionCard {
                DisclosureGroup(text("Звіти ще не отримано: \(missing.count)", "Noch ausstehende Berichte: \(missing.count)")) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(missing, id: \.self) { key in
                            let parts = key.split(separator: "|").map(String.init)
                            Text(PublicationControlText.kind(parts[1]) + " · " + PublicationControlText.region(parts[0])).font(.caption).foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
        }
        if affected.isEmpty { empty(text("У отриманих звітах проблем не вказано. Відсутність звітів не означає, що все перевірено.", "In den erhaltenen Berichten sind keine Probleme angegeben. Fehlende Berichte bedeuten keine vollständige Prüfung.")) }
        ForEach(affected) { run in
            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    runSummary(run, now: store.reportNow(at: clockDate))
                    let grouped = Dictionary(grouping: run.issues, by: \.code)
                    ForEach(grouped.keys.sorted(), id: \.self) { code in
                        let entries = grouped[code] ?? []
                        DisclosureGroup(PublicationControlText.issue(code) + (entries.count > 1 ? " (\(entries.count))" : "")) {
                            ForEach(Array(Set(entries.map(\.detail))).sorted(), id: \.self) { detail in
                                Text(verbatim: detail).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    if run.issueCount > run.issues.count { Text(text("Інші зауваження: \(run.issueCount - run.issues.count)", "Weitere Hinweise: \(run.issueCount - run.issues.count)" )).font(.caption).foregroundStyle(AppTheme.textSecondary) }
                }
            }
        }
    }
    @ViewBuilder private var historyCards: some View {
        Text(text("Історія отриманих звітів. Час із файлу позначається окремо, якщо звіт не містить часу завершення.", "Historie der eingegangenen Berichte. Fehlt die Abschlusszeit, wird die Dateizeit gesondert gekennzeichnet.")).font(.caption).foregroundStyle(AppTheme.textSecondary)
        if let error = store.runsError { InlineMessageCard(style: .error, message: error); Button(PublicationControlText.retry) { Task { await store.loadRuns() } } }
        ForEach(store.runs.filter { region == nil || $0.region == region }) { run in
            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    runSummary(run, now: store.reportNow(at: clockDate))
                    Text(text("Опубліковано за звітом: ", "Laut Bericht veröffentlicht: ") + (run.published.map(String.init) ?? "—")).font(.subheadline)
                    if let candidates = run.candidates {
                        Text(text("Опрацьовано кандидатів: ", "Bearbeitete Kandidaten: ") + String(candidates) + (run.rejected.map { text(" · Відхилено / пропущено: \($0)", " · Abgelehnt / übersprungen: \($0)") } ?? "")).font(.caption).foregroundStyle(AppTheme.textSecondary)
                    }
                    if let checked = run.sourcesChecked { Text(text("Перевірено джерел: ", "Geprüfte Quellen: ") + String(checked) + (run.sourcesExpected.map { " / \($0)" } ?? "")).font(.caption).foregroundStyle(AppTheme.textSecondary) }
                    if run.publicationOnly { Text(text("Продовження підготовленої публікації", "Fortsetzung einer vorbereiteten Publikation")).font(.caption) }
                    DisclosureGroup(text("Подробиці проходу", "Details des Durchlaufs")) {
                        Text(verbatim: run.runId).font(.caption).textSelection(.enabled)
                        ForEach(Array(run.issues.enumerated()), id: \.offset) { _, issue in Text(PublicationControlText.issue(issue.code) + "\n" + issue.detail).font(.caption).textSelection(.enabled) }
                    }
                }
            }
        }
        if store.loadingRuns { ProgressView() }
        if store.runs.isEmpty && !store.loadingRuns && store.runsError == nil { empty(text("Звітів ще немає", "Noch keine Berichte")) }
        if store.runCursor != nil { Button(text("Завантажити старіші проходи", "Ältere Durchläufe laden")) { Task { await store.loadRuns(more: true) } }.disabled(store.loadingRuns) }
    }
    private func isStale(_ run: PublicationControlRun, now: Double) -> Bool { now - (run.endedAt ?? 0) > (run.kind == "news" ? 3 : 26) * 3600000 }
    private func runSummary(_ run: PublicationControlRun, now: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(PublicationControlText.kind(run.kind) + " · " + PublicationControlText.region(run.region)).font(.headline)
            Label(PublicationControlText.status(run.status), systemImage: run.status == "complete" ? "checkmark.circle" : "exclamationmark.triangle").font(.subheadline).foregroundStyle(run.status == "complete" ? AppTheme.accentSuccessForeground : AppTheme.accentWarningForeground)
            Text((run.timestampBasis == "reportFileModifiedAt" ? text("Час файлу: ", "Dateizeit: ") : "") + PublicationControlText.date(run.endedAt)).font(.caption).foregroundStyle(AppTheme.textSecondary)
            if isStale(run, now: now) { Text(text("Новішого звіту немає — поточний стан невідомий", "Kein neuerer Bericht – aktueller Zustand unbekannt")).font(.caption).foregroundStyle(AppTheme.accentWarningForeground) }
            if let complete = run.lastCompleteAt { Text(text("Останній повністю завершений прохід: ", "Letzter vollständig abgeschlossener Durchlauf: ") + PublicationControlText.date(complete)).font(.caption).foregroundStyle(AppTheme.textSecondary) }
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func empty(_ message: String) -> some View { AppEditorSectionCard { Text(message).foregroundStyle(AppTheme.textSecondary).frame(maxWidth: .infinity, alignment: .leading) } }
    private func refresh() async {
        let currentActor = actor
        guard !currentActor.isEmpty else { store.reset(); return }
        await store.load(actor: currentActor, day: day)
        guard actor == currentActor, !Task.isCancelled else { return }
        if section == "items" { await store.loadItems(region: region) }
        if section == "history" { await store.loadRuns() }
    }
}
