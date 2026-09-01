import Foundation
import FirebaseFirestore

enum FirestoreContentPublishingCoding {
    static func organizationLocalizationsData(_ values: [String: OrganizationLocalizedContent]) -> [String: Any] {
        values.mapValues { value in
            var data: [String: Any] = [
                "name": value.name,
                "shortDescription": value.shortDescription,
                "fullDescription": value.fullDescription,
                "services": value.services
            ]
            data["missionStatement"] = value.missionStatement
            data["serviceArea"] = value.serviceArea
            data["specialHoursNote"] = value.specialHoursNote
            data["currentOfferTitle"] = value.currentOfferTitle
            data["currentOfferDetails"] = value.currentOfferDetails
            return data.compactMapValues { $0 }
        }
    }

    static func organizationLocalizations(from value: Any?) -> [String: OrganizationLocalizedContent] {
        guard let entries = value as? [String: Any] else { return [:] }
        return entries.reduce(into: [:]) { result, entry in
            guard let data = entry.value as? [String: Any],
                  let name = data["name"] as? String,
                  let shortDescription = data["shortDescription"] as? String,
                  let fullDescription = data["fullDescription"] as? String else { return }
            result[entry.key] = OrganizationLocalizedContent(
                name: name,
                shortDescription: shortDescription,
                fullDescription: fullDescription,
                missionStatement: data["missionStatement"] as? String,
                serviceArea: data["serviceArea"] as? String,
                specialHoursNote: data["specialHoursNote"] as? String,
                services: data["services"] as? [String] ?? [],
                currentOfferTitle: data["currentOfferTitle"] as? String,
                currentOfferDetails: data["currentOfferDetails"] as? String
            )
        }
    }

    static func newsLocalizationsData(_ values: [String: NewsLocalizedContent]) -> [String: Any] {
        values.mapValues { ["title": $0.title, "subtitle": $0.subtitle, "body": $0.body] }
    }

    static func newsLocalizations(from value: Any?) -> [String: NewsLocalizedContent] {
        guard let values = value as? [String: Any] else { return [:] }
        return values.reduce(into: [:]) { result, entry in
            guard let data = entry.value as? [String: Any],
                  let title = data["title"] as? String,
                  let subtitle = data["subtitle"] as? String,
                  let body = data["body"] as? String else { return }
            result[entry.key] = NewsLocalizedContent(title: title, subtitle: subtitle, body: body)
        }
    }

    static func eventLocalizationsData(_ values: [String: EventLocalizedContent]) -> [String: Any] {
        values.mapValues { ["title": $0.title, "summary": $0.summary, "details": $0.details] }
    }

    static func eventLocalizations(from value: Any?) -> [String: EventLocalizedContent] {
        guard let values = value as? [String: Any] else { return [:] }
        return values.reduce(into: [:]) { result, entry in
            guard let data = entry.value as? [String: Any],
                  let title = data["title"] as? String,
                  let summary = data["summary"] as? String,
                  let details = data["details"] as? String else { return }
            result[entry.key] = EventLocalizedContent(title: title, summary: summary, details: details)
        }
    }

    static func externalActionData(_ action: ExternalContentAction?) -> [String: Any]? {
        guard let action, action.webURL != nil else { return nil }
        var data: [String: Any] = ["url": action.url]
        if let title = action.title { data["title"] = title }
        return data
    }

    static func externalAction(from value: Any?) -> ExternalContentAction? {
        guard let data = value as? [String: Any], let url = data["url"] as? String else { return nil }
        let action = ExternalContentAction(title: data["title"] as? String, url: url)
        return action.webURL == nil ? nil : action
    }

    static func mediaData(_ metadata: ContentMediaMetadata?) -> [String: Any]? {
        guard let metadata else { return nil }
        var data: [String: Any] = [:]
        if let caption = metadata.caption { data["caption"] = caption }
        if let alternativeText = metadata.alternativeText { data["alternativeText"] = alternativeText }
        if let credit = metadata.credit { data["credit"] = credit }
        return data.isEmpty ? nil : data
    }

    static func media(from value: Any?) -> ContentMediaMetadata? {
        guard let data = value as? [String: Any] else { return nil }
        let metadata = ContentMediaMetadata(
            caption: data["caption"] as? String,
            alternativeText: data["alternativeText"] as? String,
            credit: data["credit"] as? String
        )
        return metadata.caption == nil && metadata.alternativeText == nil && metadata.credit == nil ? nil : metadata
    }

    static func newsMediaData(_ metadata: NewsMediaMetadata?) -> [String: Any]? {
        mediaData(metadata)
    }

    static func newsMedia(from value: Any?) -> NewsMediaMetadata? {
        media(from: value)
    }

    static func eventMediaData(_ metadata: EventMediaMetadata?) -> [String: Any]? {
        mediaData(metadata)
    }

    static func eventMedia(from value: Any?) -> EventMediaMetadata? {
        media(from: value)
    }

    static func occurrencesData(_ occurrences: [EventOccurrence]) -> [[String: Any]] {
        occurrences.map {
            [
                "id": $0.id,
                "startDate": Timestamp(date: $0.startDate),
                "endDate": Timestamp(date: $0.endDate),
                "isAllDay": $0.isAllDay,
                "status": $0.status.rawValue
            ]
        }
    }

    static func occurrences(from value: Any?) -> [EventOccurrence] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.compactMap { data in
            guard let startDate = (data["startDate"] as? Timestamp)?.dateValue(),
                  let endDate = (data["endDate"] as? Timestamp)?.dateValue(),
                  endDate >= startDate else { return nil }
            return EventOccurrence(
                id: data["id"] as? String ?? UUID().uuidString,
                startDate: startDate,
                endDate: endDate,
                isAllDay: data["isAllDay"] as? Bool ?? false,
                status: (data["status"] as? String).flatMap(EventOccurrenceStatus.init(rawValue:)) ?? .scheduled
            )
        }.sorted { $0.startDate < $1.startDate }
    }

    static func pricingData(_ pricing: EventPricing) -> [String: Any] {
        var data: [String: Any] = ["kind": pricing.kind.rawValue, "currencyCode": pricing.currencyCode]
        if let amount = pricing.amount { data["amount"] = amount }
        if let maximumAmount = pricing.maximumAmount { data["maximumAmount"] = maximumAmount }
        if let note = pricing.note { data["note"] = note }
        return data
    }

    static func pricing(from value: Any?) -> EventPricing? {
        guard let data = value as? [String: Any],
              let kindValue = data["kind"] as? String,
              let kind = EventPriceKind(rawValue: kindValue) else { return nil }
        return EventPricing(
            kind: kind,
            amount: (data["amount"] as? NSNumber)?.doubleValue,
            maximumAmount: (data["maximumAmount"] as? NSNumber)?.doubleValue,
            currencyCode: data["currencyCode"] as? String ?? "EUR",
            note: data["note"] as? String
        )
    }
}
