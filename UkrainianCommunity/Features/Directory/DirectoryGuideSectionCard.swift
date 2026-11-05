import SwiftUI

struct DirectoryGuideSectionCard: View {
    let section: DirectoryGuideSection
    let language: AppLanguage
    let route: DirectoryRoute
    var compactBody: Bool = true
    var contacts: [SafetyContact] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: route) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: section.symbol)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.accentPrimaryForeground)
                            .frame(width: 36, height: 36)
                            .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 11))
                            .accessibilityHidden(true)
                        Text(section.title.value(for: language))
                            .font(.title3.weight(.semibold))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    if compactBody {
                        DirectoryGuideBodyView(text: section.body.value(for: language), compact: true)
                        Text(language == .ukrainian ? "Читати повністю" : "Weiterlesen")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.accentPrimaryForeground)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("directory.section.open.\(section.id)")
            if !compactBody {
                Divider()
                DirectoryGuideBodyView(text: section.body.value(for: language))
            }
            ForEach(contacts) { contact in
                SafetyCallButton(contact: contact, language: language)
            }
            if let source = section.source {
                Divider()
                Link(destination: source.url) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "arrow.up.right.square")
                        Text(source.name)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: AppTheme.minimumInteractiveTarget)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("directory.source.\(section.id)")
            }
            if let number = section.phoneNumber,
               let url = URL(string: "tel:\(number.replacingOccurrences(of: " ", with: ""))") {
                Link(destination: url) {
                    Label(number, systemImage: "phone.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityIdentifier("directory.call.\(section.id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .appGlassCard(material: .regularMaterial)
    }
}

/// Resolve stable IDs against the current catalog, so edits and hidden/deleted
/// items cannot leave a captured, obsolete article open for sharing.
struct DirectorySectionDestination: View {
    let categoryID: String
    let topicID: String
    let sectionID: String
    var federalState: String? = nil
    @EnvironmentObject private var contentStore: DirectoryContentStore
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }

    private func section(in topic: DirectoryManagedTopic) -> DirectoryManagedSection? {
        let sections = federalState.map { topic.regionalSections[$0] ?? [] } ?? topic.sections
        return sections.first { $0.id == sectionID && !$0.isHidden }
    }

    var body: some View {
        if let category = contentStore.category(categoryID), !category.isHidden,
           let topic = category.topic(topicID), let section = section(in: topic) {
            DirectorySectionReader(
                section: .init(section.id, section.symbol, section.title.ukrainian, section.title.german,
                               section.body.ukrainian, section.body.german,
                               phoneNumber: section.phoneNumber, source: section.source?.displaySource),
                language: language,
                contacts: section.contacts.map { SafetyContact(number: $0.number, title: $0.title, detail: $0.detail) },
                context: [topic.title.value(for: language), federalState.flatMap(AustrianFederalState.init(rawValue:))?.displayName]
                    .compactMap { $0 }.joined(separator: " · "),
                additionalSources: topic.sources.compactMap(\.displaySource)
            )
        } else if contentStore.syncState == .loading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(AppBackgroundView())
                .toolbar(.visible, for: .navigationBar)
        } else {
            ContentUnavailableView(language == .ukrainian ? "Матеріал більше недоступний" : "Inhalt nicht mehr verfügbar",
                                   systemImage: "doc.text.magnifyingglass")
                .background(AppBackgroundView())
                .toolbar(.visible, for: .navigationBar)
        }
    }
}

/// A focused reader shares only the selected information, never the entire category.
struct DirectorySectionReader: View {
    let section: DirectoryGuideSection
    let language: AppLanguage
    var contacts: [SafetyContact] = []
    var context: String? = nil
    var additionalSources: [DirectorySource] = []

    @State private var showingShare = false

    private var sources: [DirectorySource] {
        if let source = section.source { return [source] }
        return additionalSources
    }

