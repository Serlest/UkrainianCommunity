import Combine
import Foundation

@MainActor
final class GuideTreeManagementViewModel: ObservableObject {
    let categories: [GuideCategory]

    private let repository: GuideRepositoryProtocol

    init(repository: GuideRepositoryProtocol) {
        self.repository = repository
        self.categories = GuideCategoryPresentation.publicTopLevelCategories
    }

    func makeReaderViewModel() -> GuideReaderViewModel {
        GuideReaderViewModel(repository: repository)
    }
}
