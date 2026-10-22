import Combine

enum OwnerVisibilityCountState: Equatable {
    case idle
    case loading
    case loaded(Int)
    case failed
}

@MainActor
final class OwnerProfileVisibilityViewModel: ObservableObject {
    @Published private var ownerFeedbackItems: [FeedbackItem]?
    @Published private var pendingOrganizationRequests: Int?
    @Published private(set) var feedbackCountState: OwnerVisibilityCountState = .idle
    @Published private(set) var organizationRequestCountState: OwnerVisibilityCountState = .idle

    private let feedbackRepository: FeedbackRepository
    private let organizationRepository: OrganizationRepository
    private let listenerBag = RealtimeListenerBag()
    private var generation = 0
    private var hasLoadedFeedback = false
    private var hasLoadedOrganizationRequests = false

    init(
        feedbackRepository: FeedbackRepository,
        organizationRepository: OrganizationRepository
    ) {
        self.feedbackRepository = feedbackRepository
        self.organizationRepository = organizationRepository
    }

    var unreadFeedbackCount: Int? {
        ownerFeedbackItems?.filter(\.unreadForOwner).count
    }

    var pendingOrganizationRequestCount: Int? {
        pendingOrganizationRequests
    }

    var hasCountLoadFailure: Bool {
        feedbackCountState == .failed || organizationRequestCountState == .failed
    }

    func loadIfNeeded(includeOrganizationRequests: Bool, includeFeedback: Bool) async {
        let expected = generation
        startListening(includeOrganizationRequests: includeOrganizationRequests, includeFeedback: includeFeedback)

        if includeFeedback, !hasLoadedFeedback {
            await refreshFeedback()
        } else if !includeFeedback {
            resetFeedback()
        }

        guard generation == expected, !Task.isCancelled else { return }
        if includeOrganizationRequests, !hasLoadedOrganizationRequests {
            await refreshOrganizationRequests()
        } else if !includeOrganizationRequests {
            resetOrganizationRequests()
        }
    }

    func refresh(includeOrganizationRequests: Bool, includeFeedback: Bool) async {
        let expected = generation
        startListening(includeOrganizationRequests: includeOrganizationRequests, includeFeedback: includeFeedback)

        if includeFeedback {
            await refreshFeedback()
        } else {
            resetFeedback()
        }

        guard generation == expected, !Task.isCancelled else { return }
        if includeOrganizationRequests {
            await refreshOrganizationRequests()
        } else {
            resetOrganizationRequests()
        }
    }

    func reset() {
        generation &+= 1
        resetFeedback()
        resetOrganizationRequests()
    }

    private func refreshFeedback() async {
        let expected = generation
        feedbackCountState = .loading

        do {
            let items = try await RefreshRequest.run { [self] in try await feedbackRepository.fetchFeedback() }
            guard generation == expected, !Task.isCancelled else { return }
            ownerFeedbackItems = items
            hasLoadedFeedback = true
            feedbackCountState = .loaded(unreadFeedbackCount ?? 0)
        } catch {
            guard generation == expected, !Task.isCancelled else { return }
            hasLoadedFeedback = false
            if feedbackCountState == .loading {
                feedbackCountState = .failed
            }
        }
    }

    func refreshOrganizationRequests() async {
        let expected = generation
        organizationRequestCountState = .loading

        do {
            let items = try await RefreshRequest.run { [self] in try await organizationRepository.fetchPendingOrganizationCount() }
            guard generation == expected, !Task.isCancelled else { return }
            pendingOrganizationRequests = items
            hasLoadedOrganizationRequests = true
            organizationRequestCountState = .loaded(pendingOrganizationRequestCount ?? 0)
        } catch {
            guard generation == expected, !Task.isCancelled else { return }
            hasLoadedOrganizationRequests = false
            if organizationRequestCountState == .loading {
                organizationRequestCountState = .failed
            }
        }
    }

    private func resetFeedback() {
        ownerFeedbackItems = nil
        feedbackCountState = .idle
        listenerBag.remove("ownerFeedback")
        hasLoadedFeedback = false
    }

    private func resetOrganizationRequests() {
        pendingOrganizationRequests = nil
        organizationRequestCountState = .idle
        listenerBag.remove("pendingOrganizationRequests")
        hasLoadedOrganizationRequests = false
    }

    private func startListening(includeOrganizationRequests: Bool, includeFeedback: Bool) {
        let expected = generation
        if includeFeedback,
           !listenerBag.contains("ownerFeedback"),
           let realtimeRepository = feedbackRepository as? FeedbackRealtimeRepository {
            listenerBag.set(realtimeRepository.listenOwnerFeedbackInbox { [weak self] items in
                guard self?.generation == expected else { return }
                self?.ownerFeedbackItems = items
                self?.hasLoadedFeedback = true
                self?.feedbackCountState = .loaded(items.filter(\.unreadForOwner).count)
            } onError: { [weak self] _ in
                guard self?.generation == expected else { return }
                self?.hasLoadedFeedback = false
                self?.feedbackCountState = .failed
                self?.listenerBag.remove("ownerFeedback")
            }, for: "ownerFeedback")
        } else if !includeFeedback {
            resetFeedback()
        }

        // The profile needs only a count. The request queue owns its paginated
        // documents; refresh the count on entry and organization-change events.
        if !includeOrganizationRequests { resetOrganizationRequests() }
    }
}
