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
    @Published private var pendingOrganizationRequests: [Organization]?
    @Published private(set) var feedbackCountState: OwnerVisibilityCountState = .idle
    @Published private(set) var organizationRequestCountState: OwnerVisibilityCountState = .idle

    private let feedbackRepository: FeedbackRepository
    private let organizationRepository: OrganizationRepository
    private let listenerBag = RealtimeListenerBag()
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
        pendingOrganizationRequests?.count
    }

    var hasCountLoadFailure: Bool {
        feedbackCountState == .failed || organizationRequestCountState == .failed
    }

    func loadIfNeeded(includeOrganizationRequests: Bool, includeFeedback: Bool) async {
        startListening(includeOrganizationRequests: includeOrganizationRequests, includeFeedback: includeFeedback)

        if includeFeedback, !hasLoadedFeedback {
            await refreshFeedback()
        } else if !includeFeedback {
            resetFeedback()
        }

        if includeOrganizationRequests, !hasLoadedOrganizationRequests {
            await refreshOrganizationRequests()
        } else if !includeOrganizationRequests {
            resetOrganizationRequests()
        }
    }

    func refresh(includeOrganizationRequests: Bool, includeFeedback: Bool) async {
        startListening(includeOrganizationRequests: includeOrganizationRequests, includeFeedback: includeFeedback)

        if includeFeedback {
            await refreshFeedback()
        } else {
            resetFeedback()
        }

        if includeOrganizationRequests {
            await refreshOrganizationRequests()
        } else {
            resetOrganizationRequests()
        }
    }

    func reset() {
        resetFeedback()
        resetOrganizationRequests()
    }

    private func refreshFeedback() async {
        feedbackCountState = .loading

        do {
            ownerFeedbackItems = try await RefreshRequest.run { [self] in try await feedbackRepository.fetchFeedback() }
            hasLoadedFeedback = true
            feedbackCountState = .loaded(unreadFeedbackCount ?? 0)
        } catch {
            hasLoadedFeedback = false
            if feedbackCountState == .loading {
                feedbackCountState = .failed
            }
        }
    }

    private func refreshOrganizationRequests() async {
        organizationRequestCountState = .loading

        do {
            pendingOrganizationRequests = try await RefreshRequest.run { [self] in try await organizationRepository.fetchPendingOrganizations() }
            hasLoadedOrganizationRequests = true
            organizationRequestCountState = .loaded(pendingOrganizationRequestCount ?? 0)
        } catch {
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
        if includeFeedback,
           !listenerBag.contains("ownerFeedback"),
           let realtimeRepository = feedbackRepository as? FeedbackRealtimeRepository {
            listenerBag.set(realtimeRepository.listenOwnerFeedbackInbox { [weak self] items in
                self?.ownerFeedbackItems = items
                self?.hasLoadedFeedback = true
                self?.feedbackCountState = .loaded(items.filter(\.unreadForOwner).count)
            } onError: { [weak self] _ in
                self?.hasLoadedFeedback = false
                self?.feedbackCountState = .failed
                self?.listenerBag.remove("ownerFeedback")
            }, for: "ownerFeedback")
        } else if !includeFeedback {
            resetFeedback()
        }

        if includeOrganizationRequests,
           !listenerBag.contains("pendingOrganizationRequests"),
           let realtimeRepository = organizationRepository as? OrganizationRealtimeRepository {
            listenerBag.set(realtimeRepository.listenPendingOrganizationRequestsForOwner { [weak self] organizations in
                self?.pendingOrganizationRequests = organizations
                self?.hasLoadedOrganizationRequests = true
                self?.organizationRequestCountState = .loaded(organizations.count)
            } onError: { [weak self] _ in
                self?.hasLoadedOrganizationRequests = false
                self?.organizationRequestCountState = .failed
                self?.listenerBag.remove("pendingOrganizationRequests")
            }, for: "pendingOrganizationRequests")
        } else if !includeOrganizationRequests {
            resetOrganizationRequests()
        }
    }
}
