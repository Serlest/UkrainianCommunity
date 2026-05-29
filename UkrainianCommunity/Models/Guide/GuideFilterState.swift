import Foundation

struct GuideFilterState: Equatable {
    var searchText: String = ""
    var selectedCategory: GuideCategory?
    var selectedContentType: GuideContentType?
    var selectedFederalState: AustrianFederalState?
    var selectedAudience: String?

    var hasActiveFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedCategory != nil
            || selectedContentType != nil
            || selectedFederalState != nil
            || selectedAudience != nil
    }
}
