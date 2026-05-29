import SwiftUI

struct GuideContentBlocksEditorView: View {
    @Binding var blocks: [GuideContentBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            AppEditorField(title: AppStrings.GuideEditor.contentBlocksField) {
                if blocks.isEmpty {
                    Text(AppStrings.GuideEditor.contentBlocksEmpty)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                        ForEach(blocks.indices, id: \.self) { index in
                            GuideContentBlockEditorRow(
                                block: binding(for: index),
                                canMoveUp: index > 0,
                                canMoveDown: index < blocks.count - 1,
                                onMoveUp: { moveBlock(from: index, to: index - 1) },
                                onMoveDown: { moveBlock(from: index, to: index + 1) },
                                onDelete: { deleteBlock(at: index) }
                            )
                        }
                    }
                }

                GuideContentBlockTypePicker { type in
                    blocks.append(type.makeBlock())
                }
            }
        }
    }

    private func binding(for index: Int) -> Binding<GuideContentBlock> {
        Binding(
            get: { blocks[index] },
            set: { blocks[index] = $0 }
        )
    }

    private func moveBlock(from source: Int, to destination: Int) {
        guard blocks.indices.contains(source), blocks.indices.contains(destination) else { return }
        let block = blocks.remove(at: source)
        blocks.insert(block, at: destination)
    }

    private func deleteBlock(at index: Int) {
        guard blocks.indices.contains(index) else { return }
        blocks.remove(at: index)
    }
}

