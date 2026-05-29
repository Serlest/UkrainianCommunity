import SwiftUI

struct GuideContactBlockView: View {
    let block: GuideContentBlock.ContactsBlock

    private var contacts: [GuideContactReference] {
        block.contacts.filter { !$0.name.guideIsBlank }
    }

    var body: some View {
        if !contacts.isEmpty {
            DetailCard {
                GuideBlockTitleView(title: block.title)

                ForEach(contacts) { contact in
                    contactRow(contact)
                }
            }
        }
    }

    private func contactRow(_ contact: GuideContactReference) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(contact.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let description = contact.description, !description.guideIsBlank {
                Text(description)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                contactLink(title: contact.phone, systemImage: "phone", urlPrefix: "tel:")
                contactLink(title: contact.email, systemImage: "envelope", urlPrefix: "mailto:")
                websiteLink(contact.website)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func contactLink(title: String?, systemImage: String, urlPrefix: String) -> some View {
        if let title, !title.guideIsBlank {
            let compactValue = title.replacingOccurrences(of: " ", with: "")

            if let url = URL(string: "\(urlPrefix)\(compactValue)") {
                Link(destination: url) {
                    contactLabel(title: title, systemImage: systemImage)
                }
                .buttonStyle(.plain)
            } else {
                contactLabel(title: title, systemImage: systemImage)
            }
        }
    }

    @ViewBuilder
    private func websiteLink(_ value: String?) -> some View {
        if let value, !value.guideIsBlank {
            if let url = URL(string: value) {
                Link(destination: url) {
                    contactLabel(title: value, systemImage: "globe")
                }
                .buttonStyle(.plain)
            } else {
                contactLabel(title: value, systemImage: "globe")
            }
        }
    }

    private func contactLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.accentPrimary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
