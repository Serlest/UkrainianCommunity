import SwiftUI

struct GuideSourceLinkEditorRow: View {
    let link: GuideSourceLink
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onChange: (GuideSourceLink) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
            VStack(alignment: .leading, spacing: 8) {
                TextField(
                    AppStrings.GuideEditor.linkTitlePlaceholder,
                    text: Binding(
                        get: { link.title },
                        set: { update(title: $0) }
                    )
                )
                .textInputAutocapitalization(.sentences)
                .textFieldStyle(.roundedBorder)

                TextField(
                    AppStrings.GuideEditor.linkURLPlaceholder,
                    text: Binding(
                        get: { link.url },
                        set: { update(url: $0) }
                    )
                )
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

                TextField(
                    AppStrings.GuideEditor.linkSourceNamePlaceholder,
                    text: Binding(
                        get: { link.sourceName ?? "" },
                        set: { update(sourceName: $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankForGuideSourceLinkEditor) }
                    )
                )
                .textInputAutocapitalization(.words)
                .textFieldStyle(.roundedBorder)

                Toggle(AppStrings.GuideEditor.linkIsOfficial, isOn: Binding(
                    get: { link.isOfficial },
                    set: { update(isOfficial: $0) }
                ))
                .font(.subheadline.weight(.medium))
            }

            VStack(spacing: 4) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveUp)
                .accessibilityLabel(AppStrings.GuideEditor.moveLinkUp)

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveDown)
                .accessibilityLabel(AppStrings.GuideEditor.moveLinkDown)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(AppStrings.GuideEditor.deleteLink)
            }
            .buttonStyle(.borderless)
        }
    }

    private func update(
        title: String? = nil,
        url: String? = nil,
        sourceName: String?? = nil,
        isOfficial: Bool? = nil
    ) {
        onChange(.init(
            id: link.id,
            title: title ?? link.title,
            url: url ?? link.url,
            sourceName: sourceName ?? link.sourceName,
            isOfficial: isOfficial ?? link.isOfficial
        ))
    }
}

private extension String {
    var nilIfBlankForGuideSourceLinkEditor: String? {
        isEmpty ? nil : self
    }
}
