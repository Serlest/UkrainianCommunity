import SwiftUI

struct GuideMaterialEditorSourcesSection: View {
    @Binding var sourceLinks: [GuideSourceLink]

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                SectionHeaderBlock(
                    title: GuideAuthoringPresentation.sourcesTitle,
                    subtitle: GuideAuthoringPresentation.sourcesSubtitle
                )

                GuideMaterialSourceLinksEditorView(sourceLinks: $sourceLinks)
            }
        }
    }
}

private struct GuideMaterialSourceLinksEditorView: View {
    @Binding var sourceLinks: [GuideSourceLink]

    var body: some View {
        AppEditorField(title: GuideAuthoringPresentation.sourceLinksLabel) {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                if sourceLinks.isEmpty {
                    Text(GuideAuthoringPresentation.noSourceLinks)
                        .font(AppTheme.metadataFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(sourceLinks.indices, id: \.self) { index in
                        GuideMaterialSourceRow(
                            link: binding(for: index),
                            onDelete: { deleteLink(at: index) }
                        )
                    }
                }

                Button {
                    sourceLinks.append(.init(id: UUID().uuidString, title: "", url: ""))
                } label: {
                    Label(GuideAuthoringPresentation.addSourceLink, systemImage: "plus.circle")
                        .font(AppTheme.buttonLabelFont)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func binding(for index: Int) -> Binding<GuideSourceLink> {
        Binding(
            get: { sourceLinks.indices.contains(index) ? sourceLinks[index] : .init(id: UUID().uuidString, title: "", url: "") },
            set: { newValue in
                guard sourceLinks.indices.contains(index) else { return }
                sourceLinks[index] = newValue
            }
        )
    }

    private func deleteLink(at index: Int) {
        guard sourceLinks.indices.contains(index) else { return }
        sourceLinks.remove(at: index)
    }
}

private struct GuideMaterialSourceRow: View {
    @Binding var link: GuideSourceLink
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(GuideAuthoringPresentation.sourceLinksLabel)
                    .font(AppTheme.buttonLabelFont)
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer(minLength: 0)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(AppTheme.buttonLabelFont)
                }
                .buttonStyle(.borderless)
            }

            editorField(
                GuideAuthoringPresentation.sourceTitleFieldLabel,
                text: titleBinding,
                capitalization: .words
            )

            editorField(
                GuideAuthoringPresentation.sourceURLFieldLabel,
                text: urlBinding,
                capitalization: .never,
                disableAutocorrection: true,
                keyboardType: .URL
            )
        }
        .padding(14)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { link.title },
            set: { link = GuideSourceLink(id: link.id, title: $0, url: link.url, sourceName: link.sourceName, isOfficial: link.isOfficial) }
        )
    }

    private var urlBinding: Binding<String> {
        Binding(
            get: { link.url },
            set: { link = GuideSourceLink(id: link.id, title: link.title, url: $0, sourceName: link.sourceName, isOfficial: link.isOfficial) }
        )
    }

    private func editorField(
        _ title: String,
        text: Binding<String>,
        capitalization: TextInputAutocapitalization,
        disableAutocorrection: Bool = false,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        TextField(title, text: text, axis: .vertical)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled(disableAutocorrection)
            .keyboardType(keyboardType)
            .appEditorInputStyle()
    }
}
