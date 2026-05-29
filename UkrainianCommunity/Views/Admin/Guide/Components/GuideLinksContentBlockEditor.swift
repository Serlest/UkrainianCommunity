import SwiftUI

struct GuideLinksContentBlockEditor: View {
    @Binding var block: GuideContentBlock

    var body: some View {
        if case .links(let value) = block {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                GuideContentBlockTitleField(title: value.title) { title in
                    block = .links(.init(id: value.id, title: title, links: value.links))
                }

                AppEditorField(title: AppStrings.GuideEditor.blockLinksField) {
                    if value.links.isEmpty {
                        Text(AppStrings.GuideEditor.blockLinksEmpty)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                            ForEach(value.links.indices, id: \.self) { index in
                                GuideSourceLinkEditorRow(
                                    link: value.links[index],
                                    canMoveUp: index > 0,
                                    canMoveDown: index < value.links.count - 1,
                                    onChange: { updateLink(at: index, link: $0, in: value) },
                                    onMoveUp: { moveLink(from: index, to: index - 1, in: value) },
                                    onMoveDown: { moveLink(from: index, to: index + 1, in: value) },
                                    onDelete: { deleteLink(at: index, in: value) }
                                )
                            }
                        }
                    }

                    Button {
                        appendLink(to: value)
                    } label: {
                        Label(AppStrings.GuideEditor.addLink, systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func appendLink(to value: GuideContentBlock.LinksBlock) {
        var links = value.links
        links.append(.init(id: UUID().uuidString, title: "", url: ""))
        block = .links(.init(id: value.id, title: value.title, links: links))
    }

    private func updateLink(at index: Int, link: GuideSourceLink, in value: GuideContentBlock.LinksBlock) {
        guard value.links.indices.contains(index) else { return }
        var links = value.links
        links[index] = link
        block = .links(.init(id: value.id, title: value.title, links: links))
    }

    private func moveLink(from source: Int, to destination: Int, in value: GuideContentBlock.LinksBlock) {
        guard value.links.indices.contains(source), value.links.indices.contains(destination) else { return }
        var links = value.links
        let link = links.remove(at: source)
        links.insert(link, at: destination)
        block = .links(.init(id: value.id, title: value.title, links: links))
    }

    private func deleteLink(at index: Int, in value: GuideContentBlock.LinksBlock) {
        guard value.links.indices.contains(index) else { return }
        var links = value.links
        links.remove(at: index)
        block = .links(.init(id: value.id, title: value.title, links: links))
    }
}
