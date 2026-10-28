import SwiftUI
import UniformTypeIdentifiers

struct SeasonalPackageFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SeasonalManagementView: View {
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var seasonalStore:SeasonalStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @StateObject private var model: SeasonalManagementModel
    @MainActor init(model: SeasonalManagementModel? = nil) { _model = StateObject(wrappedValue: model ?? SeasonalManagementModel()) }
    @State private var editing: SeasonalTheme?
    @State private var presets: [SeasonalTheme] = {
        var items=[SeasonalTheme.halloweenScene(),.gtaVI(),.christmas(),.newYear()]
        for i in items.indices {
            items[i].id="uac.preset."+["halloween","gta","christmas","newyear"][i]
            items[i].name=SeasonalText.value(["presetHalloween","presetGTA","presetChristmas","presetNewYear"][i],items[i].name)
        }
        return items
    }()
    @State private var imports = false
    @State private var exports = false
    @State private var exportFile = SeasonalPackageFile(data: Data())
    @State private var confirmation: Confirmation?
    private enum Confirmation: Identifiable {
        case leave, reload, publish, disable, remove(String)
        var id: String { String(describing: self) }
    }
    private var owner: Bool { PermissionService.isAppOwner(user: authState.user) }

    var body: some View {
        PushedScreenShell(title: SeasonalText.title, subtitle: SeasonalText.subtitle, tabBarHidden: true, backAction: attemptClose) {
            if !owner {
                Text(SeasonalText.ownerOnly)
            } else {
                content
            }
        }
        .accessibilityIdentifier("seasonal.management")
        .task(id: ProfileAccessIdentity(user: authState.user)) {
            editing = nil; imports = false; exports = false; confirmation = nil
            model.reset()
            await model.load(user: authState.user)
        }
        .sheet(item: $editing) { theme in
            SeasonalThemeEditor(theme: theme) { updated in
                guard owner, model.hasLoaded else { return }
                model.library.manualThemeID=nil
                if let index = model.library.themes.firstIndex(where: { $0.id == updated.id }) {
                    model.library.themes[index] = updated
                } else { model.library.themes.append(updated) }
            }
        }
        .confirmationDialog(confirmationTitle, isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
            switch confirmation {
            case .leave:
                Button(SeasonalText.value("discardAction", "Änderungen verwerfen"), role: .destructive) { dismiss() }
            case .reload:
                Button(SeasonalText.value("reloadDiscard", "Neu laden und Änderungen verwerfen"), role: .destructive) { Task { await model.load(user: authState.user) } }
            case .publish:
                Button(SeasonalText.value("publish", "Zeitplan veröffentlichen")) { Task { await model.save(user: authState.user, publish: true) } }
            case .remove(let id):
                Button(AppStrings.Action.delete, role: .destructive) { if model.library.manualThemeID==id { model.library.manualThemeID=nil };model.library.themes.removeAll { $0.id == id } }
            case .disable:
                Button(SeasonalText.value("disable", "Für alle ausschalten"), role: .destructive) { Task { await model.save(user: authState.user, publish: true, disable: true) } }
            case nil: EmptyView()
            }
            Button(AppStrings.Action.cancel, role: .cancel) {}
        }
        .fileImporter(isPresented: $imports, allowedContentTypes: [.json]) { result in
            do {
                guard owner, model.hasLoaded else { throw SeasonalError.ownerOnly }
                let url = try result.get()
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                guard let size = values.fileSize, size <= 240_000 else { throw SeasonalError.invalidPackage }
                let imported = try SeasonalLibrary.decode(Data(contentsOf: url))
                guard model.library.themes.count + imported.themes.count <= 12 else { throw SeasonalError.invalidPackage }
                // Import is always a disabled copy: it cannot accidentally activate a package.
                model.library.themes += imported.themes.map { theme in
                    var copy = theme; copy.id = UUID().uuidString; copy.isEnabled = false; return copy
                }
            } catch { if (error as NSError).code != NSUserCancelledError { model.message = error.localizedDescription } }
        }
        .fileExporter(isPresented: $exports, document: exportFile, contentType: .json, defaultFilename: "UAC-seasonal-library") { result in
            if case .failure(let error) = result, (error as NSError).code != NSUserCancelledError { model.message = error.localizedDescription }
        }
        .interactiveDismissDisabled(model.hasChanges || model.isSaving)
    }

