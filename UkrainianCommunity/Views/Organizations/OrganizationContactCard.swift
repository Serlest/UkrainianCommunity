import MapKit
import SwiftUI

struct OrganizationContactCard: View {
    let organization: Organization
    let allowsEditing: Bool
    let showsManagementActions: Bool
    var usesPublicDetailStyle = false
    let onEdit: (() -> Void)?

    private var contactItems: [OrganizationContactItem] {
        var items: [OrganizationContactItem] = []

        if let websiteURL = organizationWebsiteURL(for: organization) {
            items.append(
                OrganizationContactItem(
                    title: AppStrings.Organizations.fieldWebsite,
                    value: cleanURLDisplayText(websiteURL),
                    systemImage: "globe",
                    destination: websiteURL
                )
            )
        }
        if let telegramURL = organizationTelegramURL(for: organization) {
            items.append(
                OrganizationContactItem(
                    title: AppStrings.Organizations.fieldTelegram,
                    value: cleanURLDisplayText(telegramURL),
                    systemImage: "paperplane",
                    destination: telegramURL
                )
            )
        }
        if let instagramURL = organizationSocialURL(for: organization, matching: "instagram") {
            items.append(
                OrganizationContactItem(
                    title: AppStrings.Organizations.fieldInstagram,
                    value: cleanURLDisplayText(instagramURL),
                    systemImage: "camera",
                    destination: instagramURL
                )
            )
        }
        if let facebookURL = organizationSocialURL(for: organization, matching: "facebook") {
            items.append(
                OrganizationContactItem(
                    title: AppStrings.Organizations.fieldFacebook,
                    value: cleanURLDisplayText(facebookURL),
                    systemImage: "person.2",
                    destination: facebookURL
                )
            )
        }
        if let whatsappURL = organizationSocialURL(for: organization, matching: "whatsapp") {
            items.append(
                OrganizationContactItem(
                    title: AppStrings.Organizations.fieldWhatsApp,
                    value: cleanURLDisplayText(whatsappURL),
                    systemImage: "phone.bubble",
                    destination: whatsappURL
                )
            )
        }
        if let youtubeURL = organizationSocialURL(for: organization, matching: "youtube") {
            items.append(
                OrganizationContactItem(
                    title: AppStrings.Organizations.fieldYouTube,
                    value: cleanURLDisplayText(youtubeURL),
                    systemImage: "play.rectangle",
                    destination: youtubeURL
                )
            )
        }
        if let linkedinURL = organizationSocialURL(for: organization, matching: "linkedin") {
            items.append(
                OrganizationContactItem(
                    title: AppStrings.Organizations.fieldLinkedIn,
                    value: cleanURLDisplayText(linkedinURL),
                    systemImage: "briefcase",
                    destination: linkedinURL
                )
            )
        }
        if let contactEmail = organizationContactText(for: organization),
           let destination = emailURL(for: contactEmail) {
            items.append(
                OrganizationContactItem(
                    title: AppStrings.Organizations.fieldEmail,
                    value: contactEmail,
                    systemImage: "envelope",
                    destination: destination
                )
            )
        }
        if let phone = organization.phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty,
           let destination = phoneURL(for: phone) {
            items.append(
                OrganizationContactItem(
                    title: AppStrings.Organizations.fieldPhone,
                    value: phone,
                    systemImage: "phone",
                    destination: destination
                )
            )
        }
        if let address = organizationAddressText(for: organization),
           let destination = organizationMapURL(for: organization) {
            items.append(
                OrganizationContactItem(
                    title: AppStrings.Organizations.fieldLocation,
                    value: address,
                    systemImage: "mappin.and.ellipse",
                    destination: destination,
                    isAddress: true
                )
            )
        }

        return items
    }

