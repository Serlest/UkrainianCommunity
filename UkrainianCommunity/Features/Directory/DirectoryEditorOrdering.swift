import Foundation

/// Editorial order is stored as numbers, but editors move visible rows instead of entering ranks.
enum DirectoryEditorOrdering {
    static func groupIDs(_ groups: [DirectoryManagedGroup]) -> [String] {
        groups.sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order }.map(\.id)
    }

    static func topicIDs(_ topics: [DirectoryManagedTopic], groupID: String) -> [String] {
        topics.filter { $0.groupID == groupID }
            .sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order }
            .map(\.id)
    }

    static func sectionIDs(_ sections: [DirectoryManagedSection]) -> [String] {
        sections.sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order }.map(\.id)
    }

    static func moveGroup(_ groups: inout [DirectoryManagedGroup], id: String, by offset: Int) {
        var ordered = groupIDs(groups)
        guard swap(&ordered, id: id, by: offset) else { return }
        for (rank, groupID) in ordered.enumerated() {
            if let index = groups.firstIndex(where: { $0.id == groupID }) { groups[index].order = rank }
        }
    }

    static func moveTopic(_ topics: inout [DirectoryManagedTopic], id: String,
                          groupID: String, by offset: Int) {
        var ordered = topicIDs(topics, groupID: groupID)
        guard swap(&ordered, id: id, by: offset) else { return }
        for (rank, topicID) in ordered.enumerated() {
            if let index = topics.firstIndex(where: { $0.id == topicID }) { topics[index].order = rank }
        }
    }

    static func moveSection(_ sections: inout [DirectoryManagedSection], id: String, by offset: Int) {
        var ordered = sectionIDs(sections)
        guard swap(&ordered, id: id, by: offset) else { return }
        for (rank, sectionID) in ordered.enumerated() {
            if let index = sections.firstIndex(where: { $0.id == sectionID }) { sections[index].order = rank }
        }
    }

    static func nextOrder(in placement: DirectoryManagedCategory.Placement,
                          categories: [DirectoryManagedCategory]) -> Int {
        min(1000, (categories.filter { $0.placement == placement }.map(\.order).max() ?? -1) + 1)
    }

    private static func swap(_ ids: inout [String], id: String, by offset: Int) -> Bool {
        guard let current = ids.firstIndex(of: id), ids.indices.contains(current + offset) else { return false }
        ids.swapAt(current, current + offset)
        return true
    }
}
