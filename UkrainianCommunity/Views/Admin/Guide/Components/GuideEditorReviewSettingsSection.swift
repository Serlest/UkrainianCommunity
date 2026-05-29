import SwiftUI

struct GuideEditorReviewSettingsSection: View {
    @ObservedObject var viewModel: GuideEditorViewModel

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                AppEditorSectionTitle(title: AppStrings.GuideEditor.reviewSection)

                Picker(AppStrings.GuideEditor.reviewIntervalField, selection: $viewModel.draft.reviewInterval) {
                    ForEach(ReviewInterval.allCases) { interval in
                        Text(interval.guideEditorTitle).tag(interval)
                    }
                }
                .pickerStyle(.segmented)

                Stepper(value: $viewModel.draft.priority, in: 0...100) {
                    LabeledContent(AppStrings.GuideEditor.priorityField, value: "\(viewModel.draft.priority)")
                }

                Toggle(AppStrings.GuideEditor.isFeaturedField, isOn: $viewModel.draft.isFeatured)
                Toggle(AppStrings.GuideEditor.officialSourcesRequiredField, isOn: $viewModel.draft.officialSourcesRequired)
            }
        }
    }
}

private extension ReviewInterval {
    var guideEditorTitle: String {
        switch self {
        case .critical:
            AppStrings.GuideEditor.reviewIntervalCritical
        case .normal:
            AppStrings.GuideEditor.reviewIntervalNormal
        case .stable:
            AppStrings.GuideEditor.reviewIntervalStable
        }
    }
}
