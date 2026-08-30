import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct PublicFeedPaginationTests {
    @Test func regionalQueryFiltersBeforeApplyingThePageLimit() async throws {
        let repository = MockNewsRepository(seededNews:
            makePosts(count: 20, state: .wien, newestOffset: 0)
            + [makePost(id: "national", state: nil, scope: .austria, publishedOffset: 20)]
            + makePosts(count: 5, state: .salzburg, newestOffset: 21)
        )

        let firstPage = try await repository.fetchNewsPage(
            limit: 3,
            after: nil,
            federalState: .salzburg
        )

        #expect(firstPage.items.map(\.id) == ["national", "salzburg-0", "salzburg-1"])
        #expect(firstPage.items.allSatisfy {
            $0.regionScope == .austria || $0.federalState == .salzburg
        })
        #expect(firstPage.hasMore)
    }

    @Test func explicitPaginationLoadsFifteenItemsAtATime() async {
        let repository = MockNewsRepository(seededNews:
            makePosts(count: 35, state: .salzburg, newestOffset: 0)
        )
        let viewModel = NewsViewModel(repository: repository)

        await viewModel.loadIfNeeded(federalState: .salzburg, initialLimit: 15)
        #expect(viewModel.posts.count == 15)
        #expect(viewModel.hasMorePages)

        await viewModel.loadNextPage(pageSize: 15)
        #expect(viewModel.posts.count == 30)
        #expect(viewModel.hasMorePages)

        await viewModel.loadNextPage(pageSize: 15)
        #expect(viewModel.posts.count == 35)
        #expect(!viewModel.hasMorePages)
    }

    @Test func changingFederalStateReplacesThePreviousRegionalFeed() async {
        let repository = MockNewsRepository(seededNews:
            makePosts(count: 20, state: .salzburg, newestOffset: 0)
            + makePosts(count: 20, state: .wien, newestOffset: 20)
        )
        let viewModel = NewsViewModel(repository: repository)

        await viewModel.loadIfNeeded(federalState: .salzburg, initialLimit: 15)
        #expect(viewModel.posts.count == 15)
        #expect(viewModel.posts.allSatisfy { $0.federalState == .salzburg })

        await viewModel.loadIfNeeded(federalState: .wien, initialLimit: 15)
        #expect(viewModel.posts.count == 15)
        #expect(viewModel.posts.allSatisfy { $0.federalState == .wien })
    }

    private func makePosts(
        count: Int,
        state: AustrianFederalState,
        newestOffset: Int
    ) -> [NewsPost] {
        (0..<count).map { index in
            makePost(
                id: "\(state.rawValue)-\(index)",
                state: state,
                scope: .federalState,
                publishedOffset: newestOffset + index
            )
        }
    }

    private func makePost(
        id: String,
        state: AustrianFederalState?,
        scope: RegionScope,
        publishedOffset: Int
    ) -> NewsPost {
        let date = Date(timeIntervalSince1970: 2_000_000_000 - Double(publishedOffset * 60))
        return NewsPost(
            id: id,
            title: id,
            subtitle: "Subtitle",
            regionScope: scope,
            federalState: state,
            body: "Body",
            authorName: "UAC",
            publishedAt: date,
            createdAt: date,
            updatedAt: date,
            comments: [],
            moderationStatus: .approved,
            likeCount: 0,
            likeState: .notLiked
        )
    }
}
