import SwiftUI

struct GuideTreeManagementView: View {
    @StateObject private var viewModel: GuideTreeManagementViewModel
    private let writeRepository: GuideWriteRepositoryProtocol

    init(
        repository: GuideRepositoryProtocol = FirestoreGuideRepository(),
        writeRepository: GuideWriteRepositoryProtocol = FirestoreGuideWriteRepository()
    ) {
        _viewModel = StateObject(wrappedValue: GuideTreeManagementViewModel(repository: repository))
        self.writeRepository = writeRepository
    }

    var body: some View {
        AdminScreenShell(
            title: GuideAuthoringPresentation.treeManagementTitle,
            subtitle: GuideAuthoringPresentation.treeManagementSubtitle
        ) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                SectionHeaderBlock(
                    title: GuideAuthoringPresentation.categoriesTitle,
                    subtitle: GuideAuthoringPresentation.categoriesSubtitle
                )

                ForEach(viewModel.categories) { category in
                    NavigationLink {
                        GuideTreeCategoryManagementView(
                            category: category,
                            viewModel: viewModel.makeReaderViewModel(),
                            writeRepository: writeRepository
                        )
                    } label: {
                        GuideTreeCategoryCard(category: category)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        GuideTreeManagementView(repository: MockGuideRepository())
    }
}
