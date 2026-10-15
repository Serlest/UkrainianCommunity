import Foundation

/// Keep a publishable parent while removing nested editorial content.
enum DirectoryEditorDeletion {
    static func canDeleteGroup(_ id: String, from category: DirectoryManagedCategory) -> Bool {
        category.groups.contains { $0.id == id } && category.groups.count > 1 &&
            category.topics.contains { topic in
                !topic.isHidden && topic.groupID != id &&
                    category.groups.contains { $0.id == topic.groupID && !$0.isHidden }
            }
    }

    static func deleteGroup(_ id: String, from category: inout DirectoryManagedCategory) {
        guard canDeleteGroup(id, from: category) else { return }
        category.topics.removeAll { $0.groupID == id }
        category.groups.removeAll { $0.id == id }
    }

    static func canDeleteTopic(_ id: String, from category: DirectoryManagedCategory) -> Bool {
        category.topics.contains { $0.id == id } && category.topics.contains { topic in
            topic.id != id && !topic.isHidden &&
                category.groups.contains { $0.id == topic.groupID && !$0.isHidden }
        }
    }

    static func deleteTopic(_ id: String, from category: inout DirectoryManagedCategory) {
        guard canDeleteTopic(id, from: category) else { return }
        category.topics.removeAll { $0.id == id }
    }

    static func canDeleteSection(_ id: String, from topic: DirectoryManagedTopic) -> Bool {
        topic.sections.contains { $0.id == id } &&
            topic.sections.contains { $0.id != id && !$0.isHidden }
    }

    static func deleteSection(_ id: String, from topic: inout DirectoryManagedTopic) {
        guard canDeleteSection(id, from: topic) else { return }
        topic.sections.removeAll { $0.id == id }
    }

    static func deleteRegionalSection(_ id: String, state: AustrianFederalState,
                                      from topic: inout DirectoryManagedTopic) {
        topic.regionalSections[state.rawValue]?.removeAll { $0.id == id }
    }
}
