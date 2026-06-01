import Foundation

func organizationActivityDateText(for item: OrganizationActivityItem) -> String {
    LocalizationStore.dateString(from: item.publishedAt, dateStyle: .medium, timeStyle: .short)
}

func organizationActivityEventText(for item: OrganizationActivityItem) -> String? {
    guard let eventStartDate = item.eventStartDate else { return nil }
    return LocalizationStore.dateString(from: eventStartDate, dateStyle: .medium, timeStyle: .short)
}

func organizationActivityLocationText(for item: OrganizationActivityItem) -> String? {
    if let city = item.city, !city.isEmpty {
        if let venue = item.eventVenue, !venue.isEmpty {
            return "\(city) • \(venue)"
        }
        return city
    }
    return nil
}

func organizationContactText(for organization: Organization) -> String? {
    let contactEmail = (organization.email ?? organization.contactEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !contactEmail.isEmpty else { return nil }
    return contactEmail
}

func organizationWebsiteText(for organization: Organization) -> String? {
    guard let website = organization.website?.trimmingCharacters(in: .whitespacesAndNewlines), !website.isEmpty else { return nil }
    return website
}

func organizationWebsiteDisplayText(for organization: Organization) -> String? {
    guard let website = organizationWebsiteText(for: organization) else { return nil }
    let normalized = website.hasPrefix("http://") || website.hasPrefix("https://") ? website : "https://\(website)"
    guard let url = URL(string: normalized), let host = url.host, !host.isEmpty else {
        return website
    }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
}

func organizationWebsiteURL(for organization: Organization) -> URL? {
    guard let website = organizationWebsiteText(for: organization) else { return nil }
    return normalizedOrganizationURL(from: website)
}

func normalizedOrganizationURL(from value: String?) -> URL? {
    guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else { return nil }
    let normalized = rawValue.hasPrefix("http://") || rawValue.hasPrefix("https://") ? rawValue : "https://\(rawValue)"
    guard let url = URL(string: normalized), url.host?.isEmpty == false else { return nil }
    return url
}

func cleanURLDisplayText(_ url: URL) -> String {
    guard let host = url.host, !host.isEmpty else {
        return url.absoluteString
    }

    let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    let path = url.path == "/" ? "" : url.path
    return "\(cleanHost)\(path)"
}

func organizationTelegramURL(for organization: Organization) -> URL? {
    if let explicitURL = normalizedTelegramContactURL(from: organization.telegramURL) {
        return explicitURL
    }

    if let telegramLink = organization.socialLinks.first(where: { key, value in
        key.localizedCaseInsensitiveContains("telegram")
            || value.localizedCaseInsensitiveContains("t.me")
            || value.localizedCaseInsensitiveContains("telegram.me")
    })?.value {
        return normalizedTelegramContactURL(from: telegramLink)
    }

    return nil
}

func normalizedTelegramContactURL(from value: String?) -> URL? {
    guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else { return nil }

    let lowercaseValue = rawValue.lowercased()
    if rawValue.hasPrefix("@") {
        return URL(string: "https://t.me/\(rawValue.dropFirst())")
    }
    if lowercaseValue.hasPrefix("https://t.me/") || lowercaseValue.hasPrefix("http://t.me/")
        || lowercaseValue.hasPrefix("https://telegram.me/") || lowercaseValue.hasPrefix("http://telegram.me/") {
        return URL(string: rawValue)
    }
    if lowercaseValue.hasPrefix("t.me/") || lowercaseValue.hasPrefix("telegram.me/") {
        return URL(string: "https://\(rawValue)")
    }
    if !rawValue.contains("://"), !rawValue.contains("."), !rawValue.contains("/") {
        return URL(string: "https://t.me/\(rawValue)")
    }
    return normalizedOrganizationURL(from: rawValue)
}

func organizationSocialURL(for organization: Organization, matching platform: String) -> URL? {
    if let firstClassURL = organizationFirstClassSocialURL(for: organization, matching: platform) {
        return firstClassURL
    }

    return organization.socialLinks.first { key, value in
        key.localizedCaseInsensitiveContains(platform)
            || value.localizedCaseInsensitiveContains(platform)
    }.flatMap { _, value in
        normalizedSocialContactURL(value, platform: platform)
    }
}

func organizationFirstClassSocialURL(for organization: Organization, matching platform: String) -> URL? {
    switch platform.lowercased() {
    case "facebook":
        return normalizedSocialContactURL(organization.facebookURL ?? "", platform: platform)
    case "instagram":
        return normalizedSocialContactURL(organization.instagramURL ?? "", platform: platform)
    case "whatsapp":
        return normalizedWhatsAppContactURL(from: organization.whatsappURL)
    case "youtube":
        return normalizedSocialContactURL(organization.youtubeURL ?? "", platform: platform)
    case "linkedin":
        return normalizedSocialContactURL(organization.linkedinURL ?? "", platform: platform)
    default:
        return nil
    }
}

func normalizedSocialContactURL(_ rawValue: String, platform: String) -> URL? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let lowercasePlatform = platform.lowercased()
    let lowercaseValue = trimmed.lowercased()
    if lowercasePlatform.contains("telegram") || lowercaseValue.contains("t.me/") {
        return normalizedTelegramContactURL(from: trimmed)
    }
    if lowercasePlatform.contains("instagram"), !lowercaseValue.contains("instagram.com") {
        let username = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        return normalizedOrganizationURL(from: "instagram.com/\(username)")
    }
    if lowercasePlatform.contains("facebook"), !lowercaseValue.contains("facebook.com") && !lowercaseValue.contains("fb.com") {
        return normalizedOrganizationURL(from: "facebook.com/\(trimmed)")
    }
    if lowercasePlatform.contains("youtube"), !lowercaseValue.contains("youtube.com") && !lowercaseValue.contains("youtu.be") {
        return normalizedOrganizationURL(from: "youtube.com/\(trimmed)")
    }
    if lowercasePlatform.contains("linkedin"), !lowercaseValue.contains("linkedin.com") {
        return normalizedOrganizationURL(from: "linkedin.com/\(trimmed)")
    }
    if lowercasePlatform.contains("whatsapp") {
        return normalizedWhatsAppContactURL(from: trimmed)
    }
    return normalizedOrganizationURL(from: trimmed)
}

