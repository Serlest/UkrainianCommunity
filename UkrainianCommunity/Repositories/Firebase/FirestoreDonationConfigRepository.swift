import CryptoKit
import FirebaseFirestore
import Foundation

struct FirestoreDonationConfigRepository: DonationConfigRepository {
    private enum Field: String, CaseIterable {
        case isEnabled
        case donationURL
        case titleUK
        case messageUK
        case buttonTitleUK
        case titleDE
        case messageDE
        case buttonTitleDE
        case updatedAt
        case updatedBy
    }

    private let document: DocumentReference
    private let diagnostics: DonationConfigDiagnostics

    init(database: Firestore = Firestore.firestore(), diagnostics: DonationConfigDiagnostics = .live) {
        document = database.collection(DonationConfig.collectionPath).document(DonationConfig.documentID)
        self.diagnostics = diagnostics
    }

    func fetchDonationConfig() async throws -> DonationConfig? {
        do {
            let snapshot = try await document.getDocument(source: .server)
            guard snapshot.exists, let data = snapshot.data() else {
                return nil
            }
            return makeConfig(from: data)
        } catch {
            throw appError(from: error)
        }
    }

    func listenDonationConfig(onChange: @escaping @MainActor (DonationConfig) -> Void,
                              onError: @escaping @MainActor (AppError) -> Void) -> AppRealtimeListener? {
        FirebaseRealtimeListener(document.addSnapshotListener { snapshot, error in
            if let error { Task { @MainActor in onError(appError(from: error)) }; return }
            guard let snapshot, !snapshot.metadata.isFromCache, !snapshot.metadata.hasPendingWrites else { return }
            let config = snapshot.data().map(makeConfig) ?? .defaults
            Task { @MainActor in onChange(config) }
        })
    }

    func saveDonationConfig(_ config: DonationConfig, updatedBy userID: String) async throws -> DonationConfig {
        let userID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = config.normalizedForSaving()
        guard !userID.isEmpty, normalized.validationIssue == nil else { throw AppError.validationFailed }
        do {
            _ = try await document.firestore.runTransaction { transaction, errorPointer -> Any? in
                do {
                    let snapshot = try transaction.getDocument(document)
                    guard snapshot.data().map(Self.revision) == config.sourceRevision else {
                        throw NSError(domain: "DonationConfigConflict", code: 1)
                    }
                    transaction.setData(makeData(from: normalized, updatedBy: userID), forDocument: document)
                } catch { errorPointer?.pointee = error as NSError }
                return nil
            }
        } catch {
            if (error as NSError).domain == "DonationConfigConflict" {
                await diagnostics.failed(DonationConfigSaveError.conflict, userID, "writeConfiguration", config.sourceRevision)
                throw DonationConfigSaveError.conflict
            }
            // A write error can be a lost acknowledgement. Only an authoritative match proves success.
            if Self.mayHaveCommitted(error),
               let saved = try? await RefreshRequest.run(operation: { try await fetchDonationConfig() }),
               Self.confirmsWrite(saved, input: normalized, userID: userID) {
                await diagnostics.confirmed(saved, userID)
                return saved
            }
            await diagnostics.failed(error, userID, "writeConfiguration", config.sourceRevision)
            throw appError(from: error)
        }
        guard let saved = try? await RefreshRequest.run(operation: { try await fetchDonationConfig() }),
              Self.confirmsWrite(saved, input: normalized, userID: userID) else {
            await diagnostics.failed(DonationConfigSaveError.unconfirmed, userID, "confirmConfiguration", config.sourceRevision)
            throw DonationConfigSaveError.unconfirmed
        }
        await diagnostics.confirmed(saved, userID)
        return saved
    }

    static func confirmsWrite(_ saved: DonationConfig, input: DonationConfig, userID: String) -> Bool {
        saved.sourceRevision != nil && saved.sourceRevision != input.sourceRevision
            && saved.updatedBy == userID && saved.hasSameContent(as: input)
    }

    static func mayHaveCommitted(_ error: Error) -> Bool {
        let error = error as NSError
        guard error.domain == FirestoreErrorDomain,
              let code = FirestoreErrorCode.Code(rawValue: error.code) else { return false }
        return [.unavailable, .deadlineExceeded, .unknown, .internal, .aborted].contains(code)
    }

    static func revision(_ data: [String: Any]) -> String {
        let canonical = data.mapValues { value -> Any in
            if let timestamp = value as? Timestamp { return ["seconds": timestamp.seconds, "nanoseconds": timestamp.nanoseconds] as [String: Any] }
            return value
        }
        guard let bytes = try? JSONSerialization.data(withJSONObject: canonical, options: [.sortedKeys]) else { return "invalid" }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private func makeConfig(from data: [String: Any]) -> DonationConfig {
        DonationConfig(
            isEnabled: data[Field.isEnabled.rawValue] as? Bool ?? false,
            donationURL: data[Field.donationURL.rawValue] as? String ?? "",
            titleUK: data[Field.titleUK.rawValue] as? String ?? DonationConfig.defaults.titleUK,
            messageUK: data[Field.messageUK.rawValue] as? String ?? DonationConfig.defaults.messageUK,
            buttonTitleUK: data[Field.buttonTitleUK.rawValue] as? String ?? DonationConfig.defaults.buttonTitleUK,
            titleDE: data[Field.titleDE.rawValue] as? String ?? DonationConfig.defaults.titleDE,
            messageDE: data[Field.messageDE.rawValue] as? String ?? DonationConfig.defaults.messageDE,
            buttonTitleDE: data[Field.buttonTitleDE.rawValue] as? String ?? DonationConfig.defaults.buttonTitleDE,
            updatedAt: (data[Field.updatedAt.rawValue] as? Timestamp)?.dateValue(),
            updatedBy: data[Field.updatedBy.rawValue] as? String,
            sourceRevision: Self.revision(data)
        )
    }

    private func makeData(from config: DonationConfig, updatedBy userID: String) -> [String: Any] {
        [
            Field.isEnabled.rawValue: config.isEnabled,
            Field.donationURL.rawValue: trimmed(config.donationURL),
            Field.titleUK.rawValue: trimmed(config.titleUK),
            Field.messageUK.rawValue: trimmed(config.messageUK),
            Field.buttonTitleUK.rawValue: trimmed(config.buttonTitleUK),
            Field.titleDE.rawValue: trimmed(config.titleDE),
            Field.messageDE.rawValue: trimmed(config.messageDE),
            Field.buttonTitleDE.rawValue: trimmed(config.buttonTitleDE),
            Field.updatedAt.rawValue: FieldValue.serverTimestamp(),
            Field.updatedBy.rawValue: userID
        ]
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func appError(from error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        let nsError = error as NSError
        guard let code = FirestoreErrorCode.Code(rawValue: nsError.code) else {
            return .unknown
        }

        switch code {
        case .permissionDenied:
            return .permissionDenied
        case .unavailable, .deadlineExceeded:
            return .network
        case .notFound:
            return .notFound
        default:
            return .unknown
        }
    }
}
