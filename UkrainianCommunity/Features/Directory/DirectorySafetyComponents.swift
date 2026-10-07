import SwiftUI

struct SafetyInfoCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        AppGlassCard {
            Label(title, systemImage: symbol).font(.headline)
            content
        }
    }
}

struct SafetyCallButton: View {
    let contact: SafetyContact
    let language: AppLanguage

    var body: some View {
        Link(destination: contact.phoneURL) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.title.value(for: language)).font(.subheadline.weight(.semibold))
                        Text(contact.detail.value(for: language)).font(.caption)
                    }
                    Spacer(minLength: 4)
                    if contact.number.count <= 4 {
                        Text(contact.number).font(.subheadline.weight(.bold)).monospacedDigit()
                    }
                }
                if contact.number.count > 4 {
                    Text(contact.number)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .foregroundStyle(AppTheme.accentPrimaryForeground)
            .padding(12)
            .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("directory.call.\(contact.number)")
    }
}

struct SafetySourcesView: View {
    let sources: [SafetySource]
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(DirectoryText(ukrainian: "Офіційні джерела", german: "Offizielle Quellen").value(for: language))
                .font(.headline)
            ForEach(sources) { source in
                Link(destination: source.url) {
                    Label(source.name, systemImage: "arrow.up.right.square")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text(DirectoryText(
                ukrainian: "Посилання та номери перевірено \(DirectorySafetyContent.reviewedOn).",
                german: "Links und Nummern geprüft am \(DirectorySafetyContent.reviewedOn)."
            ).value(for: language))
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}
