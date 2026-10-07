import SwiftUI

struct DirectoryRegionalSectionsView: View {
    let categoryID: String
    let topicID: String
    @Binding var selectedFederalState: AustrianFederalState?
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
            Text(DirectoryText(ukrainian: "У вашій федеральній землі", german: "In Ihrem Bundesland").value(for: language))
                .font(.title3.bold())
                .foregroundStyle(AppTheme.textPrimary)
            AppRegionFilterMenu(selection: $selectedFederalState)
            if let selectedFederalState {
                ForEach(DirectoryRegionalContent.sections(categoryID: categoryID, topicID: topicID,
                                                           state: selectedFederalState)) { section in
                    DirectoryGuideSectionCard(section: section, language: language)
                }
            } else {
                Text(DirectoryText(ukrainian: "Оберіть землю, щоб побачити її офіційні служби та правила.",
                                   german: "Wählen Sie ein Bundesland für zuständige Stellen und Regeln.").value(for: language))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}
