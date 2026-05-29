import SwiftUI

struct GuideArticleSourceLinksEditorView: View {
    @Binding var sourceLinks: [GuideSourceLink]

    var body: some View {
        AppEditorField(title: AppStrings.GuideEditor.articleSourceLinksField) {
            if sourceLinks.isEmpty {
                Text(AppStrings.GuideEditor.articleSourceLinksEmpty)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    ForEach(sourceLinks.indices, id: \.self) { index in
                        GuideSourceLinkEditorRow(
                            link: sourceLinks[index],
                            canMoveUp: index > 0,
                            canMoveDown: index < sourceLinks.count - 1,
                            onChange: { updateLink(at: index, link: $0) },
                            onMoveUp: { moveLink(from: index, to: index - 1) },
                            onMoveDown: { moveLink(from: index, to: index + 1) },
                            onDelete: { deleteLink(at: index) }
                        )
                    }
                }
            }

            Button {
                sourceLinks.append(.init(id: UUID().uuidString, title: "", url: ""))
            } label: {
                Label(AppStrings.GuideEditor.addArticleSourceLink, systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
    }

    private func updateLink(at index: Int, link: GuideSourceLink) {
        guard sourceLinks.indices.contains(index) else { return }
        sourceLinks[index] = link
    }

    private func moveLink(from source: Int, to destination: Int) {
        guard sourceLinks.indices.contains(source), sourceLinks.indices.contains(destination) else { return }
        let link = sourceLinks.remove(at: source)
        sourceLinks.insert(link, at: destination)
    }

    private func deleteLink(at index: Int) {
        guard sourceLinks.indices.contains(index) else { return }
        sourceLinks.remove(at: index)
    }
}