    private var contactPerson: String? {
        let value = organization.contactPerson?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private var websiteURL: URL? {
        organizationWebsiteURL(for: organization)
    }

    private var telegramURL: URL? {
        organizationTelegramURL(for: organization)
    }

    var body: some View {
        Group {
            if usesPublicDetailStyle {
                DetailCard {
                    contactContent
                }
            } else {
                AppEditorSectionCard {
                    contactContent
                }
            }
        }
    }

    private var contactContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    contactSectionTitle
                    Text(AppStrings.Organizations.contactsSubtitle)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer(minLength: AppTheme.eventsMetadataSpacing)

                if allowsEditing, let onEdit {
                    Button(action: onEdit) {
                        Label(AppStrings.Organizations.contactsEdit, systemImage: "square.and.pencil")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(AppStrings.Organizations.contactsEdit)
                }
            }

            if contactItems.isEmpty, contactPerson == nil {
                contactEmptyState
            } else {
                if let contactPerson {
                    contactPersonView(contactPerson)
                }

                VStack(spacing: 0) {
                    ForEach(contactItems) { item in
                        OrganizationContactRow(item: item, organization: organization)
                        if item.id != contactItems.last?.id {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
                .background(AppTheme.surfaceControl.opacity(0.24), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AppTheme.borderSubtle.opacity(0.75))
                )

                if showsManagementActions {
                    contactQuickActions
                }
            }
        }
    }

    private var contactSectionTitle: some View {
        Text(AppStrings.Organizations.tabContacts)
            .font(usesPublicDetailStyle ? AppTheme.sectionTitleFont : AppTheme.cardTitleFont)
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var contactEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(AppStrings.Organizations.contactsEmptyTitle, systemImage: "person.crop.circle.badge")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(AppStrings.Organizations.contactsEmptyMessage)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)

            if allowsEditing, let onEdit {
                Button(action: onEdit) {
                    Label(AppStrings.Organizations.contactsAdd, systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(AppTheme.accentPrimary)
                .padding(.top, 4)
                .accessibilityLabel(AppStrings.Organizations.contactsAdd)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func contactPersonView(_ contactPerson: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 28, height: 28)
                .background(AppTheme.accentPrimary.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(AppStrings.Organizations.fieldContactPersonDisplay)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                Text(contactPerson)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceControl.opacity(0.24), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle.opacity(0.75))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(AppStrings.Organizations.fieldContactPersonDisplay): \(contactPerson)")
    }

    @ViewBuilder
    private var contactQuickActions: some View {
        HStack(spacing: 8) {
            if allowsEditing, let onEdit {
                Button(action: onEdit) {
                    Label(AppStrings.Organizations.contactsEdit, systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let websiteURL {
                Link(destination: websiteURL) {
                    Label(AppStrings.Organizations.contactsOpenWebsite, systemImage: "safari")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(AppStrings.Organizations.contactsOpenWebsite)
            }

            if let telegramURL {
                Link(destination: telegramURL) {
                    Label(AppStrings.Organizations.contactsOpenTelegram, systemImage: "paperplane")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(AppStrings.Organizations.contactsOpenTelegram)
            }
        }
        .font(.caption.weight(.semibold))
    }
}

private struct OrganizationContactItem: Identifiable {
    let title: String
    let value: String
    let systemImage: String
    let destination: URL
    var isAddress = false

    var id: String {
        "\(title)-\(destination.absoluteString)"
    }
}

private struct OrganizationContactRow: View {
    let item: OrganizationContactItem
    let organization: Organization

    var body: some View {
        Link(destination: item.destination) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: item.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                        .frame(width: 28, height: 28)
                        .background(AppTheme.accentPrimary.opacity(0.10), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)

                        Text(item.value)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(item.isAddress ? 2 : 1)
                            .truncationMode(item.isAddress ? .tail : .middle)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)

                if item.isAddress, organization.latitude != nil, organization.longitude != nil {
                    OrganizationContactMapPreview(organization: organization)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title): \(item.value)")
    }
}

private struct OrganizationContactMapPreview: View {
    let organization: Organization

    var body: some View {
        if let latitude = organization.latitude, let longitude = organization.longitude {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            )
            Map(initialPosition: .region(region)) {
                Marker(organization.name, coordinate: coordinate)
            }
            .allowsHitTesting(false)
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
        }
    }
}
