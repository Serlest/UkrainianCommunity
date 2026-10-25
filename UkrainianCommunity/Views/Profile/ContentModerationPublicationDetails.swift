import Foundation
import SwiftUI

nonisolated struct ContentReviewOccurrence: Codable, Equatable, Identifiable {
    let id: String
    let startDate: Double?
    let endDate: Double?
    let isAllDay: Bool
    let status: String
}

nonisolated struct ContentReviewPricing: Codable, Equatable {
    let kind: String
    let amount: Double?
    let maximumAmount: Double?
    let currencyCode: String
    let note: String?
}
nonisolated struct ContentReviewExternalAction: Codable, Equatable {
    let title: String?
    let url: String
    var webURL: URL? {
        guard let parsed = URL(string: url), parsed.scheme?.lowercased() == "https", parsed.host?.isEmpty == false else { return nil }
        return parsed
    }
}
nonisolated struct ContentReviewMediaMetadata: Codable, Equatable {
    let caption: String?
    let alternativeText: String?
    let credit: String?
}

nonisolated struct ContentReviewPublication: Codable, Equatable {
    let regionScope: String?
    let category: String?
    let additionalCategories: [String]?
    let tags: [String]?
    let locationNote: String?
    let organizerName: String?
    let organizerURL: String?
    let contactPhone: String?
    let contactEmail: String?
    let contactURL: String?
    let latitude: Double?
    let longitude: Double?
    let isAllDay: Bool?
    let requiresRegistration: Bool?
    let participationMode: String?
    let price: Double?
    let pricing: ContentReviewPricing?
    let capacity: Int?
    let audience: String?
    let minimumAge: Int?
    let maximumAge: Int?
    let externalAction: ContentReviewExternalAction?
    let mediaMetadata: ContentReviewMediaMetadata?
    let cancellationState: String?
    let cancellationReason: String?
    let occurrences: [ContentReviewOccurrence]?
}

enum ModerationAuditCopy {
    static func text(_ key: String) -> String {
        LocalizationStore.localizedString("moderation_audit." + key, defaultValue: key, table: "ModerationAudit")
    }
    static var unavailable: String { text("unavailable") }
    static var editHint: String { text("edit_hint") }
}

struct ContentModerationPublicationDetails: View {
    let item: ContentReviewItem
    private var fields: ContentReviewPublication? { item.publication }

    var body: some View {
        if let p = fields {
            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text(ModerationAuditCopy.text("publication_details")).font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    row("scope", scope(p.regionScope))
                    row("region", AustrianFederalState(rawValue: item.region)?.displayName ?? item.region)
                    row("category", ([p.category].compactMap { $0 } + (p.additionalCategories ?? [])).map(category).joined(separator: ", "))
                    row("tags", (p.tags ?? []).joined(separator: ", "))
                    row("location_note", p.locationNote)
                    row("organizer", p.organizerName)
                    webRow("organizer_website", p.organizerURL)
                    row("phone", p.contactPhone)
                    row("email", p.contactEmail)
                    webRow("contact_website", p.contactURL)
                    if let latitude = p.latitude, let longitude = p.longitude {
                        row("coordinates", "\(latitude.formatted(.number.precision(.fractionLength(2...6)).locale(LocalizationStore.locale))), \(longitude.formatted(.number.precision(.fractionLength(2...6)).locale(LocalizationStore.locale)))")
                    }
                    if item.contentType == "event" {
                        eventFields(p)
                    }
                    if let action = p.externalAction {
                        webRow("external_action", action.url, title: action.title)
                    }
                    row("image_caption", p.mediaMetadata?.caption)
                    row("image_alt", p.mediaMetadata?.alternativeText)
                    row("image_credit", p.mediaMetadata?.credit)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("content.review.publicationDetails")
        }
    }

