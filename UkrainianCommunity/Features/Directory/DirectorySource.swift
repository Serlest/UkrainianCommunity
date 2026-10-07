import SwiftUI

struct DirectorySource: Identifiable {
    let name: String
    let url: URL

    var id: String { url.absoluteString }

    init(name: String, url: String) {
        self.name = name
        self.url = URL(string: url)!
    }
}
