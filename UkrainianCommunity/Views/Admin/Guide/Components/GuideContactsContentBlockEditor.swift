import SwiftUI

struct GuideContactsContentBlockEditor: View {
    @Binding var block: GuideContentBlock

    var body: some View {
        if case .contacts(let value) = block {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                GuideContentBlockTitleField(title: value.title) { title in
                    block = .contacts(.init(id: value.id, title: title, contacts: value.contacts))
                }

                AppEditorField(title: AppStrings.GuideEditor.blockContactsField) {
                    if value.contacts.isEmpty {
                        Text(AppStrings.GuideEditor.blockContactsEmpty)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                            ForEach(value.contacts.indices, id: \.self) { index in
                                GuideContactEditorRow(
                                    contact: value.contacts[index],
                                    canMoveUp: index > 0,
                                    canMoveDown: index < value.contacts.count - 1,
                                    onChange: { updateContact(at: index, contact: $0, in: value) },
                                    onMoveUp: { moveContact(from: index, to: index - 1, in: value) },
                                    onMoveDown: { moveContact(from: index, to: index + 1, in: value) },
                                    onDelete: { deleteContact(at: index, in: value) }
                                )
                            }
                        }
                    }

                    Button {
                        appendContact(to: value)
                    } label: {
                        Label(AppStrings.GuideEditor.addContact, systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func appendContact(to value: GuideContentBlock.ContactsBlock) {
        var contacts = value.contacts
        contacts.append(.init(id: UUID().uuidString, name: ""))
        block = .contacts(.init(id: value.id, title: value.title, contacts: contacts))
    }

    private func updateContact(at index: Int, contact: GuideContactReference, in value: GuideContentBlock.ContactsBlock) {
        guard value.contacts.indices.contains(index) else { return }
        var contacts = value.contacts
        contacts[index] = contact
        block = .contacts(.init(id: value.id, title: value.title, contacts: contacts))
    }

    private func moveContact(from source: Int, to destination: Int, in value: GuideContentBlock.ContactsBlock) {
        guard value.contacts.indices.contains(source), value.contacts.indices.contains(destination) else { return }
        var contacts = value.contacts
        let contact = contacts.remove(at: source)
        contacts.insert(contact, at: destination)
        block = .contacts(.init(id: value.id, title: value.title, contacts: contacts))
    }

    private func deleteContact(at index: Int, in value: GuideContentBlock.ContactsBlock) {
        guard value.contacts.indices.contains(index) else { return }
        var contacts = value.contacts
        contacts.remove(at: index)
        block = .contacts(.init(id: value.id, title: value.title, contacts: contacts))
    }
}

private struct GuideContactEditorRow: View {
    let contact: GuideContactReference
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onChange: (GuideContactReference) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
            VStack(alignment: .leading, spacing: 8) {
                TextField(
                    AppStrings.GuideEditor.contactNamePlaceholder,
                    text: Binding(get: { contact.name }, set: { update(name: $0) })
                )
                .textInputAutocapitalization(.words)
                .textFieldStyle(.roundedBorder)

                TextField(
                    AppStrings.GuideEditor.contactDescriptionPlaceholder,
                    text: Binding(
                        get: { contact.description ?? "" },
                        set: { update(description: $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankForGuideContactEditor) }
                    )
                )
                .textInputAutocapitalization(.sentences)
                .textFieldStyle(.roundedBorder)

                TextField(
                    AppStrings.GuideEditor.contactPhonePlaceholder,
                    text: Binding(
                        get: { contact.phone ?? "" },
                        set: { update(phone: $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankForGuideContactEditor) }
                    )
                )
                .keyboardType(.phonePad)
                .textFieldStyle(.roundedBorder)

                TextField(
                    AppStrings.GuideEditor.contactEmailPlaceholder,
                    text: Binding(
                        get: { contact.email ?? "" },
                        set: { update(email: $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankForGuideContactEditor) }
                    )
                )
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

                TextField(
                    AppStrings.GuideEditor.contactWebsitePlaceholder,
                    text: Binding(
                        get: { contact.website ?? "" },
                        set: { update(website: $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankForGuideContactEditor) }
                    )
                )
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            }

            VStack(spacing: 4) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveUp)
                .accessibilityLabel(AppStrings.GuideEditor.moveContactUp)

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveDown)
                .accessibilityLabel(AppStrings.GuideEditor.moveContactDown)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(AppStrings.GuideEditor.deleteContact)
            }
            .buttonStyle(.borderless)
        }
    }

    private func update(
        name: String? = nil,
        description: String?? = nil,
        phone: String?? = nil,
        email: String?? = nil,
        website: String?? = nil
    ) {
        onChange(.init(
            id: contact.id,
            name: name ?? contact.name,
            description: description ?? contact.description,
            phone: phone ?? contact.phone,
            email: email ?? contact.email,
            website: website ?? contact.website
        ))
    }
}

private extension String {
    var nilIfBlankForGuideContactEditor: String? {
        isEmpty ? nil : self
    }
}
