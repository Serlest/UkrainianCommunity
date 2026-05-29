import SwiftUI

struct GuideEditorClassificationSection: View {
    @ObservedObject var viewModel: GuideEditorViewModel

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                AppEditorSectionTitle(title: AppStrings.GuideEditor.classificationSection)

                Picker(AppStrings.GuideEditor.categoryField, selection: $viewModel.draft.category) {
                    Text(AppStrings.GuideEditor.categoryPlaceholder).tag(Optional<GuideCategory>.none)
                    ForEach(GuideCategory.allCases) { category in
                        Text(category.title).tag(Optional(category))
                    }
                }
                .pickerStyle(.menu)

                Picker(AppStrings.GuideEditor.contentTypeField, selection: $viewModel.draft.contentType) {
                    ForEach(GuideContentType.allCases) { contentType in
                        Text(contentType.guideEditorTitle).tag(contentType)
                    }
                }
                .pickerStyle(.segmented)

                Picker(AppStrings.GuideEditor.federalStateField, selection: $viewModel.draft.federalState) {
                    Text(AppStrings.GuideEditor.austriaWide).tag(Optional<AustrianFederalState>.none)
                    ForEach(AustrianFederalState.allCases) { state in
                        Text(AppStrings.FederalStates.title(for: state)).tag(Optional(state))
                    }
                }
                .pickerStyle(.menu)

                AppEditorField(title: AppStrings.GuideEditor.audienceField) {
                    TextField(AppStrings.GuideEditor.audiencePlaceholder, text: audienceText)
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.roundedBorder)

                    Text(AppStrings.GuideEditor.audienceHelp)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var audienceText: Binding<String> {
        Binding(
            get: { viewModel.draft.audience.joined(separator: ", ") },
            set: { newValue in
                viewModel.updateDraft { draft in
                    draft.audience = newValue
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                }
            }
        )
    }
}

private extension GuideContentType {
    var guideEditorTitle: String {
        switch self {
        case .guide:
            AppStrings.Guide.contentTypeGuide
        case .quickInfo:
            AppStrings.Guide.contentTypeQuickInfo
        case .checklist:
            AppStrings.Guide.contentTypeChecklist
        case .contact:
            AppStrings.Guide.contentTypeContact
        case .process:
            AppStrings.Guide.contentTypeProcess
        }
    }
}