func normalizedWhatsAppContactURL(from value: String?) -> URL? {
    guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else { return nil }
    let lowercaseValue = rawValue.lowercased()
    if lowercaseValue.hasPrefix("http://") || lowercaseValue.hasPrefix("https://") {
        return URL(string: rawValue)
    }
    if lowercaseValue.contains("wa.me/") || lowercaseValue.contains("whatsapp.com/") {
        return normalizedOrganizationURL(from: rawValue)
    }
    let digits = rawValue.filter(\.isNumber)
    guard !digits.isEmpty else { return nil }
    return URL(string: "https://wa.me/\(digits)")
}

func organizationAddressText(for organization: Organization) -> String? {
    let address = (organization.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let city = organization.city.trimmingCharacters(in: .whitespacesAndNewlines)

    if !address.isEmpty, !city.isEmpty, !address.localizedCaseInsensitiveContains(city) {
        return "\(address), \(city)"
    }
    if !address.isEmpty {
        return address
    }
    return nil
}

func organizationMapURL(for organization: Organization) -> URL? {
    if let latitude = organization.latitude, let longitude = organization.longitude {
        return URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(organization.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
    }

    let address = organizationAddressText(for: organization)
    let city = organization.city.trimmingCharacters(in: .whitespacesAndNewlines)
    let query = (address ?? city).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty,
          let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
        return nil
    }
    return URL(string: "https://maps.apple.com/?q=\(encodedQuery)")
}

func emailURL(for email: String) -> URL? {
    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
        return nil
    }
    return URL(string: "mailto:\(encoded)")
}

func phoneURL(for phone: String) -> URL? {
    let digits = phone.filter { $0.isNumber || $0 == "+" }
    guard !digits.isEmpty else { return nil }
    return URL(string: "tel:\(digits)")
}