    private var content: some View {
        VStack(spacing: AppTheme.sectionSpacing) {
            if model.isLoading { ProgressView(AppStrings.Common.loading).frame(maxWidth:.infinity,minHeight:44) }
            quickScenes
            if let message = model.message {
                Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(AppTheme.textPrimary).accessibilityIdentifier("seasonal.status")
            }
            Button {
                if model.hasChanges { confirmation = .reload } else { Task { await model.load(user: authState.user) } }
            } label: {
                Text(model.hasLoaded ? SeasonalText.value("reload", "Neu laden") : AppStrings.Action.retry).frame(minHeight: 44)
            }.disabled(model.isSaving)
            if model.hasLoaded {
                ProfileSectionCard(title: SeasonalText.value("library", "Bibliothek")) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(SeasonalText.value("libraryHint", "Themen bleiben für das nächste Jahr erhalten. Speichern ändert nur die Bibliothek; der veröffentlichte Zeitplan bleibt bestehen."))
                            .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                        ForEach(model.library.themes) { theme in
                            Button { editing = theme } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: "sparkles").foregroundStyle(AppTheme.accentPrimaryForeground)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(theme.name).foregroundStyle(AppTheme.textPrimary)
                                        Text(model.published.manualThemeID == theme.id ? SeasonalText.value("manualOn","Jetzt aktiv · bis zum Ausschalten"):SeasonalText.value(theme.isEnabled ? "scheduled" : "archived", theme.isEnabled ? "Im Zeitplan" : "Gespeichert · ausgeschaltet"))
                                            .font(.caption).foregroundStyle(AppTheme.textSecondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.forward").foregroundStyle(AppTheme.textSecondary)
                                }.frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("seasonal.theme.\(theme.id)")
                            .contextMenu {
                                Button(SeasonalText.value("duplicate", "Kopie erstellen"), systemImage: "doc.on.doc") {
                                    var copy = theme; copy.id = UUID().uuidString; copy.isEnabled = false
                                    editing = copy
                                }.disabled(model.library.themes.count >= 12)
                                Button(AppStrings.Action.delete, role: .destructive) { confirmation = .remove(theme.id) }
                            }
                        }
                        Menu {
                            Button(SeasonalText.value("presetHalloween", "Halloween")) { editing = .halloweenScene() }
                            Button(SeasonalText.value("presetGTA", "GTA VI · Vice Nights")) { editing = .gtaVI() }
                            Button(SeasonalText.value("presetChristmas", "Weihnachten")) { editing = .christmas() }
                            Button(SeasonalText.value("presetNewYear", "Neujahr")) { editing = .newYear() }
                        } label: {
                            Label(SeasonalText.value("addScene", "Szene hinzufügen"), systemImage: "plus.circle")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.accessibilityIdentifier("seasonal.library.addScene").disabled(model.library.themes.count >= 12)
                        Button { imports = true } label: {
                            Label(SeasonalText.value("import", "Themenpaket importieren"), systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.disabled(model.library.themes.count >= 12)
                        Button {
                            do { exportFile = SeasonalPackageFile(data: try model.library.encoded()); exports = true }
                            catch { model.message = error.localizedDescription }
                        } label: {
                            Label(SeasonalText.value("export", "Bibliothek exportieren"), systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.disabled(!model.isValid)
                        Button { Task { await model.save(user: authState.user) } } label: {
                            Text(SeasonalText.value("save", "Bibliothek speichern")).frame(minHeight: 44)
                        }
                            .buttonStyle(.borderedProminent).disabled(!model.hasChanges || !model.isValid)
                            .accessibilityIdentifier("seasonal.saveLibrary")
                        if !model.isValid { Text(SeasonalText.invalid).foregroundStyle(.red).font(.footnote) }
                    }.disabled(model.isSaving)
                }
                ProfileSectionCard(title: SeasonalText.value("publication", "Für die Community")) {
                    if model.savedLibrary.themes.contains(where:{$0.isEnabled && $0.isComposedScene}) {
                        Text(SeasonalText.value("sceneUpdateHint","Dieses Design benötigt die aktualisierte App. Ältere Versionen zeigen die Oberfläche ohne die neuen Dekorationen."))
                            .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        if model.published.manualThemeID != nil { Text(SeasonalText.value("manualCalendarHint","Die manuelle Szene ersetzt den Zeitplan vorübergehend. Ihre gespeicherten Termine bleiben erhalten.")).font(.footnote).foregroundStyle(AppTheme.textSecondary) }
                        Text(SeasonalText.value("publicationHint", "Veröffentlicht werden nur gespeicherte, eingeschaltete Themen. Beginn und Ende gelten in der gewählten Zeitzone. Bei Überschneidung gewinnt die höhere Priorität."))
                            .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                        Text(SeasonalText.value("publishedCount", "Themen im veröffentlichten Zeitplan") + ": \(model.published.themes.count)")
                        ForEach(model.published.themes) { theme in Text(theme.name).font(.callout) }
                        Button { confirmation = .publish } label: {
                            Text(model.published.manualThemeID == nil ? SeasonalText.value("publish", "Zeitplan veröffentlichen"):SeasonalText.value("resumeSchedule","Zum Zeitplan wechseln")).frame(minHeight: 44)
                        }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.hasChanges || !model.hasPublicationChanges || model.isSaving)
                            .accessibilityIdentifier("seasonal.publish")
                        Button(role: .destructive) { confirmation = .disable } label: {
                            Text(SeasonalText.value("disable", "Für alle ausschalten")).frame(minHeight: 44)
                        }
                            .disabled(model.published.themes.isEmpty || model.isSaving)
                        Text(SeasonalText.value("offline", "Bereits geladene Pakete funktionieren offline. Ein vorzeitiges Ausschalten erreicht offline befindliche Geräte erst bei der nächsten Verbindung."))
                            .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                    }
                }
                if model.isSaving { ProgressView(AppStrings.Common.loading) }
            }
        }
    }
    private var quickOptions:[SeasonalTheme] {
        let defaults=presets.map { preset in model.savedLibrary.themes.first{$0.id==preset.id} ?? preset }
        return defaults+model.savedLibrary.themes.filter { scene in !presets.contains{$0.id==scene.id} }
    }
    private func needsLiveUpdate(_ scene:SeasonalTheme) -> Bool {
        guard let published=model.published.themes.first(where:{$0.id==scene.id}) else { return false }
        var live=scene;if model.published.manualThemeID != nil { live.isEnabled=true }
        return published != live
    }
    private var quickScenes:some View {
        ProfileSectionCard(title:SeasonalText.value("quickScenes","Szene auswählen")) {
            VStack(alignment:.leading,spacing:14) {
                Text(SeasonalText.value("oneSceneHint","Eine Szene für die gesamte App. Einschalten ersetzt die bisherige Szene. Einstellungen und Zeitpläne bleiben in der Bibliothek erhalten."))
                    .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                if !model.published.themes.isEmpty {
                    Button(role:.destructive) { Task { await model.save(user:authState.user,publish:true,disable:true) } } label: {
                        Label(SeasonalText.value("disable","Für alle ausschalten"),systemImage:"power").frame(minHeight:44)
                    }.accessibilityIdentifier("seasonal.quick.off")
                }
                TimelineView(.periodic(from:.now,by:1)) { clock in
                let currentID=SeasonalSection.allCases.lazy.compactMap { model.published.active(at:clock.date,section:$0)?.id }.first
                ForEach(quickOptions) { preset in
                    let scene=model.savedLibrary.themes.first(where:{$0.id==preset.id}) ?? preset
                    let active=currentID==scene.id
                    let update=needsLiveUpdate(scene)
                    VStack(alignment:.leading,spacing:10) {
                        HStack(spacing:12) {
                            Image(systemName:scene.elements.contains{$0.artwork == .snowflake} ? "snowflake":"sparkles")
                                .font(.title2).foregroundStyle(AppTheme.accentPrimaryForeground).frame(width:32)
                            VStack(alignment:.leading,spacing:3) {
                                Text(scene.name).font(.headline).foregroundStyle(AppTheme.textPrimary)
                                if active { Text(model.published.manualThemeID != nil ? SeasonalText.value("manualOn","Jetzt aktiv · bis zum Ausschalten"):SeasonalText.value("calendarOn","Jetzt laut Zeitplan aktiv")).font(.caption).foregroundStyle(AppTheme.textSecondary) }
                            }
                        }
                        let controls=textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:10)):AnyLayout(HStackLayout(spacing:10))
                        controls {
                            Button { guard owner else { return };seasonalStore.preview(scene);dismiss() } label: {
                                Label(SeasonalText.value("quickPreview","Vorschau"),systemImage:"eye").font(.subheadline.weight(.semibold)).frame(maxWidth:.infinity,minHeight:44)
                            }.buttonStyle(.bordered).disabled(model.hasChanges).accessibilityLabel(SeasonalText.value("quickPreview","Vorschau")+": "+scene.name).accessibilityIdentifier("seasonal.quick.preview."+scene.id)
                            Button { Task { if active && !update { await model.save(user:authState.user,publish:true,disable:true) } else if active && update && model.published.manualThemeID == nil { await model.save(user:authState.user,publish:true) } else { await model.activate(scene,user:authState.user) } } } label: {
                                Text(active && update ? SeasonalText.value("updateScene","Aktualisieren"):SeasonalText.value(active ? "turnOff":"turnOn",active ? "Aus":"Ein")).frame(maxWidth:.infinity,minHeight:44)
                            }.buttonStyle(.borderedProminent).disabled(!model.hasLoaded || (model.hasChanges && (!active || update))).accessibilityIdentifier("seasonal.quick."+scene.id)
                            Button { editing=model.library.themes.first{$0.id==scene.id} ?? scene } label: { Image(systemName:"slider.horizontal.3").frame(width:44,height:44) }
                                .accessibilityLabel(SeasonalText.value("settings","Einstellungen")+": "+scene.name)
                                .accessibilityIdentifier("seasonal.quick.edit."+scene.id)
                        }
                        Divider()
                    }
                }
                }
                if model.hasChanges { Text(SeasonalText.value("saveBeforeSwitch","Speichern oder verwerfen Sie zuerst die offenen Änderungen.")).font(.footnote).foregroundStyle(AppTheme.textSecondary) }
            }.disabled(model.isSaving)
        }
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .remove: SeasonalText.value("removeConfirm", "Thema aus der Bibliothek entfernen? Der veröffentlichte Zeitplan bleibt bis zur nächsten Veröffentlichung bestehen.")
        case .leave, .reload: SeasonalText.value("discard", "Nicht gespeicherte Änderungen verwerfen?")
        case .publish: SeasonalText.value("publishConfirm", "Gespeicherten Zeitplan für alle veröffentlichen?")
        case .disable: SeasonalText.value("disableConfirm", "Saisonale Gestaltung für alle ausschalten? Die Bibliothek bleibt erhalten.")
        case nil: ""
        }
    }
    private func attemptClose() {
        guard !model.isSaving else { return }
        if model.hasChanges { confirmation = .leave } else { dismiss() }
    }
}
