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
                        readerOrderSummary

                        ForEach(blocks.indices, id: \.self) { index in
                            GuideContentBlockEditorRow(
                                block: binding(for: index),
                                position: index + 1,
                                totalCount: blocks.count,
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

    private var readerOrderSummary: some View {
        SoftContentCard(padding: AppTheme.eventsCardPadding) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppStrings.GuideEditor.readerOrderTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(AppStrings.GuideEditor.readerOrderHelp)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.accentPrimary)
                                .frame(width: 20, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(block.readerSummaryTitle)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)

                                Text(block.readerSummaryBody)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
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

private extension GuideContentBlock {
    var readerSummaryTitle: String {
        switch self {
        case .text(let block):
            summaryTitle(for: AppStrings.GuideEditor.blockTypeText, customTitle: block.title)
        case .steps(let block):
            summaryTitle(for: AppStrings.GuideEditor.blockTypeSteps, customTitle: block.title)
        case .checklist(let block):
            summaryTitle(for: AppStrings.GuideEditor.blockTypeChecklist, customTitle: block.title)
        case .warning(let block):
            summaryTitle(for: AppStrings.GuideEditor.blockTypeWarning, customTitle: block.title)
        case .infoBox(let block):
            summaryTitle(for: AppStrings.GuideEditor.blockTypeInfoBox, customTitle: block.title)
        case .links(let block):
            summaryTitle(for: AppStrings.GuideEditor.blockTypeLinks, customTitle: block.title)
        case .contacts(let block):
            summaryTitle(for: AppStrings.GuideEditor.blockTypeContacts, customTitle: block.title)
        }
    }

    var readerSummaryBody: String {
        switch self {
        case .text(let block):
            block.text.guideSummaryPreviewText
        case .steps(let block):
            block.steps.guideSummaryPreviewText
        case .checklist(let block):
            block.items.guideSummaryPreviewText
        case .warning(let block), .infoBox(let block):
            block.message.guideSummaryPreviewText
        case .links(let block):
            block.links
                .compactMap { $0.title.guideSummaryPreviewText.nilIfEmptyGuideSummary }
                .first ?? AppStrings.GuideEditor.blockSummaryEmpty
        case .contacts(let block):
            block.contacts
                .compactMap { $0.name.guideSummaryPreviewText.nilIfEmptyGuideSummary }
                .first ?? AppStrings.GuideEditor.blockSummaryEmpty
        }
    }

    private func summaryTitle(for blockType: String, customTitle: String?) -> String {
        let trimmedCustomTitle = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedCustomTitle, !trimmedCustomTitle.isEmpty {
            return "\(blockType) • \(trimmedCustomTitle)"
        }

        return "\(blockType) • \(AppStrings.GuideEditor.blockSummaryUntitled)"
    }
}

private extension String {
    var guideSummaryPreviewText: String {
        let trimmedValue = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return AppStrings.GuideEditor.blockSummaryEmpty
        }

        return trimmedValue
    }

    var nilIfEmptyGuideSummary: String? {
        let trimmedValue = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

private extension Array where Element == String {
    var guideSummaryPreviewText: String {
        compactMap(\.nilIfEmptyGuideSummary).first ?? AppStrings.GuideEditor.blockSummaryEmpty
    }
}
