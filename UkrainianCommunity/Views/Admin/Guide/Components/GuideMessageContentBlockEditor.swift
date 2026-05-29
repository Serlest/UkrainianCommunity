import SwiftUI

struct GuideMessageContentBlockEditor: View {
    @Binding var block: GuideContentBlock

    var body: some View {
        switch block {
        case .warning(let value):
            messageEditor(value: value, type: .warning)
        case .infoBox(let value):
            messageEditor(value: value, type: .infoBox)
        default:
            GuideUnsupportedContentBlockEditor()
        }
    }

    private func messageEditor(
        value: GuideContentBlock.MessageBlock,
        type: GuideMessageContentBlockType
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            GuideContentBlockTitleField(title: value.title) { title in
                block = type.makeBlock(id: value.id, title: title, message: value.message)
            }

            GuideContentBlockBodyEditor(
                text: value.message,
                label: AppStrings.GuideEditor.blockMessageField
            ) { message in
                block = type.makeBlock(id: value.id, title: value.title, message: message)
            }
        }
    }
}

private enum GuideMessageContentBlockType {
    case warning
    case infoBox

    func makeBlock(id: String, title: String?, message: String) -> GuideContentBlock {
        switch self {
        case .warning:
            return .warning(.init(id: id, title: title, message: message))
        case .infoBox:
            return .infoBox(.init(id: id, title: title, message: message))
        }
    }
}

