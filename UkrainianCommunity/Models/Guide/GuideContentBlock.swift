import Foundation

struct GuideSourceLink: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let url: String
    let sourceName: String?
    let isOfficial: Bool

    nonisolated init(
        id: String,
        title: String,
        url: String,
        sourceName: String? = nil,
        isOfficial: Bool = false
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.sourceName = sourceName
        self.isOfficial = isOfficial
    }

    nonisolated var searchableTextValues: [String] {
        [title, url, sourceName].compactMap { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
    }

    nonisolated var isRenderable: Bool {
        !searchableTextValues.isEmpty
    }
}

struct GuideContactReference: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String?
    let phone: String?
    let email: String?
    let website: String?

    nonisolated init(
        id: String,
        name: String,
        description: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        website: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.phone = phone
        self.email = email
        self.website = website
    }

    var searchableTextValues: [String] {
        [name, description, phone, email, website].compactMap { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
    }
}

enum GuideContentBlock: Identifiable, Codable, Equatable {
    case text(TextBlock)
    case steps(StepsBlock)
    case checklist(ChecklistBlock)
    case warning(MessageBlock)
    case infoBox(MessageBlock)
    case links(LinksBlock)
    case contacts(ContactsBlock)

    var id: String {
        switch self {
        case .text(let block):
            block.id
        case .steps(let block):
            block.id
        case .checklist(let block):
            block.id
        case .warning(let block):
            block.id
        case .infoBox(let block):
            block.id
        case .links(let block):
            block.id
        case .contacts(let block):
            block.id
        }
    }

    var searchableTextValues: [String] {
        switch self {
        case .text(let block):
            Self.nonEmptyTextValues(block.title, block.text)
        case .steps(let block):
            Self.nonEmptyTextValues(block.title) + block.steps.nonEmptyTextValues
        case .checklist(let block):
            Self.nonEmptyTextValues(block.title) + block.items.nonEmptyTextValues
        case .warning(let block), .infoBox(let block):
            Self.nonEmptyTextValues(block.title, block.message)
        case .links(let block):
            Self.nonEmptyTextValues(block.title) + block.links.flatMap(\.searchableTextValues)
        case .contacts(let block):
            Self.nonEmptyTextValues(block.title) + block.contacts.flatMap(\.searchableTextValues)
        }
    }

    var isRenderable: Bool {
        switch self {
        case .text(let block):
            !block.text.guideRenderableIsBlank
        case .steps(let block):
            block.steps.contains { !$0.guideRenderableIsBlank }
        case .checklist(let block):
            block.items.contains { !$0.guideRenderableIsBlank }
        case .warning(let block), .infoBox(let block):
            !block.message.guideRenderableIsBlank
        case .links(let block):
            block.links.contains { $0.isRenderable }
        case .contacts(let block):
            block.contacts.contains { !$0.name.guideRenderableIsBlank }
        }
    }

    var renderableTextValues: [String] {
        isRenderable ? searchableTextValues : []
    }

    private static func nonEmptyTextValues(_ values: String?...) -> [String] {
        values.compactMap { $0?.nilIfEmpty }
    }

    struct TextBlock: Identifiable, Codable, Equatable {
        let id: String
        let title: String?
        let text: String
    }

    struct StepsBlock: Identifiable, Codable, Equatable {
        let id: String
        let title: String?
        let steps: [String]
    }

    struct ChecklistBlock: Identifiable, Codable, Equatable {
        let id: String
        let title: String?
        let items: [String]
    }

    struct MessageBlock: Identifiable, Codable, Equatable {
        let id: String
        let title: String?
        let message: String
    }

    struct LinksBlock: Identifiable, Codable, Equatable {
        let id: String
        let title: String?
        let links: [GuideSourceLink]
    }

    struct ContactsBlock: Identifiable, Codable, Equatable {
        let id: String
        let title: String?
        let contacts: [GuideContactReference]
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    nonisolated var guideRenderableIsBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private extension Array where Element == String {
    nonisolated var nonEmptyTextValues: [String] {
        compactMap(\.nilIfEmpty)
    }
}
