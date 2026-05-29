import SwiftUI

struct GuideChecklistContentBlockEditor: View {
    @Binding var block: GuideContentBlock

    var body: some View {
        if case .checklist(let value) = block {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                GuideContentBlockTitleField(title: value.title) { title in
                    block = .checklist(.init(id: value.id, title: title, items: value.items))
                }

                AppEditorField(title: AppStrings.GuideEditor.blockChecklistField) {
                    if value.items.isEmpty {
                        Text(AppStrings.GuideEditor.blockChecklistEmpty)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                            ForEach(value.items.indices, id: \.self) { index in
                                GuideChecklistItemEditorRow(
                                    text: value.items[index],
                                    canMoveUp: index > 0,
                                    canMoveDown: index < value.items.count - 1,
                                    onChange: { updateItem(at: index, text: $0, in: value) },
                                    onMoveUp: { moveItem(from: index, to: index - 1, in: value) },
                                    onMoveDown: { moveItem(from: index, to: index + 1, in: value) },
                                    onDelete: { deleteItem(at: index, in: value) }
                                )
                            }
                        }
                    }

                    Button {
                        appendItem(to: value)
                    } label: {
                        Label(AppStrings.GuideEditor.addChecklistItem, systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func appendItem(to value: GuideContentBlock.ChecklistBlock) {
        var items = value.items
        items.append("")
        block = .checklist(.init(id: value.id, title: value.title, items: items))
    }

    private func updateItem(at index: Int, text: String, in value: GuideContentBlock.ChecklistBlock) {
        guard value.items.indices.contains(index) else { return }
        var items = value.items
        items[index] = text
        block = .checklist(.init(id: value.id, title: value.title, items: items))
    }

    private func moveItem(from source: Int, to destination: Int, in value: GuideContentBlock.ChecklistBlock) {
        guard value.items.indices.contains(source), value.items.indices.contains(destination) else { return }
        var items = value.items
        let item = items.remove(at: source)
        items.insert(item, at: destination)
        block = .checklist(.init(id: value.id, title: value.title, items: items))
    }

    private func deleteItem(at index: Int, in value: GuideContentBlock.ChecklistBlock) {
        guard value.items.indices.contains(index) else { return }
        var items = value.items
        items.remove(at: index)
        block = .checklist(.init(id: value.id, title: value.title, items: items))
    }
}

private struct GuideChecklistItemEditorRow: View {
    let text: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onChange: (String) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: "checkmark.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .padding(.top, 12)

            TextEditor(text: Binding(get: { text }, set: onChange))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 64)
                .padding(8)
                .background(AppTheme.surfaceGlass, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                .accessibilityLabel(AppStrings.GuideEditor.checklistItemPlaceholder)

            VStack(spacing: 4) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveUp)
                .accessibilityLabel(AppStrings.GuideEditor.moveChecklistItemUp)

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveDown)
                .accessibilityLabel(AppStrings.GuideEditor.moveChecklistItemDown)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(AppStrings.GuideEditor.deleteChecklistItem)
            }
            .buttonStyle(.borderless)
        }
    }
}
