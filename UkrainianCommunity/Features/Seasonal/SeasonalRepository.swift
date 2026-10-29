import FirebaseAuth
import FirebaseFirestore
import Foundation

struct SeasonalDocument {
    var library = SeasonalLibrary()
    var revision: String?
}

protocol SeasonalRepositoryProtocol {
    func fetch(path: String) async throws -> SeasonalDocument
    func save(_ library: SeasonalLibrary, path: String, expectedRevision: String?, userID: String) async throws -> SeasonalDocument
}

struct SeasonalRepository: SeasonalRepositoryProtocol {
    static let libraryPath = "seasonalLibraries/current"
    static let presentationPath = "seasonalPresentations/current"
    private var database: Firestore { Firestore.firestore() }

    func fetch(path: String) async throws -> SeasonalDocument {
        try await Self.retryTransientRead { try Self.decode(try await database.document(path).getDocument(source: .server)) }
    }

    /// Bounded retries for transient server reads only. Permission/conflict/validation never retry.
    static func retryTransientRead<T>(_ operation:() async throws -> T) async throws -> T {
        for attempt in 0..<3 {
            do { return try await operation() }
            catch {
                let failure=error as NSError
                guard !Task.isCancelled,attempt<2,failure.domain==FirestoreErrorDomain,
                      failure.code==FirestoreErrorCode.Code.unavailable.rawValue || failure.code==FirestoreErrorCode.Code.deadlineExceeded.rawValue else { throw error }
                try await Task.sleep(for:.milliseconds(attempt==0 ? 250:750))
            }
        }
        throw SeasonalError.unavailable
    }

    static func decode(_ snapshot: DocumentSnapshot) throws -> SeasonalDocument {
        guard snapshot.exists else { return SeasonalDocument() }
        guard let data = snapshot.data(), data["schemaVersion"] as? Int == 1,
              let revision = data["revision"] as? String, !revision.isEmpty,
              let payload = data["payload"] as? String else { throw SeasonalError.invalidPackage }
        return SeasonalDocument(library: try SeasonalLibrary.decode(Data(payload.utf8)), revision: revision)
    }

    /// Optimistic revision and principal checks; an ambiguous reply is accepted only after exact server readback.
    func save(_ library: SeasonalLibrary, path: String, expectedRevision: String?, userID: String) async throws -> SeasonalDocument {
        guard [Self.libraryPath, Self.presentationPath].contains(path),
              Auth.auth().currentUser?.uid == userID else { throw SeasonalError.ownerOnly }
        let payload = String(decoding: try library.encoded(), as: UTF8.self)
        let revision = UUID().uuidString
        let reference = database.document(path)
        do {
            _ = try await database.runTransaction { transaction, errorPointer -> Any? in
                do {
                    guard Auth.auth().currentUser?.uid == userID else { throw SeasonalError.ownerOnly }
                    let old = try transaction.getDocument(reference)
                    // A transaction may be replayed after its commit reply was lost.
                    // Accept only this exact operation, never another device's revision.
                    if (old.data()?["revision"] as? String) == revision,
                       (old.data()?["payload"] as? String) == payload { return nil }
                    guard (old.data()?["revision"] as? String) == expectedRevision else {
                        throw NSError(domain: "SeasonalConflict", code: 1)
                    }
                    transaction.setData(["schemaVersion": 1, "payload": payload, "revision": revision,
                                         "updatedBy": userID, "updatedAt": FieldValue.serverTimestamp()], forDocument: reference)
                } catch { errorPointer?.pointee = error as NSError }
                return nil
            }
        } catch {
            if (error as NSError).domain == "SeasonalConflict" { throw SeasonalError.conflict }
            if Auth.auth().currentUser?.uid == userID,
               let confirmed = try? await fetch(path: path), confirmed.revision == revision,
               (try? confirmed.library.encoded()) == Data(payload.utf8) { return confirmed }
            throw error
        }
        guard Auth.auth().currentUser?.uid == userID else { throw SeasonalError.ownerOnly }
        let confirmed = try await fetch(path: path)
        guard confirmed.revision == revision, (try? confirmed.library.encoded()) == Data(payload.utf8) else { throw SeasonalError.conflict }
        return confirmed
    }
}