    @ViewBuilder private func eventFields(_ p: ContentReviewPublication) -> some View {
        if let mode = p.participationMode, let mode = EventParticipationMode(rawValue: mode) {
            row("participation", mode.localizedTitle)
        } else if let required = p.requiresRegistration {
            row("participation", required ? ContentPublishingStrings.inAppRegistration : ContentPublishingStrings.noRegistration)
        }
        if let pricing = p.pricing {
            row("price", price(pricing))
            row("price_note", pricing.note)
        } else if let amount = p.price { row("price", amount.formatted(.currency(code: "EUR").locale(LocalizationStore.locale))) }
        if let capacity = p.capacity { row("capacity", capacity.formatted(.number.locale(LocalizationStore.locale))) }
        if let audience = p.audience { row("audience", EventAudience(rawValue: audience)?.title ?? audience) }
        if let minimum = p.minimumAge { row("minimum_age", minimum.formatted(.number.locale(LocalizationStore.locale))) }
        if let maximum = p.maximumAge { row("maximum_age", maximum.formatted(.number.locale(LocalizationStore.locale))) }
        if p.isAllDay == true { Text(ModerationAuditCopy.text("all_day")).font(.subheadline) }
        if p.cancellationState == "cancelled" {
            InlineMessageCard(style: .info, message: p.cancellationReason?.isEmpty == false ? p.cancellationReason! : ModerationAuditCopy.text("cancelled"))
        }
        if let occurrences = p.occurrences, !occurrences.isEmpty {
            Text(ContentPublishingStrings.multipleDates).font(.subheadline.weight(.semibold))
            ForEach(occurrences) { occurrence in
                VStack(alignment: .leading, spacing: 4) {
                    if let start = occurrence.startDate {
                        Text(LocalizationStore.dateString(from: Date(timeIntervalSince1970: start / 1000), timeStyle: occurrence.isAllDay ? .none : .short))
                    }
                    if let end = occurrence.endDate {
                        Text(LocalizationStore.dateString(from: Date(timeIntervalSince1970: end / 1000), timeStyle: occurrence.isAllDay ? .none : .short))
                    }
                    if occurrence.status == "cancelled" { Text(ModerationAuditCopy.text("cancelled")).foregroundStyle(AppTheme.accentDestructiveForeground) }
                }.font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func row(_ key: String, _ value: String?) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(ModerationAuditCopy.text(key)).font(.caption).foregroundStyle(AppTheme.textSecondary)
                Text(value).font(.subheadline).foregroundStyle(AppTheme.textPrimary).textSelection(.enabled)
            }.fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder private func webRow(_ key: String, _ value: String?, title: String? = nil) -> some View {
        if let value, !value.isEmpty {
            if let url = URL(string: value), url.scheme?.lowercased() == "https", url.host?.isEmpty == false {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ModerationAuditCopy.text(key)).font(.caption).foregroundStyle(AppTheme.textSecondary)
                    Link(title?.isEmpty == false ? title! : value, destination: url)
                        .font(.subheadline).foregroundStyle(AppTheme.accentPrimaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                    if title?.isEmpty == false { Text(value).font(.caption).foregroundStyle(AppTheme.textSecondary).textSelection(.enabled) }
                }
            } else { row(key, value) }
        }
    }
    private func category(_ raw: String) -> String {
        item.contentType == "news" ? (NewsCategory(rawValue: raw)?.title ?? raw) : (EventCategory(rawValue: raw)?.title ?? raw)
    }
    private func scope(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw == "austria" { return AppStrings.Home.regionAllAustria }
        return ModerationAuditCopy.text(raw == "city" ? "scope_city" : "scope_region")
    }
    private func price(_ p: ContentReviewPricing) -> String {
        let amount: (Double) -> String = { $0.formatted(.currency(code: p.currencyCode).locale(LocalizationStore.locale)) }
        switch EventPriceKind(rawValue: p.kind) ?? .unspecified {
        case .unspecified: return ContentPublishingStrings.priceUnspecified
        case .free: return ContentPublishingStrings.priceFree
        case .exact: return p.amount.map(amount) ?? ContentPublishingStrings.priceUnspecified
        case .startingFrom: return p.amount.map { "\(ContentPublishingStrings.priceFrom) \(amount($0))" } ?? ContentPublishingStrings.priceUnspecified
        case .range:
            guard let minimum = p.amount, let maximum = p.maximumAmount else { return ContentPublishingStrings.priceUnspecified }
            return "\(amount(minimum))–\(amount(maximum))"
        }
    }
}
