import Foundation

struct GuideMaterialRef: Codable, Equatable, Hashable, Identifiable {
    let materialID: String
    let kind: GuideMaterialKind
    let title: String

    var id: String { materialID }

    init(
        materialID: String,
        kind: GuideMaterialKind,
        title: String
    ) {
        self.materialID = materialID
        self.kind = kind
        self.title = title
    }
}
