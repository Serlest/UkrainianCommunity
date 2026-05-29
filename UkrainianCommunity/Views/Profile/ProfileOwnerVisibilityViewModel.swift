import Combine

@MainActor
final class OwnerProfileVisibilityViewModel: ObservableObject {
    @Published private var ownerFeedbackItems: [FeedbackItem]?
    @Published private var pendingOrganizationRequests: [Organization]?

    private let feedbackRepository: FeedbackRepository
    private let organizationRepository: OrganizationRepository
    private let listenerBag = RealtimeListenerBag()
    private var hasLoaded = false

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

    func loadIfNeeded() async {
        startListening()
        guard !hasLoaded else { return }
        await refresh()
    }

    func refresh() async {
        startListening()

        do {
            ownerFeedbackItems = try await feedbackRepository.fetchFeedback()
            pendingOrganizationRequests = try await organizationRepository.fetchPendingOrganizations()
            hasLoaded = true
        } catch {
            hasLoaded = true
        }
    }

    func reset() {
        ownerFeedbackItems = nil
        pendingOrganizationRequests = nil
        listenerBag.removeAll()
        hasLoaded = false
    }

    private func startListening() {
        if !listenerBag.contains("ownerFeedback"),
           let realtimeRepository = feedbackRepository as? FeedbackRealtimeRepository {
            listenerBag.set(realtimeRepository.listenOwnerFeedbackInbox { [weak self] items in
                self?.ownerFeedbackItems = items
                self?.hasLoaded = true
            } onError: { [weak self] _ in
                self?.listenerBag.remove("ownerFeedback")
            }, for: "ownerFeedback")
        }

        if !listenerBag.contains("pendingOrganizationRequests"),
           let realtimeRepository = organizationRepository as? OrganizationRealtimeRepository {
            listenerBag.set(realtimeRepository.listenPendingOrganizationRequestsForOwner { [weak self] organizations in
                self?.pendingOrganizationRequests = organizations
                self?.hasLoaded = true
            } onError: { [weak self] _ in
                self?.listenerBag.remove("pendingOrganizationRequests")
            }, for: "pendingOrganizationRequests")
        }
    }
}
