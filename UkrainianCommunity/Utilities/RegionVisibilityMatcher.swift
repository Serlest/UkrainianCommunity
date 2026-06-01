import Foundation

enum RegionVisibilityMatcher {
    static func isVisible(
        regionScope: RegionScope?,
        federalState: AustrianFederalState?,
        selectedFederalState: AustrianFederalState?
    ) -> Bool {
        guard let selectedFederalState else { return true }

        switch regionScope {
        case .austria:
            return true
        case .federalState, .city:
            return federalState == selectedFederalState
        case nil:
            guard let federalState else { return true }
            return federalState == selectedFederalState
        }
    }
}
