import SwiftUI

struct GuideMaterialEditorSettingsSection: View {
    @Binding var reviewInterval: ReviewInterval
    @Binding var regionScope: RegionScope
    @Binding var federalState: AustrianFederalState?
    let reviewIntervalTitle: (ReviewInterval) -> String

    private var federalStateOptions: [AustrianFederalState] {
        [
            .burgenland,
            .kaernten,
            .niederoesterreich,
            .oberoesterreich,
            .salzburg,
            .steiermark,
            .tirol,
            .vorarlberg,
            .wien
        ]
    }

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                SectionHeaderBlock(
                    title: GuideAuthoringPresentation.localized(
                        uk: "Додаткові налаштування",
                        de: "Zusätzliche Einstellungen",
                        en: "Additional settings"
                    ),
                    subtitle: GuideAuthoringPresentation.localized(
                        uk: "Налаштуйте нагадування для перевірки та регіональність матеріалу.",
                        de: "Legen Sie Erinnerung und regionale Gültigkeit für diesen Artikel fest.",
                        en: "Set review reminders and region coverage for this material."
                    )
                )

                AppEditorField(title: GuideAuthoringPresentation.reviewIntervalExplainTitle) {
                    Picker(GuideAuthoringPresentation.reviewIntervalExplainTitle, selection: $reviewInterval) {
                        ForEach(ReviewInterval.allCases) { interval in
                            Text(reviewIntervalTitle(interval)).tag(interval)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Text(GuideAuthoringPresentation.reviewIntervalExplainSubtitle)
                    .font(AppTheme.metadataFont)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                SectionHeaderBlock(
                    title: GuideAuthoringPresentation.regionTitle,
                    subtitle: GuideAuthoringPresentation.regionSubtitleMaterial
                )

                Picker(GuideAuthoringPresentation.regionTitle, selection: $regionScope) {
                    Text(GuideAuthoringPresentation.allAustria).tag(RegionScope.austria)
                    Text(GuideAuthoringPresentation.oneFederalState).tag(RegionScope.federalState)
                }
                .pickerStyle(.segmented)

                if regionScope == .federalState {
                    AppEditorField(title: GuideAuthoringPresentation.federalStateLabel) {
                        Picker(GuideAuthoringPresentation.federalStateLabel, selection: $federalState) {
                            Text(GuideAuthoringPresentation.selectFederalState).tag(AustrianFederalState?.none)
                            ForEach(federalStateOptions, id: \.self) { federalState in
                                Text(AppStrings.FederalStates.title(for: federalState))
                                    .tag(Optional(federalState))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
        }
    }
}
