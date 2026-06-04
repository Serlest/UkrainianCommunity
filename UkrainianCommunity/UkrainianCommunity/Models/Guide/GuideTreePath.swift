import Foundation

struct GuideTreePath: Codable, Equatable, Hashable {
    let components: [Component]

    init(components: [Component]) {
        self.components = components
    }

    var titles: [String] {
        components.map(\.title)
    }
}

extension GuideTreePath {
    struct Component: Codable, Equatable, Hashable, Identifiable {
        let id: String
        let title: String

        init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }
}
