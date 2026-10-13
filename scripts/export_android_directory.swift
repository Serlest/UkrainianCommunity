import Foundation

enum AppLanguage { case ukrainian, german }

// Compiled with the Foundation-only Directory sources. Keep this small bridge separate from
// the iOS app target so Android can bundle the exact reviewed catalog without hand copying it.
struct DirectorySource: Identifiable {
    let name: String
    let url: URL
    var id: String { url.absoluteString }
    init(name: String, url: String) {
        self.name = name
        self.url = URL(string: url)!
    }
}

enum AustrianFederalState: String, CaseIterable {
    case burgenland, kaernten, niederoesterreich, oberoesterreich, salzburg
    case steiermark, tirol, vorarlberg, wien

    var displayName: String {
        switch self {
        case .burgenland: "Burgenland"
        case .kaernten: "Kärnten"
        case .niederoesterreich: "Niederösterreich"
        case .oberoesterreich: "Oberösterreich"
        case .salzburg: "Salzburg"
        case .steiermark: "Steiermark"
        case .tirol: "Tirol"
        case .vorarlberg: "Vorarlberg"
        case .wien: "Wien"
        }
    }
}

@main
struct ExportAndroidDirectory {
    static func main() throws {
        let categories = DirectoryCatalog.categories.map(DirectoryManagedCategory.bundled)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(categories)
        FileHandle.standardOutput.write(data)
    }
}
