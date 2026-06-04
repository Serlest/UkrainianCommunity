import SwiftUI

struct GuideMaterialSourcesView: View {
    let links: [GuideSourceLink]
    let legacyURL: String?
    let legacyTitle: String?

    var body: some View {
        if !visibleLinks.isEmpty {
            DetailCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(GuideAuthoringPresentation.sourcesTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    ForEach(visibleLinks) { link in
                        GuideMaterialSourceLinkRow(link: link)
                    }
                }
            }
        } else if let legacyLink {
            DetailCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(GuideAuthoringPresentation.sourcesTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    GuideMaterialSourceLinkRow(link: legacyLink)
                }
            }
        }
    }

    private var visibleLinks: [GuideSourceLink] {
        links.filter(\.isRenderable)
    }

    private var legacyLink: GuideSourceLink? {
        guard let legacyURL,
              let trimmedURL = legacyURL.trimmingCharacters(in: .whitespacesAndNewlines).nilIfNotEmpty
        else {
            return nil
        }

        let fallbackTitle: String
        if let legacyTitle = legacyTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !legacyTitle.isEmpty {
            fallbackTitle = legacyTitle
        } else if let url = FeaturedBannerURLNormalizer.normalizedExternalURL(from: trimmedURL),
                  let host = url.host,
                  !host.isEmpty {
            fallbackTitle = host
        } else {
            fallbackTitle = trimmedURL
        }

        return GuideSourceLink(id: "legacy-source", title: fallbackTitle, url: trimmedURL)
    }
}

private struct GuideMaterialSourceLinkRow: View {
    let link: GuideSourceLink

    var body: some View {
        if let destination = normalizedURL {
            Link(destination: destination) {
                rowContent(displayURL: destination.absoluteString, showsLinkIcon: true)
            }
            .buttonStyle(.plain)
        } else {
            rowContent(displayURL: trimmedURL, showsLinkIcon: false)
        }
    }

    private var normalizedURL: URL? {
        FeaturedBannerURLNormalizer.normalizedExternalURL(from: trimmedURL)
    }

    private var trimmedURL: String {
        link.url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private func rowContent(displayURL: String, showsLinkIcon: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(link.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !displayURL.isEmpty {
                    Text(displayURL)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            if showsLinkIcon {
                Image(systemName: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
            }
        }
    }
}

private extension String {
    var nilIfNotEmpty: String? {
        isEmpty ? nil : self
    }
}