    private var shareText: String {
        DirectorySectionShareText.compose(
            section: section, contacts: contacts, context: context,
            sources: sources, language: language
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let context, !context.isEmpty {
                    Text(context).font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                }
                Label {
                    Text(section.title.value(for: language)).font(.title2.bold())
                        .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: section.symbol).foregroundStyle(AppTheme.accentPrimaryForeground)
                }
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                DirectoryGuideBodyView(text: section.body.value(for: language))
                ForEach(contacts) { contact in
                    SafetyCallButton(contact: contact, language: language)
                }
                if let number = section.phoneNumber,
                   let url = URL(string: "tel:\(number.replacingOccurrences(of: " ", with: ""))") {
                    Link(destination: url) {
                        Label(number, systemImage: "phone.fill")
                            .frame(maxWidth: .infinity, minHeight: AppTheme.minimumInteractiveTarget, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
                if !sources.isEmpty {
                    Divider()
                    Text(section.source != nil
                         ? (language == .ukrainian ? "Джерело" : "Quelle")
                         : (language == .ukrainian ? "Джерела теми" : "Quellen zum Thema"))
                        .font(.headline).foregroundStyle(AppTheme.textPrimary)
                    ForEach(sources) { source in
                        Link(destination: source.url) {
                            Label(source.name, systemImage: "arrow.up.right.square")
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: AppTheme.minimumInteractiveTarget, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("directory.reader.source")
                    }
                }
            }
            .padding(20)
            .appGlassCard(material: .regularMaterial)
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.top, AppTheme.homeSectionSpacing)
            .padding(.bottom, AppTheme.homeBottomContentPadding)
            .appCenteredContent(maxWidth: AppTheme.readableContentMaxWidth)
        }
        .background(AppBackgroundView())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(language == .ukrainian ? "Поділитися" : "Teilen")
                .accessibilityIdentifier("detail.header.share")
                .background {
                    ContentTextSharePresenter(isPresented: $showingShare, text: shareText,
                                              title: section.title.value(for: language))
                        .allowsHitTesting(false)
                }
            }
        }
        // A focused instruction must remain readable while the global scene stays enabled elsewhere.
        .anchorPreference(key: SeasonalHeaderAnchors.self, value: .bounds) { [.readingSurface: $0] }
        .accessibilityIdentifier("directory.section.reader")
    }
}

enum DirectorySectionShareText {
    static func compose(section: DirectoryGuideSection, contacts: [SafetyContact], context: String?,
                        sources: [DirectorySource], language: AppLanguage) -> String {
        var paragraphs = [section.title.value(for: language)]
        if let context, !context.isEmpty { paragraphs.append(context) }
        // Instructions can contain conditions and exceptions: do not cut them off mid-procedure.
        paragraphs.append(section.body.value(for: language).trimmingCharacters(in: .whitespacesAndNewlines))
        for contact in contacts {
            paragraphs.append([contact.title.value(for: language), contact.number,
                               contact.detail.value(for: language)].filter { !$0.isEmpty }.joined(separator: " — "))
        }
        if let number = section.phoneNumber, !contacts.contains(where: { $0.number == number }) {
            paragraphs.append(number)
        }
        var seen = Set<String>()
        for source in sources {
            guard let url = ContentShareText.safeWebURL(source.url.absoluteString),
                  seen.insert(url.absoluteString).inserted else { continue }
            paragraphs.append("\(language == .ukrainian ? "Джерело" : "Quelle"): \(url.absoluteString)")
        }
        paragraphs.append("\(language == .ukrainian ? "Більше інформації — у застосунку UAC" : "Weitere Informationen in der UAC-App"): \(ContentShareText.appURL)")
        return paragraphs.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

/// Keep the standard toolbar treatment; a second custom glass background would draw two rings.
struct DirectoryInformationShareButton: View {
    let title: String
    let text: String
    let language: AppLanguage
    @State private var showingShare = false

    var body: some View {
        Button { showingShare = true } label: { Image(systemName: "square.and.arrow.up") }
            .accessibilityLabel(language == .ukrainian ? "Поділитися темою" : "Thema teilen")
            .accessibilityIdentifier("directory.topic.share")
            .background {
                ContentTextSharePresenter(isPresented: $showingShare, text: text, title: title)
                    .allowsHitTesting(false)
            }
    }
}
