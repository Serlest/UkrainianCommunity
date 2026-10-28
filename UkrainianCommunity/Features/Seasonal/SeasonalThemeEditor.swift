import SwiftUI

struct SeasonalThemeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editingDate: DateField?
    private enum DateField: String, Identifiable { case start, end; var id: String { rawValue } }
    @State private var draft: SeasonalTheme
    @State private var previewScheme: ColorScheme = .light
    @State private var confirmDiscard = false
    @FocusState private var nameFocused: Bool
    private let original: SeasonalTheme
    private let onApply: (SeasonalTheme) -> Void
    private var valid: Bool { (try? draft.validate()) != nil }

    init(theme: SeasonalTheme, onApply: @escaping (SeasonalTheme) -> Void) {
        original = theme; _draft = State(initialValue: theme); self.onApply = onApply
    }
    private var timeZoneControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SeasonalText.value("timezone", "Zeitzone"))
            Menu {
                ForEach(Array(Set(["Europe/Vienna", "Europe/Kyiv", "UTC", draft.timeZoneID])).sorted(), id: \.self) { zone in
                    Button { draft.timeZoneID = zone } label: {
                        if zone == draft.timeZoneID { Label(zone, systemImage: "checkmark") } else { Text(zone) }
                    }
                }
            } label: {
                HStack(alignment: .top) {
                    Text(draft.timeZoneID.replacingOccurrences(of: "/", with: " / "))
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 14))
                }.frame(minHeight: 44)
            }.accessibilityIdentifier("seasonal.editor.timezone")
        }
    }
    private func dateTitle(_ field: DateField) -> String {
        field == .start ? SeasonalText.value("from", "Beginn") : SeasonalText.value("until", "Ende")
    }
    private func dateBinding(_ field: DateField) -> Binding<Date> {
        field == .start ? $draft.startsAt : $draft.endsAt
    }
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = LocalizationStore.locale
        formatter.timeZone = TimeZone(identifier: draft.timeZoneID)
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    private func accessibleDate(_ field: DateField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dateTitle(field))
            Button { nameFocused = false; editingDate = field } label: {
                Text(formattedDate(field == .start ? draft.startsAt : draft.endsAt))
                    .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
            }.accessibilityIdentifier("seasonal.editor.date." + field.rawValue)
        }
    }
    private func appendArtwork(_ artwork: SeasonalArtwork) {
        let leadingCount = draft.elements.filter { $0.anchor == SeasonalAnchor.leading }.count
        let anchor: SeasonalAnchor = leadingCount < 3 ? .leading : .trailing
        draft.elements.append(SeasonalElement(artwork: artwork, anchor: anchor))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(SeasonalText.value("preview", "Vorschau")) {
                    SeasonalPreview(theme: draft).environment(\.colorScheme, previewScheme)
                    Picker(SeasonalText.value("appearance", "Darstellung"), selection: $previewScheme) {
                        Text(SeasonalText.value("light", "Hell")).tag(ColorScheme.light)
                        Text(SeasonalText.value("dark", "Dunkel")).tag(ColorScheme.dark)
                    }.pickerStyle(.segmented)
                    Text(SeasonalText.value("previewHint", "Die Vorschau zeigt das Thema sofort, unabhängig vom Zeitplan. Nur Sie sehen diese Änderungen."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(SeasonalText.value("schedule", "Zeitplan")) {
                    TextField(SeasonalText.value("name", "Name"), text: $draft.name).focused($nameFocused)
                        .accessibilityIdentifier("seasonal.editor.name")
                    Toggle(SeasonalText.value("enabled", "In den Zeitplan aufnehmen"), isOn: $draft.isEnabled)
                    timeZoneControl
                    if typeSize.isAccessibilitySize {
                        accessibleDate(.start)
                        accessibleDate(.end)
                    } else {
                        Group {
                            DatePicker(SeasonalText.value("from", "Beginn"), selection: $draft.startsAt)
                            DatePicker(SeasonalText.value("until", "Ende"), selection: $draft.endsAt)
                        }.environment(\.timeZone, TimeZone(identifier: draft.timeZoneID) ?? .gmt)
                    }
                    Toggle(SeasonalText.value("yearly", "Jährlich wiederholen"), isOn: $draft.repeatsYearly)
                    Stepper(SeasonalText.value("priority", "Priorität") + ": \(draft.priority)", value: $draft.priority, in: 0...100)
                    Text(SeasonalText.value("endHint", "Das Ende ist exklusiv. Jährliche Wiederholung verwendet dieselbe lokale Uhrzeit; ein Zeitraum über Silvester bleibt zusammenhängend."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(SeasonalText.value("motion", "Bewegung")) {
                    Toggle(SeasonalText.value("tilt", "Auf die Geräteneigung reagieren"), isOn: $draft.reactsToTilt)
                    Text(SeasonalText.value("intensity", "Intensität"))
                    Slider(value: $draft.intensity, in: 0.2...1)
                        .accessibilityLabel(SeasonalText.value("intensity", "Intensität"))
                    Text(SeasonalText.preferenceHint).font(.footnote).foregroundStyle(.secondary)
                }
                Section(SeasonalText.value("sections", "Hauptseiten")) {
                    ForEach(SeasonalSection.allCases) { section in
                        Toggle(SeasonalText.section(section), isOn: Binding(get: { draft.sections.contains(section) }, set: { enabled in
                            if enabled { draft.sections.append(section) } else { draft.sections.removeAll { $0 == section } }
                        }))
                    }
                    Text(SeasonalText.value("scopeHint", "In Unterseiten, Formularen, beim Anmelden und bei geöffneter Tastatur werden die Effekte ausgeblendet. Im Querformat bleiben die Inhalte im Vordergrund."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(SeasonalText.value("artwork", "Dekorationen")) {
                    ForEach($draft.elements) { $element in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(SeasonalText.artwork(element.artwork)).font(.headline)
                                Spacer()
                                Button(role: .destructive) { draft.elements.removeAll { $0.id == element.id } } label: {
                                    Image(systemName: "trash").frame(width: 44, height: 44).accessibilityLabel(AppStrings.Action.delete)
                                }.buttonStyle(.borderless).disabled(draft.elements.count <= 1)
                            }
                            Picker(SeasonalText.value("position", "Position"), selection: $element.anchor) {
                                Text(SeasonalText.value("leading", "Links")).tag(SeasonalAnchor.leading)
                                Text(SeasonalText.value("trailing", "Rechts")).tag(SeasonalAnchor.trailing)
                            }.pickerStyle(.segmented)
                            Text(SeasonalText.value("size", "Größe"))
                            Slider(value: $element.size, in: 16...44).accessibilityLabel(SeasonalText.value("size", "Größe"))
                            Text(SeasonalText.value("sway", "Bewegungsstärke"))
                            Slider(value: $element.sway, in: 0...1).accessibilityLabel(SeasonalText.value("sway", "Bewegungsstärke"))
                            Toggle(SeasonalText.value("glow", "Leuchten"), isOn: $element.glow)
                        }.padding(.vertical, 6)
                    }
                    Menu {
                        ForEach(SeasonalArtwork.allCases.filter { $0 != .image }) { artwork in
                            Button(SeasonalText.artwork(artwork)) {
                                appendArtwork(artwork)
                            }
                        }
                    } label: { Label(SeasonalText.value("addArtwork", "Dekoration hinzufügen"), systemImage: "plus").frame(minHeight: 44) }
                        .disabled(draft.elements.count >= 6)
                }
                if let message = draft.validationMessage { Section { Text(message).foregroundStyle(.red) } }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackgroundView() }
            .tint(AppTheme.accentPrimaryForeground)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(draft.name.isEmpty ? SeasonalText.title : draft.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Action.cancel) { nameFocused = false; if draft != original { confirmDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(SeasonalText.value("apply", "Übernehmen")) { nameFocused = false; onApply(draft); dismiss() }
                        .disabled(!valid).accessibilityIdentifier("seasonal.editor.apply")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button(AppStrings.Common.done) { nameFocused = false } }
            }
            .confirmationDialog(SeasonalText.value("discard", "Nicht gespeicherte Änderungen verwerfen?"), isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button(SeasonalText.value("discardAction", "Änderungen verwerfen"), role: .destructive) { dismiss() }
                Button(AppStrings.Action.cancel, role: .cancel) {}
            }
            .sheet(item: $editingDate) { field in
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 20) {
                            Text(formattedDate(field == .start ? draft.startsAt : draft.endsAt))
                                .fixedSize(horizontal: false, vertical: true)
                            DatePicker(dateTitle(field), selection: dateBinding(field))
                                .datePickerStyle(.wheel).labelsHidden().dynamicTypeSize(.large)
                        }.padding()
                    }
                    .environment(\.timeZone, TimeZone(identifier: draft.timeZoneID) ?? .gmt)
                    .navigationTitle(dateTitle(field)).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(AppStrings.Common.done) { editingDate = nil } } }
                }.dynamicTypeSize(typeSize)
                    .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
            }
            .interactiveDismissDisabled(draft != original)
        }
    }
}
