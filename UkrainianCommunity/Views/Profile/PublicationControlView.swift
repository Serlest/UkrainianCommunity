import SwiftUI

enum PublicationControlText {
    static func value(_ uk: String, _ de: String) -> String { DirectoryEditorText.value(uk, de) }
    static var title: String { value("Контроль публікацій", "Publikationsübersicht") }
    static var subtitle: String { value("Новини, події та результати автоматичних проходів.", "Nachrichten, Termine und Ergebnisse der automatischen Durchläufe.") }
    static var loadFailed: String { value("Не вдалося оновити дані. Перевірте з’єднання та спробуйте ще раз.", "Daten konnten nicht aktualisiert werden. Prüfen Sie die Verbindung und versuchen Sie es erneut.") }
    static var listChanged: String { value("Список змінився. Оновіть його, щоб продовжити.", "Die Liste hat sich geändert. Aktualisieren Sie sie, um fortzufahren.") }
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
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!; calendar.firstWeekday = 2; return calendar
    }()
    static func date(_ ms: Double?) -> String {
        guard let ms, ms.isFinite, ms >= 0, ms <= 253402300799000 else { return value("Немає даних", "Keine Daten") }
        return Date(timeIntervalSince1970: ms / 1000).formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: LocalizationStore.locale, calendar: calendar, timeZone: calendar.timeZone))
    }
    static func nextExpected(_ run: PublicationControlRun) -> Date? {
        guard let schedule = run.schedule, schedule.timeZone == "Europe/Vienna", let ms = run.scheduledAt ?? run.endedAt, ms.isFinite else { return nil }
        let base = Date(timeIntervalSince1970: ms / 1000)
        for offset in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: base)) else { continue }
            let dates = schedule.hours.filter { (0..<24).contains($0) }.flatMap { hour in
                schedule.minutes.filter { (0..<60).contains($0) }.compactMap { minute in
                    calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
                }
            }
            if let next = dates.filter({ $0 > base }).min() { return next }
        }
        return nil
    }
    static func remedy(_ code: String) -> String {
        switch code {
        case "restrictedSource": value("Перевірте доступ до джерела. Матеріал потребує доступного підтвердження.", "Prüfen Sie den Quellenzugriff. Der Inhalt benötigt einen zugänglichen Beleg.")
        case "capacity": value("Перевірте завершення попереднього проходу та наступний запланований запуск.", "Prüfen Sie den vorherigen Durchlauf und den nächsten geplanten Start.")
        case "sourceUnavailable": value("Перевірте доступність джерела та результат наступного проходу.", "Prüfen Sie die Erreichbarkeit der Quelle und den nächsten Durchlauf.")
        case "uncertainPublication": value("Звірте матеріал у вкладці «Публікації» перед повторною спробою.", "Gleichen Sie den Inhalt vor einem erneuten Versuch unter Publikationen ab.")
        default: value("Перевірте, які джерела залишилися неперевіреними. Повний результат ще не підтверджено.", "Prüfen Sie die noch offenen Quellen. Ein vollständiges Ergebnis ist noch nicht bestätigt.")
        }
    }

}
struct PublicationControlView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: PublicationControlStore
    @State private var section = "items"
    @State private var selectedRegion = "all"
    @State private var date = Date()
    @State private var choosingDate = false
    @State private var choosingRegion = false
    @State private var lastContextKey = ""
    @State private var clockDate = Date.now
    private let onOpen: (OwnerContentDraftKind, String) -> Void
    private var actor: String { authState.isAuthenticated && PermissionService.isAppOwner(user: authState.user) ? authState.user?.id ?? "" : "" }
    private var day: String {
        let parts = PublicationControlText.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    private var region: String? { selectedRegion == "all" ? nil : selectedRegion }
    private var key: String { actor + "|" + day + "|" + String(ProfileAccessIdentity(user: authState.user).hashValue) + "|" + String(describing: authState.sessionState) }
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
                    if section == "items" || section == "regions" { overviewCard(overview) }
                    else { synchronizationCard(overview) }
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.publicationControl")
        .task(id: key) {
            if lastContextKey != key { store.reset(); lastContextKey = key; choosingDate = false; choosingRegion = false }
            guard !actor.isEmpty else { return }
            await refresh(force: false)
        }
        .task(id: selectedRegion + "|" + section) {
            guard !actor.isEmpty, store.overview != nil else { return }
            if section == "items" { await store.loadItems(region: region) }
            if section == "history" { await store.loadRuns(region: region) }
        }
        .appRefreshable { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh(force: false) } }
        }
        .sheet(isPresented: $choosingRegion) {
            PublicationControlRegionSheet(selected: selectedRegion) { selectedRegion = $0 }
        }
        .sheet(isPresented: $choosingDate) {
            PublicationControlDateSheet(date: date) { selected in date = selected }
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                let previousToday = PublicationControlText.calendar.startOfDay(for: clockDate)
                clockDate = .now
                if PublicationControlText.calendar.isDate(date, inSameDayAs: previousToday),
                   !PublicationControlText.calendar.isDate(clockDate, inSameDayAs: previousToday) { date = clockDate }
            }
        }
    }
    private func overviewCard(_ value: PublicationControlOverview) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text("Дата публікацій", "Publikationsdatum")).font(.headline)
                    Button { choosingDate = true } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: "calendar").font(.system(size: 20))
                            Text(date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: LocalizationStore.locale, calendar: PublicationControlText.calendar, timeZone: PublicationControlText.calendar.timeZone)))
                                .font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down").font(.system(size: 14))
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(AppTheme.accentPrimaryForeground)
                        .accessibilityIdentifier("publicationControl.day")
                    Text(text("День за часом Відня", "Kalendertag nach Wiener Zeit")).font(.caption).foregroundStyle(AppTheme.textSecondary)
                }
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 20) { summaryMetrics(value) }
                } else {
                    HStack(alignment: .top, spacing: 24) { summaryMetrics(value) }
                }
                DisclosureGroup(text("Як рахуються публікації", "So werden Publikationen gezählt")) {
                    Text(text("За датою першої публікації у застосунку. Загальноавстрійські матеріали враховано один раз.", "Nach der ersten Veröffentlichung in der App. Österreichweite Inhalte werden einmal gezählt.")).font(.caption).foregroundStyle(AppTheme.textSecondary)
                    if (value.legacyTimeCount ?? 0) > 0 {
                        Text(text("Для перенесеної історії використано дату додавання матеріалу: точний час першої публікації раніше не завжди зберігався.", "Für übernommene Inhalte wird das Erstellungsdatum verwendet: Der genaue Zeitpunkt der ersten Veröffentlichung wurde früher nicht immer gespeichert.")).font(.caption).foregroundStyle(AppTheme.textSecondary)
                    }
                }
                synchronizationStatus(value)
            }
        }
    }
    private func synchronizationCard(_ value: PublicationControlOverview) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(text("Результати проходів", "Ergebnisse der Durchläufe")).font(.headline)
                Text(text("Показано останні результати, незалежно від дати публікації.", "Die letzten Ergebnisse werden unabhängig vom Publikationsdatum angezeigt.")).font(.caption).foregroundStyle(AppTheme.textSecondary)
                synchronizationStatus(value)
            }
        }
    }
    @ViewBuilder private func synchronizationStatus(_ value: PublicationControlOverview) -> some View {
        if (value.syncErrors ?? 0) > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(text("Частину звітів не отримано", "Einige Berichte fehlen"))
                } icon: {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 20))
                }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accentWarningForeground)
                    .accessibilityIdentifier("publicationControl.syncWarning")
                Text(text("Неповні результати. Звітів з помилкою: ", "Unvollständige Ergebnisse. Fehlerhafte Berichte: ") + String(value.syncErrors ?? 0))
                    .font(.caption).foregroundStyle(AppTheme.textSecondary)
                    .accessibilityIdentifier("publicationControl.syncWarning.count")
                if let issues = value.syncIssues, !issues.isEmpty {
                    DisclosureGroup(text("Звіти, що потребують перевірки", "Zu prüfende Berichte")) {
                        ForEach(Array(issues.prefix(20).enumerated()), id: \.offset) { _, issue in
                            VStack(alignment: .leading, spacing: 6) {
                                Text([issue.kind.map { PublicationControlText.kind($0) }, issue.region.map { PublicationControlText.region($0) }].compactMap { $0 }.joined(separator: " · ")).font(.subheadline)
                                if let detail = issue.detail { Text(verbatim: detail).font(.caption).textSelection(.enabled) }
                            }.fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Button(text("Оновити перегляд", "Ansicht aktualisieren")) { Task { await refresh() } }
                    .disabled(store.loading)
                    .accessibilityIdentifier("publicationControl.syncWarning.retry")
            }
        }
        Divider()
        Text(text("Успішна перевірка синхронізації: ", "Erfolgreiche Synchronisationsprüfung: ") + PublicationControlText.date(value.lastSuccessfulCheckAt ?? value.syncedAt)).font(.caption).foregroundStyle(AppTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        if let attempted = value.lastAttemptAt {
            Text(text("Остання спроба: ", "Letzter Versuch: ") + PublicationControlText.date(attempted)).font(.caption).foregroundStyle(AppTheme.textSecondary)
        }
        if value.syncedAt == nil || store.reportNow(at: clockDate) - (value.lastSuccessfulCheckAt ?? value.syncedAt ?? 0) > 2 * 3600000 {
            Label(text("Звіти застаріли. Останні зміни можуть бути відсутні.", "Berichte sind veraltet. Neueste Änderungen können fehlen."), systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(AppTheme.accentWarningForeground)
        }
    }
    @ViewBuilder private func summaryMetrics(_ value: PublicationControlOverview) -> some View {
        metric(PublicationControlText.kind("news"), count: value.news, icon: "newspaper")
        metric(PublicationControlText.kind("event"), count: value.events, icon: "calendar")
    }
    private func metric(_ title: String, count: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { HStack(alignment: .top, spacing: 10) { Image(systemName: icon).font(.system(size: 20)); Text(title).accessibilityIdentifier("publicationControl.metric." + icon).font(.subheadline).fixedSize(horizontal: false, vertical: true) }; Text(count.formatted()).font(.largeTitle.bold()).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading)
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
            Button { choosingRegion = true } label: {
                let title = selectedRegion == "all" ? text("Усі регіони", "Alle Regionen") : PublicationControlText.region(selectedRegion)
                if typeSize.isAccessibilitySize {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 18)).accessibilityHidden(true)
                        Text(title).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").font(.system(size: 14)).accessibilityHidden(true)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(12)
                        .foregroundStyle(selectedRegion == "all" ? AppTheme.textPrimary : .white)
                        .background(selectedRegion == "all" ? AppTheme.surfaceControl : AppTheme.accentPrimary, in: RoundedRectangle(cornerRadius: 18))
                } else {
                    AppFilterChip(title: title, systemImage: "mappin.and.ellipse", isSelected: selectedRegion != "all", trailingSystemImage: "chevron.down")
                }
            }.buttonStyle(.plain).accessibilityIdentifier("publicationControl.region")
        }
    }
    private var itemCards: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            if let error = store.itemsError { InlineMessageCard(style: .error, message: error); Button(PublicationControlText.retry) { Task { await store.loadItems(region: region) } } }
            if store.loadingItems || !store.hasLoadedItems && store.items.isEmpty && store.itemsError == nil { ProgressView().accessibilityIdentifier("publicationControl.loading.items") }
            if store.hasLoadedItems && store.items.isEmpty && !store.loadingItems && store.itemsError == nil { empty(text("За цю дату публікацій немає", "Keine Publikationen an diesem Tag")) }
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
                        Text(PublicationControlText.issue(code)).font(.subheadline.weight(.semibold))
                        Text(PublicationControlText.remedy(code)).font(.footnote).foregroundStyle(AppTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        DisclosureGroup(text("Технічні подробиці", "Technische Einzelheiten") + (entries.count > 1 ? " (\(entries.count))" : "")) {
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
    private var historyCards: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            Text(text("Історія отриманих звітів. Час із файлу позначається окремо, якщо звіт не містить часу завершення.", "Historie der eingegangenen Berichte. Fehlt die Abschlusszeit, wird die Dateizeit gesondert gekennzeichnet.")).font(.caption).foregroundStyle(AppTheme.textSecondary)
            if let error = store.runsError { InlineMessageCard(style: .error, message: error); Button(PublicationControlText.retry) { Task { await store.loadRuns(region: region) } } }
            ForEach(store.runs) { run in
                AppEditorSectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        runSummary(run, now: store.reportNow(at: clockDate), showsFreshness: false)
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
            if store.loadingRuns || !store.hasLoadedRuns && store.runs.isEmpty && store.runsError == nil { ProgressView().accessibilityIdentifier("publicationControl.loading.runs") }
            if store.hasLoadedRuns && store.runs.isEmpty && !store.loadingRuns && store.runsError == nil { empty(region == nil ? text("Звітів ще немає", "Noch keine Berichte") : text("За цим регіоном звітів немає", "Für diese Region liegen keine Berichte vor")) }
            if store.runCursor != nil { Button(text("Завантажити старіші проходи", "Ältere Durchläufe laden")) { Task { await store.loadRuns(region: region, more: true) } }.disabled(store.loadingRuns) }
        }
    }
    private func isStale(_ run: PublicationControlRun, now: Double) -> Bool {
        if let next = PublicationControlText.nextExpected(run), let schedule = run.schedule {
            return now > next.timeIntervalSince1970 * 1000 + Double(max(0, schedule.graceMinutes)) * 60000
        }
        return now - (run.endedAt ?? 0) > 26 * 3600000
    }
    private func runSummary(_ run: PublicationControlRun, now: Double, showsFreshness: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(PublicationControlText.kind(run.kind) + " · " + PublicationControlText.region(run.region)).font(.headline)
            Label(PublicationControlText.status(run.status), systemImage: run.status == "complete" ? "checkmark.circle" : "exclamationmark.triangle").font(.subheadline).foregroundStyle(run.status == "complete" ? AppTheme.accentSuccessForeground : AppTheme.accentWarningForeground)
            Text((run.timestampBasis == "reportFileModifiedAt" ? text("Час файлу: ", "Dateizeit: ") : "") + PublicationControlText.date(run.endedAt)).font(.caption).foregroundStyle(AppTheme.textSecondary)
            if showsFreshness && isStale(run, now: now) { Text(text("Новішого звіту немає — поточний стан невідомий", "Kein neuerer Bericht – aktueller Zustand unbekannt")).font(.caption).foregroundStyle(AppTheme.accentWarningForeground) }
            if showsFreshness, let next = PublicationControlText.nextExpected(run) {
                Text(text("Наступний запланований прохід: ", "Nächster geplanter Durchlauf: ") + PublicationControlText.date(next.timeIntervalSince1970 * 1000)).font(.caption).foregroundStyle(AppTheme.textSecondary)
            }
            if let complete = run.lastCompleteAt { Text(text("Останній повністю завершений прохід: ", "Letzter vollständig abgeschlossener Durchlauf: ") + PublicationControlText.date(complete)).font(.caption).foregroundStyle(AppTheme.textSecondary) }
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func empty(_ message: String) -> some View { AppEditorSectionCard { Text(message).foregroundStyle(AppTheme.textSecondary).frame(maxWidth: .infinity, alignment: .leading) } }
    private func refresh(force: Bool = true) async {
        let currentActor = actor
        guard !currentActor.isEmpty else { store.reset(); return }
        let currentKey = key
        await store.load(actor: currentActor, day: day, force: force)
        guard key == currentKey, actor == currentActor, !Task.isCancelled else { return }
        if section == "items" { await store.loadItems(region: region) }
        if section == "history" { await store.loadRuns(region: region) }
    }
}

private struct PublicationControlDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var date: Date
    let confirm: (Date) -> Void
    private let calendar = PublicationControlText.calendar
    var body: some View {
        NavigationStack {
            ScrollView {
                DatePicker(PublicationControlText.value("Дата публікацій", "Publikationsdatum"), selection: $date,
                           in: calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: .now))!...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
                    .padding().accessibilityIdentifier("publicationControl.calendar")
            }
            .navigationTitle(PublicationControlText.value("Дата", "Datum"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppStrings.Common.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.Common.done) { confirm(date); dismiss() }.accessibilityIdentifier("publicationControl.calendar.done")
                }
            }
        }
    }
}


private struct PublicationControlRegionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selected: String
    let confirm: (String) -> Void
    private let regions = ["all", "austria", "burgenland", "kaernten", "niederoesterreich", "oberoesterreich", "salzburg", "steiermark", "tirol", "vorarlberg", "wien", "unknown"]
    var body: some View {
        NavigationStack {
            List(regions, id: \.self) { region in
                Button {
                    confirm(region); dismiss()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(region == "all" ? PublicationControlText.value("Усі регіони", "Alle Regionen") : PublicationControlText.region(region))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if region == selected { Image(systemName: "checkmark").font(.system(size: 18, weight: .semibold)) }
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.foregroundStyle(AppTheme.textPrimary)
                    .accessibilityIdentifier("publicationControl.region." + region)
                    .accessibilityAddTraits(region == selected ? .isSelected : [])
                    .listRowBackground(AppTheme.surfacePrimary)
            }.scrollContentBackground(.hidden).background { AppBackgroundView() }
                .navigationTitle(PublicationControlText.value("Регіон", "Region"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(AppStrings.Common.cancel) { dismiss() } } }
        }
    }
}
