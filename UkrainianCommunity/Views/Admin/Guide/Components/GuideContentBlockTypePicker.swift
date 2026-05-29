import SwiftUI

struct GuideContentBlockTypePicker: View {
    let onAdd: (GuideEditableContentBlockType) -> Void

    var body: some View {
        Menu {
            ForEach(GuideEditableContentBlockType.allCases) { type in
                Button {
                    onAdd(type)
                } label: {
                    Label(type.title, systemImage: type.systemImage)
                }
            }
        } label: {
            Label(AppStrings.GuideEditor.addContentBlock, systemImage: "plus.circle")
                .font(.subheadline.weight(.semibold))
        }
    }
}

enum GuideEditableContentBlockType: CaseIterable, Identifiable {
    case text
    case steps
    case checklist
    case links
    case contacts
    case warning
    case infoBox

    var id: String { title }

    var title: String {
        switch self {
        case .text:
            AppStrings.GuideEditor.blockTypeText
        case .steps:
            AppStrings.GuideEditor.blockTypeSteps
        case .checklist:
            AppStrings.GuideEditor.blockTypeChecklist
        case .links:
            AppStrings.GuideEditor.blockTypeLinks
        case .contacts:
            AppStrings.GuideEditor.blockTypeContacts
        case .warning:
            AppStrings.GuideEditor.blockTypeWarning
        case .infoBox:
            AppStrings.GuideEditor.blockTypeInfoBox
        }
    }

    var systemImage: String {
        switch self {
        case .text:
            "text.alignleft"
        case .steps:
            "list.number"
        case .checklist:
            "checklist"
        case .links:
            "link"
        case .contacts:
            "person.crop.circle"
        case .warning:
            "exclamationmark.triangle"
        case .infoBox:
            "info.circle"
        }
    }

    func makeBlock() -> GuideContentBlock {
        let id = UUID().uuidString

        switch self {
        case .text:
            return .text(.init(id: id, title: nil, text: ""))
        case .steps:
            return .steps(.init(id: id, title: nil, steps: []))
        case .checklist:
            return .checklist(.init(id: id, title: nil, items: []))
        case .links:
            return .links(.init(id: id, title: nil, links: []))
        case .contacts:
            return .contacts(.init(id: id, title: nil, contacts: []))
        case .warning:
            return .warning(.init(id: id, title: nil, message: ""))
        case .infoBox:
            return .infoBox(.init(id: id, title: nil, message: ""))
        }
    }
}
