import FirebaseFunctions
import Foundation

/// The same request/receipt contract is used by the editor, tests and server.
@MainActor
struct DirectoryContentAPI {
    struct Receipt { let categoryID: String; let revision: Int }
    var save: (String, String, Int) async throws -> Receipt
    var delete: (String, Int) async throws -> Receipt

    private static func call(_ name: String, data: [String: Any]) async throws -> Receipt {
        let response = try await Functions.functions(region: "europe-west3").httpsCallable(name).call(data)
        guard let result = response.data as? [String: Any], let id = result["categoryId"] as? String,
              let revision = result["revision"] as? Int else { throw AppError.validationFailed }
        return Receipt(categoryID: id, revision: revision)
    }
    static let live = Self(save: { id, payload, revision in
        try await call("saveDirectoryCategory", data: ["categoryId": id, "payload": payload, "expectedRevision": revision])
    }, delete: { id, revision in
        try await call("deleteDirectoryCategory", data: ["categoryId": id, "expectedRevision": revision])
    })

    static var simulatorFixture: Self? {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           ProcessInfo.processInfo.environment["UITestDirectoryRecentPreview"] == "1" {
            return Self(save: { id, _, revision in Receipt(categoryID: id, revision: revision + 1) },
                        delete: { id, revision in Receipt(categoryID: id, revision: revision + 1) })
        }
        #endif
        return nil
    }
}
