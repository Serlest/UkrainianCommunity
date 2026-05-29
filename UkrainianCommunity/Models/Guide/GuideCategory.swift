import Foundation

enum GuideCategory: String, CaseIterable, Codable, Identifiable {
    case firstSteps
    case documents
    case anmeldung
    case work
    case finance
    case family
    case health
    case housing
    case transport
    case education
    case law
    case emergency
    case ukrainianCommunity
    case lifeInAustria
    case ams
    case medicine
    case children
    case business
    case contacts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstSteps:
            AppStrings.Guide.categoryFirstSteps
        case .documents:
            AppStrings.Guide.categoryDocuments
        case .anmeldung:
            AppStrings.Guide.categoryAnmeldung
        case .work:
            AppStrings.Guide.categoryWork
        case .finance:
            AppStrings.Guide.categoryFinance
        case .family:
            AppStrings.Guide.categoryFamily
        case .health:
            AppStrings.Guide.categoryHealth
        case .housing:
            AppStrings.Guide.categoryHousing
        case .transport:
            AppStrings.Guide.categoryTransport
        case .education:
            AppStrings.Guide.categoryEducation
        case .law:
            AppStrings.Guide.categoryLaw
        case .emergency:
            AppStrings.Guide.categoryEmergency
        case .ukrainianCommunity:
            AppStrings.Guide.categoryUkrainianCommunity
        case .lifeInAustria:
            AppStrings.Guide.categoryLifeInAustria
        case .ams:
            AppStrings.Guide.categoryAMS
        case .medicine:
            AppStrings.Guide.categoryMedicine
        case .children:
            AppStrings.Guide.categoryChildren
        case .business:
            AppStrings.Guide.categoryBusiness
        case .contacts:
            AppStrings.Guide.categoryContacts
        }
    }

    var systemImage: String {
        switch self {
        case .firstSteps:
            "figure.wave"
        case .documents:
            "doc.text"
        case .anmeldung:
            "building.columns"
        case .work:
            "briefcase"
        case .finance:
            "eurosign.circle"
        case .family:
            "figure.2.and.child.holdinghands"
        case .health:
            "heart.text.square"
        case .housing:
            "house"
        case .transport:
            "tram"
        case .education:
            "book"
        case .law:
            "scale.3d"
        case .emergency:
            "exclamationmark.triangle"
        case .ukrainianCommunity:
            "person.3"
        case .lifeInAustria:
            "leaf"
        case .ams:
            "person.text.rectangle"
        case .medicine:
            "cross.case"
        case .children:
            "figure.and.child.holdinghands"
        case .business:
            "building.2"
        case .contacts:
            "phone"
        }
    }
}
