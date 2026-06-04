import SwiftUI

struct GuideMaterialEditorKnowledgeSections: View {
    @Binding var steps: [String]
    @Binding var checklistItems: [String]
    @Binding var contacts: [GuideContactReference]
    @Binding var importantInformation: String

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                SectionHeaderBlock(
                    title: GuideAuthoringPresentation.knowledgeSectionsTitle,
                    subtitle: GuideAuthoringPresentation.knowledgeSectionsSubtitle
                )

                GuideStringListEditorSection(
                    title: GuideAuthoringPresentation.stepsSectionTitle,
                    placeholder: GuideAuthoringPresentation.stepPlaceholder,
                    items: $steps
                )

                GuideStringListEditorSection(
                    title: GuideAuthoringPresentation.checklistSectionTitle,
                    placeholder: GuideAuthoringPresentation.checklistPlaceholder,
                    items: $checklistItems
                )

                GuideContactsEditorSection(contacts: $contacts)

                AppEditorField(title: GuideAuthoringPresentation.importantInformationSectionTitle) {
                    TextEditor(text: $importantInformation)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140)
                        .padding(8)
                        .background(AppTheme.surfaceGlass, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                }

                Text(GuideAuthoringPresentation.importantInformationPlaceholder)
                    .font(AppTheme.metadataFont)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct GuideStringListEditorSection: View {
    let title: String
    let placeholder: String
    @Binding var items: [String]

    var body: some View {
        AppEditorField(title: title) {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                if items.isEmpty {
                    Text(GuideAuthoringPresentation.emptyListHint)
                        .font(AppTheme.metadataFont)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 10) {
                        TextField(placeholder, text: binding(for: index), axis: .vertical)
                            .textInputAutocapitalization(.sentences)
                            .appEditorInputStyle()

                        Button(role: .destructive) {
                            deleteItem(at: index)
                        } label: {
                            Image(systemName: "trash")
                                .font(AppTheme.buttonLabelFont)
                        }
                        .buttonStyle(.borderless)
                        .padding(.top, 10)
                    }
                }

                Button {
                    items.append("")
                } label: {
                    Label(GuideAuthoringPresentation.addListItem, systemImage: "plus.circle")
                        .font(AppTheme.buttonLabelFont)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { items.indices.contains(index) ? items[index] : "" },
            set: { newValue in
                guard items.indices.contains(index) else { return }
                items[index] = newValue
            }
        )
    }

    private func deleteItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
    }
}

private struct GuideContactsEditorSection: View {
    @Binding var contacts: [GuideContactReference]

    var body: some View {
        AppEditorField(title: GuideAuthoringPresentation.contactsSectionTitle) {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                if contacts.isEmpty {
                    Text(GuideAuthoringPresentation.emptyListHint)
                        .font(AppTheme.metadataFont)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                ForEach(contacts.indices, id: \.self) { index in
                    GuideContactEditorCard(
                        contact: binding(for: index),
                        onDelete: { deleteContact(at: index) }
                    )
                }

                Button {
                    contacts.append(.init(id: UUID().uuidString, name: ""))
                } label: {
                    Label(GuideAuthoringPresentation.addContact, systemImage: "plus.circle")
                        .font(AppTheme.buttonLabelFont)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func binding(for index: Int) -> Binding<GuideContactReference> {
        Binding(
            get: { contacts.indices.contains(index) ? contacts[index] : .init(id: UUID().uuidString, name: "") },
            set: { newValue in
                guard contacts.indices.contains(index) else { return }
                contacts[index] = newValue
            }
        )
    }

    private func deleteContact(at index: Int) {
        guard contacts.indices.contains(index) else { return }
        contacts.remove(at: index)
    }
}

private struct GuideContactEditorCard: View {
    @Binding var contact: GuideContactReference
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(GuideAuthoringPresentation.contactsSectionTitle)
                    .font(AppTheme.buttonLabelFont)
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer(minLength: 0)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(AppTheme.buttonLabelFont)
                }
                .buttonStyle(.borderless)
            }

            editorTextField(GuideAuthoringPresentation.contactNameLabel, text: nameBinding, capitalization: .words)
            editorTextField(GuideAuthoringPresentation.contactDescriptionLabel, text: descriptionBinding)
            editorTextField(GuideAuthoringPresentation.contactPhoneLabel, text: phoneBinding)
            editorTextField(GuideAuthoringPresentation.contactEmailLabel, text: emailBinding, capitalization: .never, autocorrection: true)
            editorTextField(GuideAuthoringPresentation.contactWebsiteLabel, text: websiteBinding, capitalization: .never, autocorrection: true)
        }
        .padding(14)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { contact.name },
            set: { contact = GuideContactReference(id: contact.id, name: $0, description: contact.description, phone: contact.phone, email: contact.email, website: contact.website) }
        )
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { contact.description ?? "" },
            set: { contact = GuideContactReference(id: contact.id, name: contact.name, description: $0.nilIfBlank, phone: contact.phone, email: contact.email, website: contact.website) }
        )
    }

    private var phoneBinding: Binding<String> {
        Binding(
            get: { contact.phone ?? "" },
            set: { contact = GuideContactReference(id: contact.id, name: contact.name, description: contact.description, phone: $0.nilIfBlank, email: contact.email, website: contact.website) }
        )
    }

    private var emailBinding: Binding<String> {
        Binding(
            get: { contact.email ?? "" },
            set: { contact = GuideContactReference(id: contact.id, name: contact.name, description: contact.description, phone: contact.phone, email: $0.nilIfBlank, website: contact.website) }
        )
    }

    private var websiteBinding: Binding<String> {
        Binding(
            get: { contact.website ?? "" },
            set: { contact = GuideContactReference(id: contact.id, name: contact.name, description: contact.description, phone: contact.phone, email: contact.email, website: $0.nilIfBlank) }
        )
    }

    private func editorTextField(
        _ title: String,
        text: Binding<String>,
        capitalization: TextInputAutocapitalization = .sentences,
        autocorrection: Bool = false
    ) -> some View {
        TextField(title, text: text, axis: .vertical)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled(autocorrection)
            .appEditorInputStyle()
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
