import SwiftUI

#Preview("Events List") {
    NavigationStack {
        EventsListView(
            viewModel: EventsViewModel(repository: MockEventRepository()),
            eventRepository: MockEventRepository(),
            featuredBannerRepository: MockFeaturedBannerRepository(),
            onEventPublished: {},
            onEventDeleted: {},
            presentationMode: .management
        )
            .environmentObject(AuthState())
    }
}

#Preview("Event Detail") {
    NavigationStack {
        EventDetailView(
            viewModel: EventsViewModel(repository: MockEventRepository()),
            eventID: MockContentBuilder.events().first!.id,
            onEventDeleted: {}
        )
        .environment(\.eventPresentationMode, .management)
    }
    .environmentObject(AuthState())
}
