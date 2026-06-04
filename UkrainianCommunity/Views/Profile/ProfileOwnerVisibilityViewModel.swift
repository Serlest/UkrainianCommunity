import Combine

@MainActor
final class OwnerProfileVisibilityViewModel: ObservableObject {
    @Published private var ownerFeedbackItems: [FeedbackItem]?
    @Published private var pendingOrganizationRequests: [Organization]?

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
        do {
            ownerFeedbackItems = try await feedbackRepository.fetchFeedback()
            hasLoadedFeedback = true
        } catch {
            hasLoadedFeedback = true
        }
    }

    private func refreshOrganizationRequests() async {
        do {
            pendingOrganizationRequests = try await organizationRepository.fetchPendingOrganizations()
            hasLoadedOrganizationRequests = true
        } catch {
            hasLoadedOrganizationRequests = true
        }
    }

    private func resetFeedback() {
        ownerFeedbackItems = nil
        listenerBag.remove("ownerFeedback")
        hasLoadedFeedback = false
    }

    private func resetOrganizationRequests() {
        pendingOrganizationRequests = nil
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
            } onError: { [weak self] _ in
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
            } onError: { [weak self] _ in
                self?.listenerBag.remove("pendingOrganizationRequests")
            }, for: "pendingOrganizationRequests")
        } else if !includeOrganizationRequests {
            resetOrganizationRequests()
        }
    }
}
