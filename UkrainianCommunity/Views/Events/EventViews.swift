import SwiftUI

struct EventsListView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: EventsViewModel
    let eventRepository: EventRepository

    private var errorText: String {
        switch viewModel.error {
        case .network:
            AppStrings.Events.loadNetworkError
        case .permissionDenied:
            AppStrings.Events.loadPermissionError
        case .validationFailed:
            AppStrings.Events.loadValidationError
        case .notFound:
            AppStrings.Events.empty
        case .unknown:
            AppStrings.Events.loadUnknownError
        case nil:
            ""
        }
    }

    private var canCreateEvent: Bool {
        authState.user?.role.permissions.canCreateEvent == true
    }

    var body: some View {
        ScrollView {
            if viewModel.events.isEmpty && viewModel.isLoading {
                ProgressView()
                    .padding(.top, 60)
            } else if viewModel.events.isEmpty && viewModel.error != nil {
                VStack(spacing: 16) {
                    Text(errorText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button(AppStrings.Events.retry) {
                        viewModel.reload()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 60)
                .padding(.horizontal, 24)
            } else if viewModel.events.isEmpty {
                VStack(spacing: 16) {
                    Text(AppStrings.Events.empty)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button(AppStrings.Events.retry) {
                        viewModel.reload()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 60)
                .padding(.horizontal, 24)
            } else {
                VStack(spacing: 16) {
                    if viewModel.error != nil {
                        VStack(spacing: 8) {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button(AppStrings.Events.retry) {
                                viewModel.reload()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal, 16)
                    }

                    AdaptiveCardGrid(items: viewModel.events) { event in
                        VStack(spacing: 10) {
                            NavigationLink {
                                EventDetailView(viewModel: viewModel, eventID: event.id)
                            } label: {
                                EventCard(event: event)
                            }
                            .buttonStyle(.plain)

                            HStack {
                                Spacer()
                                LikeButton(isLiked: event.likeState.isLiked, count: event.likeCount) {
                                    viewModel.toggleLike(for: event.id)
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(AppTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle(AppStrings.Events.title)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .toolbar {
            if canCreateEvent {
                NavigationLink {
                    EventEditorView(repository: eventRepository) {
                        viewModel.reload()
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

private struct EventCard: View {
    let event: Event

    var body: some View {
        CommunityCard {
            Text(event.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(event.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            MetadataRow(label: AppStrings.Common.city, value: event.city, systemImage: "mappin.and.ellipse")
            HStack {
                Text(event.registrationState.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryBlue)
            }
        }
    }
}

struct EventDetailView: View {
    @ObservedObject var viewModel: EventsViewModel
    let eventID: String

    var body: some View {
        Group {
            if let event = viewModel.event(for: eventID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        GradientHeroCard(title: event.title, subtitle: event.summary) {
                            Text(event.registrationState.title)
                                .font(.subheadline.weight(.semibold))
                        }

                        CommunityCard {
                            Text(event.details)
                            MetadataRow(label: AppStrings.Common.city, value: event.city, systemImage: "mappin")
                            MetadataRow(label: AppStrings.Common.venue, value: event.venue, systemImage: "building")
                            Button(event.registrationState == .registered ? AppStrings.Events.registered : AppStrings.Events.register) {
                                viewModel.toggleRegistration(for: event.id)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.primaryBlue)
                            LikeButton(isLiked: event.likeState.isLiked, count: event.likeCount) {
                                viewModel.toggleLike(for: event.id)
                            }
                        }

                        CommunityCard {
                            Text(AppStrings.Common.comments)
                                .font(.headline)
                            if event.comments.isEmpty {
                                Text(AppStrings.Common.commentsPlaceholder)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(event.comments) { comment in
                                    Text(AppStrings.commentLine(author: comment.authorName, body: comment.body))
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                    .padding()
                }
            } else {
                EmptyStateView(title: AppStrings.Common.noItems)
            }
        }
        .navigationTitle(AppStrings.Events.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Events List") {
    NavigationStack {
        EventsListView(viewModel: EventsViewModel(repository: MockEventRepository()), eventRepository: MockEventRepository())
            .environmentObject(AuthState())
    }
}

#Preview("Event Detail") {
    NavigationStack {
        EventDetailView(viewModel: EventsViewModel(repository: MockEventRepository()), eventID: MockContentBuilder.events().first!.id)
    }
}
