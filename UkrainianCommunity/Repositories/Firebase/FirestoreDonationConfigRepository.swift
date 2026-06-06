import FirebaseFirestore
import Foundation

struct FirestoreDonationConfigRepository: DonationConfigRepository {
    private enum Field: String {
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

    private let document = Firestore.firestore()
        .collection(DonationConfig.collectionPath)
        .document(DonationConfig.documentID)

    func fetchDonationConfig() async throws -> DonationConfig? {
        do {
            let snapshot = try await document.getDocument()
            guard snapshot.exists, let data = snapshot.data() else {
                return nil
            }
            return makeConfig(from: data)
        } catch {
            throw appError(from: error)
        }
    }

    func saveDonationConfig(_ config: DonationConfig, updatedBy userID: String) async throws {
        let trimmedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserID.isEmpty else {
            throw AppError.validationFailed
        }

        do {
            let normalizedConfig = config.normalizedForSaving()
            try validate(normalizedConfig)
            try await document.setData(makeData(from: normalizedConfig, updatedBy: trimmedUserID), merge: false)
        } catch {
            throw appError(from: error)
        }
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
            updatedBy: data[Field.updatedBy.rawValue] as? String
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

    private func validate(_ config: DonationConfig) throws {
        let trimmedURL = trimmed(config.donationURL)
        if config.isEnabled && trimmedURL.isEmpty {
            throw AppError.validationFailed
        }

        if !trimmedURL.isEmpty && config.validDonationURL == nil {
            throw AppError.validationFailed
        }
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
