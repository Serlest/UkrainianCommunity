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
        do {
            return try await fetchActiveDocumentFromFirestore(type: type)
        } catch {
            // Public legal pages must remain readable offline. Management uses
            // the strict loader below so a network failure cannot be mistaken
            // for the current production version.
            return LegalDocument.hardcodedFallback(type: type)
        }
    }

    func fetchActiveDocumentForReader(type: LegalDocumentType) async throws -> LegalDocument {
        try await fetchActiveDocumentFromFirestore(type: type)
    }

    func fetchAuthoritativeActiveDocument(type: LegalDocumentType) async throws -> LegalDocument {
        try await fetchActiveDocumentFromFirestore(type: type, serverOnly: true)
    }

    private func fetchActiveDocumentFromFirestore(
        type: LegalDocumentType,
        serverOnly: Bool = false
    ) async throws -> LegalDocument {
        let pointerReference = database.collection("legalDocuments").document(type.rawValue)
        let pointerSnapshot = serverOnly
            ? try await pointerReference.getDocument(source: .server)
            : try await pointerReference.getDocument()
        guard
            let pointerData = pointerSnapshot.data(),
            let activeVersion = pointerData["activeVersion"] as? String,
            let pointerVersionNumber = pointerData["versionNumber"] as? Int,
            !activeVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            LegalDocumentDraft.hasConsistentVersionIdentifier(
                activeVersion,
                versionNumber: pointerVersionNumber
            ),
            Self.matchesIfPresent(pointerData["documentType"] as? String, expected: type.rawValue),
            Self.matchesIfPresent(
                pointerData["status"] as? String,
                expected: LegalDocumentStatus.published.rawValue
            )
        else { throw AppError.notFound }

        let versionReference = pointerReference.collection("versions").document(activeVersion)
        let versionSnapshot = serverOnly
            ? try await versionReference.getDocument(source: .server)
            : try await versionReference.getDocument()

        guard let versionData = versionSnapshot.data(),
              Self.matchesIfPresent(versionData["documentType"] as? String, expected: type.rawValue),
              Self.matchesIfPresent(versionData["version"] as? String, expected: activeVersion),
              (versionData["versionNumber"] as? Int) == pointerVersionNumber,
              Self.matchesIfPresent(
                versionData["status"] as? String,
                expected: LegalDocumentStatus.published.rawValue
              ),
              Self.matchesWhenExpectedPresent(
                versionData["requiresAcceptance"] as? Bool,
                expected: pointerData["requiresAcceptance"] as? Bool
              ),
              Self.matchesWhenExpectedPresent(
                (versionData["defaultLocale"] as? String)?.lowercased(),
                expected: (pointerData["defaultLocale"] as? String)?.lowercased()
              )
        else { throw AppError.notFound }

        let document = decodeDocument(type: type, version: activeVersion, data: versionData)
        guard Self.hasValidContentHashes(document) else { throw AppError.notFound }
        return document
    }

    func fetchManagementState(type: LegalDocumentType) async throws -> LegalDocumentManagementState {
        let activeDocument = try await fetchActiveDocumentFromFirestore(type: type, serverOnly: true)
        let draftSnapshot = try await database
            .collection("legalDocuments")
            .document(type.rawValue)
            .collection("versions")
            .whereField("status", isEqualTo: LegalDocumentStatus.draft.rawValue)
            .limit(to: 2)
            .getDocuments(source: .server)
        guard draftSnapshot.documents.count <= 1 else {
            // Never pick an arbitrary mutable legal draft. An owner must first
            // resolve the duplicate server state before editing or publishing.
            throw AppError.validationFailed
        }
        let draftDocument = draftSnapshot.documents.first.map { snapshot in
            decodeDocument(type: type, version: snapshot.documentID, data: snapshot.data())
        }
        if let draftDocument {
            guard draftDocument.status == .draft,
                  Self.hasValidContentHashes(draftDocument),
                  LegalDocumentDraft.hasConsistentVersionIdentifier(
                    draftDocument.version,
                    versionNumber: draftDocument.versionNumber
                  ),
                  draftDocument.supersedesVersion == nil
                    || draftDocument.supersedesVersion == activeDocument.version,
                  draftDocument.versionNumber == activeDocument.versionNumber + 1
            else { throw AppError.validationFailed }
        }

        return LegalDocumentManagementState(
            type: type,
            activeDocument: activeDocument,
            draftDocument: draftDocument
        )
    }

    func saveDraft(_ draft: LegalDocumentDraft, updatedBy userID: String) async throws {
        let pointerReference = database.collection("legalDocuments").document(draft.type.rawValue)
        let reference = versionReference(type: draft.type, version: draft.version)
        guard draft.hasConsistentVersionIdentifier else { throw AppError.validationFailed }
        let draftPayload = payload(for: draft, status: .draft, userID: userID)

        _ = try await database.runTransaction { transaction, errorPointer -> Any? in
            do {
                let pointerSnapshot = try transaction.getDocument(pointerReference)
                let snapshot = try transaction.getDocument(reference)
                guard let pointerData = pointerSnapshot.data(),
                      Self.matchesIfPresent(pointerData["documentType"] as? String, expected: draft.type.rawValue),
                      Self.matchesIfPresent(
                        pointerData["status"] as? String,
                        expected: LegalDocumentStatus.published.rawValue
                      ),
                      pointerData["activeVersion"] as? String == draft.supersedesVersion,
                      (pointerData["versionNumber"] as? Int).map({ draft.versionNumber == $0 + 1 }) == true
                else { throw AppError.validationFailed }
                var payload = draftPayload
                payload["updatedAt"] = FieldValue.serverTimestamp()
                payload["updatedBy"] = userID

                if snapshot.exists {
                    let data = snapshot.data() ?? [:]
                    guard data["status"] as? String == LegalDocumentStatus.draft.rawValue,
                          data["contentHash"] as? String == draft.sourceContentHash
                    else { throw AppError.validationFailed }
                    transaction.updateData(payload, forDocument: reference)
                } else {
                    guard draft.sourceContentHash == nil else { throw AppError.validationFailed }
                    payload["createdAt"] = FieldValue.serverTimestamp()
                    payload["createdBy"] = userID
                    transaction.setData(payload, forDocument: reference)
                }
            } catch {
                errorPointer?.pointee = error as NSError
            }
            return nil
        }
    }

    func publishDraft(_ draft: LegalDocumentDraft, publishedBy userID: String) async throws {
        guard draft.hasConsistentVersionIdentifier else { throw AppError.validationFailed }
        let documentReference = database.collection("legalDocuments").document(draft.type.rawValue)
        let versionReference = versionReference(type: draft.type, version: draft.version)
        let publishedPayload = payload(
            for: draft,
            status: .published,
            userID: userID
        )
        let publishedAt = FieldValue.serverTimestamp()

        do {
            _ = try await database.runTransaction { transaction, errorPointer -> Any? in
                do {
                    let versionSnapshot = try transaction.getDocument(versionReference)
                    let pointerSnapshot = try transaction.getDocument(documentReference)
                    guard let versionData = versionSnapshot.data(),
                          let pointerData = pointerSnapshot.data()
                    else { throw AppError.notFound }
                    let activeVersion = pointerData["activeVersion"] as? String
                    let activeVersionNumber = pointerData["versionNumber"] as? Int
                    guard Self.matchesIfPresent(
                            pointerData["documentType"] as? String,
                            expected: draft.type.rawValue
                          ),
                          Self.matchesIfPresent(
                            pointerData["status"] as? String,
                            expected: LegalDocumentStatus.published.rawValue
                          ),
                          versionData["documentType"] as? String == draft.type.rawValue,
                          versionData["version"] as? String == draft.version,
                          versionData["versionNumber"] as? Int == draft.versionNumber,
                          versionData["status"] as? String == LegalDocumentStatus.draft.rawValue,
                          versionData["contentHash"] as? String == draft.sourceContentHash,
                          activeVersion == draft.supersedesVersion,
                          activeVersionNumber.map({ draft.versionNumber == $0 + 1 }) == true
                    else { throw AppError.validationFailed }

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
                        "defaultLocale": draft.defaultLocale.lowercased(),
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
        } catch {
            // A transaction can commit server-side while its response is lost.
            // Treat an exact authoritative read-back as success and prevent a
            // second publication attempt against an immutable version.
            if await publicationIsActive(draft) { return }
            throw error
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
            publishedBy: data["publishedBy"] as? String,
            supersedesVersion: data["supersedesVersion"] as? String
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
            "baseContentHash": draft.sourceContentHash ?? NSNull(),
            "changeSummary": draft.changeSummary ?? NSNull(),
            "supersedesVersion": draft.supersedesVersion ?? NSNull(),
            "publishedAt": NSNull(),
            "publishedBy": NSNull()
        ]
    }

    private static func normalizedMarkdown(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matchesIfPresent<T: Equatable>(_ value: T?, expected: T) -> Bool {
        value.map { $0 == expected } ?? true
    }

    private static func matchesWhenExpectedPresent<T: Equatable>(_ value: T?, expected: T?) -> Bool {
        guard let expected else { return true }
        return value == expected
    }

    private static func hasValidContentHashes(_ document: LegalDocument) -> Bool {
        guard let documentHash = document.contentHash,
              document.locales.values.allSatisfy({ $0.contentHash != nil })
        else { return false }

        let localeKeys = Set(document.locales.keys.map { $0.lowercased() })
        let supportedLocaleKeys = Set(AppLanguage.allCases.map(\.rawValue))
        guard supportedLocaleKeys.isSubset(of: localeKeys),
              localeKeys.contains(document.defaultLocale.lowercased()),
              document.canonicalLocale.map({ localeKeys.contains($0.lowercased()) }) ?? true
        else { return false }

        let localePayloads = document.locales.reduce(into: [String: [String: Any]]()) { result, entry in
            let locale = entry.key.lowercased()
            let title = entry.value.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let markdown = normalizedMarkdown(entry.value.contentMarkdown)
            let localeHash = sha256(markdown)
            guard !title.isEmpty,
                  !markdown.isEmpty,
                  entry.value.contentHash == localeHash
            else { return }
            result[locale] = [
                "title": title,
                "contentMarkdown": markdown,
                "contentHash": localeHash
            ]
        }
        guard localePayloads.count == document.locales.count else { return false }
        let currentHash = sha256(canonicalHashInput(locales: localePayloads))
        let legacySeedHash = sha256(canonicalLegacySeedHashInput(document: document))
        return documentHash == currentHash || documentHash == legacySeedHash
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

    private static func canonicalLegacySeedHashInput(document: LegalDocument) -> String {
        document.locales.keys.sorted().map { locale in
            let content = document.locales[locale]
            return [
                locale,
                content?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                normalizedMarkdown(content?.contentMarkdown ?? ""),
                content?.contentText ?? "",
                content?.contentHash ?? ""
            ].joined(separator: "\n")
        }
        .joined(separator: "\n---\n")
    }

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func publicationIsActive(_ draft: LegalDocumentDraft) async -> Bool {
        do {
            let pointerReference = database.collection("legalDocuments").document(draft.type.rawValue)
            let pointer = try await pointerReference.getDocument(source: .server)
            let version = try await versionReference(type: draft.type, version: draft.version)
                .getDocument(source: .server)
            guard let pointerData = pointer.data(), let versionData = version.data() else { return false }
            return pointerData["activeVersion"] as? String == draft.version
                && pointerData["versionNumber"] as? Int == draft.versionNumber
                && pointerData["status"] as? String == LegalDocumentStatus.published.rawValue
                && versionData["version"] as? String == draft.version
                && versionData["versionNumber"] as? Int == draft.versionNumber
                && versionData["status"] as? String == LegalDocumentStatus.published.rawValue
                && versionData["contentHash"] as? String == draft.normalizedContentHash
        } catch {
            return false
        }
    }

    private static let responseDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
