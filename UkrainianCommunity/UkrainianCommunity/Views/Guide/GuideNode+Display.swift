import Foundation

extension GuideNode {
    var displaySystemImage: String {
        switch kind {
        case .section:
            "rectangle.3.group"
        case .folder:
            "folder"
        }
    }
}
