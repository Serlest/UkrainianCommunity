import CryptoKit
import FirebaseFirestore
import Foundation

struct FirestoreLegalDocumentRepository: LegalDocumentRepository {
    private let database: Firestore
    private let functionsClient: CloudFunctionsClient

    init(
        database: Firestore = Firestore.firestore(),
        functionsClient: CloudFunctionsClient = .shared
    ) {
        self.database = database
        self.functionsClient = functionsClient
    }

    func fetchActiveDocument(type: LegalDocumentType) async throws -> LegalDocument {
        let pointerReference = database.collection("legalDocuments").document(type.rawValue)

        do {
            let pointerSnapshot = try await pointerReference.getDocument()
            guard
                let pointerData = pointerSnapshot.data(),
                let activeVersion = pointerData["activeVersion"] as? String,
                !activeVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return LegalDocument.hardcodedFallback(type: type)
            }

            let versionSnapshot = try await pointerReference
                .collection("versions")
                .document(activeVersion)
                .getDocument()

            guard let versionData = versionSnapshot.data() else {
                return LegalDocument.hardcodedFallback(type: type)
            }

            return decodeDocument(type: type, version: activeVersion, data: versionData)
        } catch {
            return LegalDocument.hardcodedFallback(type: type)
        }
    }

    func fetchManagementState(type: LegalDocumentType) async throws -> LegalDocumentManagementState {
        let activeDocument = try await fetchActiveDocument(type: type)
        let draftSnapshot = try await database
            .collection("legalDocuments")
            .document(type.rawValue)
            .collection("versions")
            .whereField("status", isEqualTo: LegalDocumentStatus.draft.rawValue)
            .limit(to: 1)
            .getDocuments()
        let draftDocument = draftSnapshot.documents.first.map { snapshot in
            decodeDocument(type: type, version: snapshot.documentID, data: snapshot.data())
        }

        return LegalDocumentManagementState(
            type: type,
            activeDocument: activeDocument,
            draftDocument: draftDocument
        )
    }

    func saveDraft(_ draft: LegalDocumentDraft, updatedBy userID: String) async throws {
        let reference = versionReference(type: draft.type, version: draft.version)
        let snapshot = try await reference.getDocument()
        var payload = payload(for: draft, status: .draft, userID: userID)
        payload["updatedAt"] = FieldValue.serverTimestamp()
        payload["updatedBy"] = userID

        if snapshot.exists {
            try await reference.updateData(payload)
        } else {
            payload["createdAt"] = FieldValue.serverTimestamp()
            payload["createdBy"] = userID
            try await reference.setData(payload)
        }
    }

    func publishDraft(_ draft: LegalDocumentDraft, publishedBy userID: String) async throws {
        let documentReference = database.collection("legalDocuments").document(draft.type.rawValue)
        let versionReference = versionReference(type: draft.type, version: draft.version)
        let publishedPayload = payload(for: draft, status: .published, userID: userID)
        let publishedAt = FieldValue.serverTimestamp()

        _ = try await database.runTransaction { transaction, errorPointer -> Any? in
            do {
                let versionSnapshot = try transaction.getDocument(versionReference)
                guard versionSnapshot.exists else {
                    throw AppError.notFound
                }

                transaction.updateData(
                    publishedPayload.merging([
                        "updatedAt": publishedAt,
                        "updatedBy": userID,
                        "publishedAt": publishedAt,
                        "publishedBy": userID
                    ]) { _, new in new },
                    forDocument: versionReference
                )

                transaction.setData([
                    "documentType": draft.type.rawValue,
                    "activeVersion": draft.version,
                    "versionNumber": draft.versionNumber,
                    "status": LegalDocumentStatus.published.rawValue,
                    "requiresAcceptance": draft.requiresAcceptance,
                    "defaultLocale": draft.defaultLocale,
                    "updatedAt": publishedAt,
                    "updatedBy": userID,
                    "publishedAt": publishedAt,
                    "publishedBy": userID,
                    "changeSummary": draft.changeSummary ?? NSNull()
                ], forDocument: documentReference)
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
        }
    }

    func acceptDocument(
        type: LegalDocumentType,
        version: String,
        appVersion: String?,
        locale: String?,
        acceptedFromPlatform: String
    ) async throws -> LegalAcceptanceReceipt {
        let response = try await functionsClient.acceptLegalDocument(
            type: type,
            version: version,
            appVersion: appVersion,
            locale: locale,
            acceptedFromPlatform: acceptedFromPlatform
        )

        return LegalAcceptanceReceipt(
            documentType: response.documentType,
            version: response.version,
            acceptedAt: Self.responseDateFormatter.date(from: response.acceptedAt) ?? .now
        )
    }

    private func decodeDocument(
        type: LegalDocumentType,
        version: String,
        data: [String: Any]
    ) -> LegalDocument {
        let fallback = LegalDocument.hardcodedFallback(type: type)
        let rawLocales = data["locales"] as? [String: [String: Any]] ?? [:]
        let locales = rawLocales.reduce(into: [String: LegalDocumentLocaleContent]()) { result, entry in
            let locale = entry.key.lowercased()
            let rawContent = entry.value
            guard
                let title = rawContent["title"] as? String,
                let contentMarkdown = rawContent["contentMarkdown"] as? String
            else {
                return
            }

            result[locale] = LegalDocumentLocaleContent(
                title: title,
                contentMarkdown: contentMarkdown,
                contentText: rawContent["contentText"] as? String,
                contentHash: rawContent["contentHash"] as? String
            )
        }

        return LegalDocument(
            id: type.rawValue,
            type: type,
            version: data["version"] as? String ?? version,
            versionNumber: data["versionNumber"] as? Int ?? 1,
            locales: locales.isEmpty ? fallback.locales : locales,
            defaultLocale: data["defaultLocale"] as? String ?? fallback.defaultLocale,
            canonicalLocale: data["canonicalLocale"] as? String ?? fallback.canonicalLocale,
            contentHash: data["contentHash"] as? String,
            changeSummary: data["changeSummary"] as? String,
            requiresAcceptance: data["requiresAcceptance"] as? Bool ?? true,
            status: (data["status"] as? String).flatMap(LegalDocumentStatus.init(rawValue:)) ?? .published,
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue(),
            updatedBy: data["updatedBy"] as? String,
            publishedAt: (data["publishedAt"] as? Timestamp)?.dateValue(),
            publishedBy: data["publishedBy"] as? String
        )
    }

    private func versionReference(
        type: LegalDocumentType,
        version: String
    ) -> DocumentReference {
        database.collection("legalDocuments")
            .document(type.rawValue)
            .collection("versions")
            .document(version)
    }

    private func payload(
        for draft: LegalDocumentDraft,
        status: LegalDocumentStatus,
        userID: String
    ) -> [String: Any] {
        let localePayloads = draft.locales.reduce(into: [String: [String: Any]]()) { result, entry in
            let normalizedMarkdown = Self.normalizedMarkdown(entry.value.contentMarkdown)
            let localeHash = Self.sha256(normalizedMarkdown)
            result[entry.key.lowercased()] = [
                "title": entry.value.title.trimmingCharacters(in: .whitespacesAndNewlines),
                "contentMarkdown": normalizedMarkdown,
                "contentText": entry.value.contentText ?? NSNull(),
                "contentHash": localeHash
            ]
        }
        let documentHash = Self.sha256(Self.canonicalHashInput(locales: localePayloads))

        return [
            "documentType": draft.type.rawValue,
            "version": draft.version,
            "versionNumber": draft.versionNumber,
            "status": status.rawValue,
            "requiresAcceptance": draft.requiresAcceptance,
            "defaultLocale": draft.defaultLocale.lowercased(),
            "canonicalLocale": draft.canonicalLocale.lowercased(),
            "locales": localePayloads,
            "contentHash": documentHash,
            "changeSummary": draft.changeSummary ?? NSNull(),
            "supersedesVersion": draft.supersedesVersion ?? NSNull()
        ]
    }

    private static func normalizedMarkdown(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func canonicalHashInput(locales: [String: [String: Any]]) -> String {
        locales.keys.sorted().map { locale in
            let content = locales[locale] ?? [:]
            return [
                locale,
                content["title"] as? String ?? "",
                content["contentMarkdown"] as? String ?? "",
                content["contentHash"] as? String ?? ""
            ].joined(separator: "\n")
        }
        .joined(separator: "\n---\n")
    }

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let responseDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
