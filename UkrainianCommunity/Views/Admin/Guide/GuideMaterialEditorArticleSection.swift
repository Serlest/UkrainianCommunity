import SwiftUI

struct GuideMaterialEditorArticleSection: View {
    let nodePathDescription: String
    @Binding var title: String
    @Binding var summary: String
    @Binding var articleBody: String

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                placementContext

                AppEditorField(title: GuideAuthoringPresentation.titleLabel) {
                    TextField(GuideAuthoringPresentation.titleLabel, text: $title, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                        .appEditorInputStyle()
                }

                AppEditorField(title: GuideAuthoringPresentation.shortDescriptionLabel) {
                    TextField(GuideAuthoringPresentation.shortDescriptionLabel, text: $summary, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                        .frame(minHeight: 100, alignment: .topLeading)
                        .appEditorInputStyle(minHeight: 100)
                }

                SectionHeaderBlock(
                    title: GuideAuthoringPresentation.descriptionSectionTitle,
                    subtitle: GuideAuthoringPresentation.descriptionSectionSubtitle
                )

                AppEditorField(title: GuideAuthoringPresentation.bodyLabel) {
                    TextEditor(text: normalizedArticleBody)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 160)
                        .padding(8)
                        .background(AppTheme.surfaceGlass, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                }
            }
        }
    }

    private var placementContext: some View {
        VStack(alignment: .leading, spacing: 6) {
            contextRow(
                label: GuideAuthoringPresentation.placementHintLabel,
                value: nodePathDescription
            )
        }
    }

    private func contextRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppTheme.metadataFont)
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(AppTheme.secondaryBodyFont)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var normalizedArticleBody: Binding<String> {
        Binding(
            get: { articleBody },
            set: { articleBody = GuideEditorTextNormalization.normalizedPastedText($0, previousValue: articleBody) }
        )
    }
}

enum GuideEditorTextNormalization {
    static func normalizedPastedText(_ value: String, previousValue: String) -> String {
        guard previousValue.isEmpty else { return value }

        let leadingSpaces = value.prefix { character in
            character == " " || character == "\t"
        }.count
        guard leadingSpaces >= 2 else { return value }

        return String(value.dropFirst(leadingSpaces))
    }
}
