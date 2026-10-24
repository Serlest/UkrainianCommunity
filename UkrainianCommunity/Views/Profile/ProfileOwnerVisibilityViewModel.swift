import Combine
import Foundation

enum OwnerVisibilityCountState: Equatable {
    case idle
    case loading
    case loaded(Int)
    case failed
}

@MainActor
final class OwnerProfileVisibilityViewModel: ObservableObject {
    @Published private(set) var unreadFeedbackCount: Int?
    @Published private(set) var pendingOrganizationRequestCount: Int?
    @Published private(set) var feedbackCountState: OwnerVisibilityCountState = .idle
    @Published private(set) var organizationRequestCountState: OwnerVisibilityCountState = .idle
    private let feedbackRepository: FeedbackRepository
    private let organizationRepository: OrganizationRepository
    private var generation = 0
    private var feedbackTask: Task<Void, Never>?
    private var organizationTask: Task<Void, Never>?
    private var feedbackLoaded = false
    private var organizationsLoaded = false

    init(feedbackRepository: FeedbackRepository, organizationRepository: OrganizationRepository) {
        self.feedbackRepository = feedbackRepository
        self.organizationRepository = organizationRepository
    }

    var hasCountLoadFailure: Bool { feedbackCountState == .failed || organizationRequestCountState == .failed }

    func loadIfNeeded(includeOrganizationRequests: Bool, includeFeedback: Bool) async {
        await refresh(includeOrganizationRequests: includeOrganizationRequests && !organizationsLoaded,
                      includeFeedback: includeFeedback && !feedbackLoaded)
    }

    func refresh(includeOrganizationRequests: Bool, includeFeedback: Bool) async {
        async let feedback: Void = refreshFeedback(if: includeFeedback)
        async let organizations: Void = refreshOrganizations(if: includeOrganizationRequests)
        _ = await (feedback, organizations)
    }

    func reset() {
        generation &+= 1
        feedbackTask?.cancel(); feedbackTask = nil
        organizationTask?.cancel(); organizationTask = nil
        unreadFeedbackCount = nil; pendingOrganizationRequestCount = nil
        feedbackLoaded = false; organizationsLoaded = false
        feedbackCountState = .idle; organizationRequestCountState = .idle
    }

    private func refreshFeedback(if enabled: Bool) async {
        guard enabled else { return }
        if let feedbackTask { await feedbackTask.value; return }
        let expected = generation
        feedbackCountState = .loading
        let task = Task { [self] in
            do {
                let count = try await RefreshRequest.run { [self] in try await feedbackRepository.fetchUnreadOwnerFeedbackCount() }
                guard generation == expected, !Task.isCancelled else { return }
                unreadFeedbackCount = count
                feedbackLoaded = true
                feedbackCountState = .loaded(count)
            } catch {
                guard generation == expected, !Task.isCancelled else { return }
                feedbackLoaded = false
                feedbackCountState = .failed
            }
        }
        feedbackTask = task
        await task.value
        if generation == expected { feedbackTask = nil }
    }

    func refreshOrganizationRequests() async { await refreshOrganizations(if: true) }

    private func refreshOrganizations(if enabled: Bool) async {
        guard enabled else { return }
        if let organizationTask { await organizationTask.value; return }
        let expected = generation
        organizationRequestCountState = .loading
        let task = Task { [self] in
            do {
                let count = try await RefreshRequest.run { [self] in try await organizationRepository.fetchPendingOrganizationCount() }
                guard generation == expected, !Task.isCancelled else { return }
                pendingOrganizationRequestCount = count
                organizationsLoaded = true
                organizationRequestCountState = .loaded(count)
            } catch {
                guard generation == expected, !Task.isCancelled else { return }
                organizationsLoaded = false
                organizationRequestCountState = .failed
            }
        }
        organizationTask = task
        await task.value
        if generation == expected { organizationTask = nil }
    }
}
