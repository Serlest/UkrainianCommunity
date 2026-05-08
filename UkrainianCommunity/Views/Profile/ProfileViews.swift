import Combine
import SwiftUI

struct ProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @EnvironmentObject var authState: AuthState
    @State private var isShowingEditProfileSheet = false
    @State private var fullNameDraft = ""
    @State private var displayNameDraft = ""
    @State private var telegramUsernameDraft = ""
    @State private var cityDraft = ""
    @State private var bioDraft = ""
    @State private var selectedFederalStateDraft: AustrianFederalState = .tirol
    @State private var selectedFeedbackType: FeedbackType = .question
    @State private var feedbackMessage = ""
    @State private var guestAccessAction: GuestAccessAction?
    @State private var isShowingLogoutConfirmation = false
    @State private var logoutErrorMessage: String?

    private var permissionUser: AppUser? {
        authState.user ?? displayUser
    }

    private var canShowAdminTools: Bool {
        PermissionService.canAccessAdminTools(user: permissionUser)
    }

    private var canShowModerationTools: Bool {
        PermissionService.canAccessModerationTools(user: permissionUser)
    }

    private var canShowContentManagement: Bool {
        PermissionService.canAccessContentManagement(user: permissionUser)
    }

    private var canShowOrganizationManagement: Bool {
        PermissionService.canAccessOrganizationManagement(user: permissionUser)
    }

    private var displayUser: AppUser? {
        guard authState.isAuthenticated else {
            return nil
        }

        if let authenticatedUser = authState.user {
            return authenticatedUser
        }

        guard viewModel.user.id != AppUser.placeholder.id else {
            return nil
        }

        return viewModel.user
    }

    private var readableFederalState: String? {
        guard let federalState = displayUser?.selectedFederalState else { return nil }
        return AppStrings.FederalStates.title(for: federalState)
    }

    private var capabilityItems: [String] {
        guard let user = permissionUser else {
            return [AppStrings.Common.likes, AppStrings.Profile.eventRegistration]
        }

        var items = [AppStrings.Common.likes, AppStrings.Profile.eventRegistration]

        if PermissionService.canModerate(section: .news, user: user)
            || PermissionService.canModerate(section: .events, user: user)
            || PermissionService.canModerate(section: .organizations, user: user) {
            items.append(AppStrings.Profile.moderationTools)
        }

        if PermissionService.canAccessAdminTools(user: user) {
            items.append(AppStrings.Profile.adminTools)
            items.append(AppStrings.Profile.userManagement)
        }

        return items
    }

    private var hasManagementSection: Bool {
        canShowOrganizationManagement || canShowContentManagement
    }

    private var hasAdministrationSection: Bool {
        canShowModerationTools || canShowAdminTools
    }

    private var feedbackSupportSection: some View {
        Section(AppStrings.Profile.feedbackSupport) {
            if let user = displayUser {
                FeedbackComposerCard(
                    selectedFeedbackType: $selectedFeedbackType,
                    feedbackMessage: $feedbackMessage,
                    statusMessage: viewModel.feedbackMessage,
                    isSubmitting: viewModel.isSubmittingFeedback
                ) {
                    submitFeedback(for: user)
                }
            }
        }
        .listRowBackground(AppTheme.surfacePrimary)
    }

    private var activitySection: some View {
        Section(AppStrings.Profile.myActivity) {
            ActivitySummaryCard(
                title: AppStrings.Profile.accountSummary,
                subtitle: AppStrings.Profile.activitySubtitle,
                items: capabilityItems
            )
        }
        .listRowBackground(AppTheme.surfacePrimary)
    }

    private var organizationsSection: some View {
        Section(AppStrings.Profile.myOrganizations) {
            if canShowOrganizationManagement, let user = permissionUser {
                NavigationLink {
                    OrganizationManagementHubView(currentUser: user)
                } label: {
                    ProfileNavigationCardLabel(
                        title: AppStrings.Profile.organizationManagement,
                        subtitle: AppStrings.Profile.organizationManagementSubtitle,
                        systemImage: "building.2.crop.circle"
                    )
                }
                .accessibilityLabel(AppStrings.Profile.organizationManagement)
            } else {
                SectionSummaryCard(
                    title: AppStrings.Profile.myOrganizations,
                    subtitle: AppStrings.Profile.organizationsSectionSubtitle,
                    systemImage: "building.2"
                )
            }
        }
        .listRowBackground(AppTheme.surfacePrimary)
    }

    private var appManagementSection: some View {
        Section(AppStrings.Profile.appManagement) {
            if canShowContentManagement {
                if PermissionService.canManageAppNews(user: permissionUser) {
                    NavigationLink {
                        AppNewsManagementView()
                    } label: {
                        ProfileNavigationCardLabel(
                            title: AppStrings.Profile.manageAppNews,
                            subtitle: AppStrings.Profile.contentManagementSubtitle,
                            systemImage: "newspaper"
                        )
                    }
                    .accessibilityLabel(AppStrings.Profile.manageAppNews)
                }

                if PermissionService.canManageAppEvents(user: permissionUser) {
                    NavigationLink {
                        AppEventsManagementView()
                    } label: {
                        ProfileNavigationCardLabel(
                            title: AppStrings.Profile.manageAppEvents,
                            subtitle: AppStrings.Profile.contentManagementSubtitle,
                            systemImage: "calendar"
                        )
                    }
                    .accessibilityLabel(AppStrings.Profile.manageAppEvents)
                }
            }

            if canShowModerationTools {
                NavigationLink {
                    ModerationToolsView()
                } label: {
                    ProfileNavigationCardLabel(
                        title: AppStrings.Profile.reviewPendingContent,
                        subtitle: AppStrings.Profile.appManagementSubtitle,
                        systemImage: "clock.badge.exclamationmark"
                    )
                }
                .accessibilityLabel(AppStrings.Profile.reviewPendingContent)
            }

            if canShowAdminTools {
                NavigationLink {
                    UserManagementView()
                } label: {
                    ProfileNavigationCardLabel(
                        title: AppStrings.Profile.userManagement,
                        subtitle: AppStrings.Profile.appManagementSubtitle,
                        systemImage: "person.3"
                    )
                }
                .accessibilityLabel(AppStrings.Profile.userManagement)
            }
        }
        .listRowBackground(AppTheme.surfacePrimary)
    }

    var body: some View {
        List {
            Section(AppStrings.Profile.accountSection) {
                ProfileHeaderCard(
                    sessionState: authState.sessionState,
                    user: displayUser,
                    readableFederalState: readableFederalState,
                    onEditProfile: beginEditingProfile,
                    onSignIn: { authState.presentAuthFlow(.login) },
                    onCreateAccount: { authState.presentAuthFlow(.register) }
                )
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if authState.isAuthenticated {
                activitySection
                organizationsSection
            }

            if displayUser != nil, (hasAdministrationSection || canShowContentManagement) {
                appManagementSection
            }

            if displayUser != nil {
                feedbackSupportSection
            }

            Section(AppStrings.Settings.title) {
                Picker(AppStrings.Settings.language, selection: $viewModel.settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }

                Picker(AppStrings.Settings.appearance, selection: $viewModel.settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }

                NavigationLink {
                    LegalDocumentView(document: .privacy)
                } label: {
                    Label(AppStrings.Settings.privacyPolicy, systemImage: "lock.doc")
                }
                .accessibilityIdentifier("settings.privacy.button")
                .accessibilityLabel(AppStrings.Settings.privacyPolicy)

                NavigationLink {
                    LegalDocumentView(document: .terms)
                } label: {
                    Label(AppStrings.Settings.terms, systemImage: "doc.text")
                }
                .accessibilityIdentifier("settings.terms.button")
                .accessibilityLabel(AppStrings.Settings.terms)

                if authState.isAuthenticated {
                    Button(role: .destructive) {
                        isShowingLogoutConfirmation = true
                    } label: {
                        Label(AppStrings.Profile.signOut, systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .accessibilityIdentifier("profile.logout.button")
                    .accessibilityLabel(AppStrings.Profile.signOut)
                }
            }
            .listRowBackground(AppTheme.surfacePrimary)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .tint(AppTheme.accentPrimary)
        .navigationTitle(AppStrings.Profile.title)
        .task {
            await viewModel.loadIfNeeded()
            await viewModel.refreshIfStale()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: $isShowingEditProfileSheet) {
            NavigationStack {
                Form {
                    Section {
                        TextField(AppStrings.Profile.fullName, text: $fullNameDraft)
                            .textInputAutocapitalization(.words)
                            .accessibilityLabel(AppStrings.Profile.fullName)

                        TextField(AppStrings.Profile.displayName, text: $displayNameDraft)
                            .textInputAutocapitalization(.words)
                            .accessibilityLabel(AppStrings.Profile.displayName)

                        TextField(AppStrings.Auth.email, text: .constant(displayUser?.email ?? ""))
                            .disabled(true)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(AppStrings.Auth.email)

                        TextField(AppStrings.Common.city, text: $cityDraft)
                            .textInputAutocapitalization(.words)
                            .accessibilityLabel(AppStrings.Common.city)

                        TextField(AppStrings.Profile.telegramUsername, text: $telegramUsernameDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel(AppStrings.Profile.telegramUsername)

                        Picker(AppStrings.Auth.federalState, selection: $selectedFederalStateDraft) {
                            ForEach(AustrianFederalState.allCases) { state in
                                Text(AppStrings.FederalStates.title(for: state)).tag(state)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(AppStrings.Profile.bio)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)

                            TextEditor(text: $bioDraft)
                                .frame(minHeight: 120)
                                .padding(8)
                                .background(
                                    AppTheme.surfaceSecondary,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                                .accessibilityLabel(AppStrings.Profile.bio)
                        }
                    } footer: {
                        Text(AppStrings.Profile.emailReadOnlyHint)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(.secondary)
                    }

                    if let profileStatusMessage = viewModel.profileMessage {
                        Section {
                            Text(profileStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(profileStatusMessage == AppStrings.Profile.profileSaved ? .green : .red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Section {
                        Button {
                            Task {
                                let updatedUser = await viewModel.saveProfile(
                                    EditableUserProfileDraft(
                                        fullName: fullNameDraft,
                                        displayName: displayNameDraft,
                                        telegramUsername: telegramUsernameDraft,
                                        city: cityDraft,
                                        bio: bioDraft,
                                        selectedFederalState: selectedFederalStateDraft
                                    )
                                )
                                guard let updatedUser else { return }
                                authState.user = updatedUser
                                isShowingEditProfileSheet = false
                            }
                        } label: {
                            if viewModel.isSavingProfile {
                                ProgressView(AppStrings.Profile.saveProfile)
                            } else {
                                Text(AppStrings.Profile.saveProfile)
                            }
                        }
                        .disabled(viewModel.isSavingProfile)
                        .accessibilityLabel(AppStrings.Profile.saveProfile)
                    }
                }
                .navigationTitle(AppStrings.Profile.editProfile)
            }
        }
        .confirmationDialog(
            AppStrings.Profile.signOutConfirmTitle,
            isPresented: $isShowingLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppStrings.Profile.signOut, role: .destructive) {
                let didSignOut = AuthService.shared.signOut()
                if !didSignOut {
                    logoutErrorMessage = AppStrings.Profile.signOutFailed
                }
            }

            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.Profile.signOutConfirmMessage)
        }
        .alert(AppStrings.Profile.signOutFailed, isPresented: Binding(
            get: { logoutErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    logoutErrorMessage = nil
                }
            }
        )) {
            Button(AppStrings.Common.ok, role: .cancel) {
                logoutErrorMessage = nil
            }
        } message: {
            Text(logoutErrorMessage ?? "")
        }
        .guestAccessAlert($guestAccessAction)
    }

    private func beginEditingProfile() {
        guard authState.isAuthenticated else {
            guestAccessAction = .profileEditing
            return
        }

        fullNameDraft = displayUser?.fullName ?? ""
        displayNameDraft = displayUser?.displayName ?? ""
        telegramUsernameDraft = displayUser?.telegramUsername ?? ""
        cityDraft = displayUser?.city ?? ""
        bioDraft = displayUser?.bio ?? ""
        selectedFederalStateDraft = displayUser?.selectedFederalState ?? .tirol
        viewModel.profileMessage = nil
        isShowingEditProfileSheet = true
    }

    private func submitFeedback(for user: AppUser) {
        guard authState.isAuthenticated else {
            guestAccessAction = .feedback
            return
        }

        Task {
            let didSubmit = await viewModel.submitFeedback(
                type: selectedFeedbackType,
                message: feedbackMessage,
                user: user
            )
            if didSubmit {
                feedbackMessage = ""
                selectedFeedbackType = .question
            }
        }
    }
}

private struct ProfileHeaderCard: View {
    let sessionState: AuthSessionState
    let user: AppUser?
    let readableFederalState: String?
    let onEditProfile: () -> Void
    let onSignIn: () -> Void
    let onCreateAccount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let user {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 16) {
                        ProfileAvatarView(user: user)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(user.preferredDisplayName)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            if let fullName = user.preferredFullName {
                                Text(fullName)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) {
                                    if user.globalRole != .user {
                                        ProfileBadge(title: user.globalRole.title, systemImage: "person.badge.key")
                                    }

                                    if let readableFederalState {
                                        ProfileBadge(title: readableFederalState, systemImage: "globe.europe.africa")
                                    }
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    if user.globalRole != .user {
                                        ProfileBadge(title: user.globalRole.title, systemImage: "person.badge.key")
                                    }

                                    if let readableFederalState {
                                        ProfileBadge(title: readableFederalState, systemImage: "globe.europe.africa")
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    if let bio = user.bio.nilIfEmpty {
                        Text(bio)
                            .font(.body)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        if let city = user.city.nilIfEmpty {
                            ProfileMetadataRow(value: city, systemImage: "mappin.and.ellipse")
                        }

                        if let telegramUsername = user.telegramUsername?.nilIfEmpty {
                            ProfileMetadataRow(value: "@\(telegramUsername)", systemImage: "paperplane")
                        }

                        ProfileMetadataRow(
                            value: LocalizationStore.dateString(from: user.joinedAt),
                            systemImage: "calendar"
                        )

                        ProfileMetadataRow(
                            value: user.accountStatus.title,
                            systemImage: "checkmark.shield"
                        )
                    }
                }

                Button(AppStrings.Profile.editProfile, action: onEditProfile)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accentPrimary)
                    .accessibilityIdentifier("profile.edit.button")
                    .accessibilityLabel(AppStrings.Profile.editProfile)
            } else if sessionState == .restoring {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(AppStrings.Profile.loadingUserProfile)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text(AppStrings.Profile.guestTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(AppStrings.Profile.guestMessage)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button(AppStrings.Auth.signIn, action: onSignIn)
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.accentPrimary)
                            .accessibilityIdentifier("profile.guest.signIn")

                        Button(AppStrings.Auth.createAccount, action: onCreateAccount)
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("profile.guest.createAccount")
                    }
                }
                .accessibilityIdentifier("profile.guest.card")
            }
        }
        .padding(20)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.borderSubtle)
        )
        .accessibilityIdentifier("profile.account.hero")
    }
}

private struct ProfileAvatarView: View {
    let user: AppUser

    var body: some View {
        Group {
            if let avatarURL = user.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(Circle())
        .overlay(Circle().stroke(AppTheme.borderSubtle))
        .accessibilityLabel(user.preferredDisplayName)
    }

    private var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accentPrimarySoft, AppTheme.surfaceSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(user.initials)
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.accentPrimary)
        }
    }
}

private struct ProfileMetadataRow: View {
    let value: String
    let systemImage: String

    var body: some View {
        Label {
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accentPrimary)
        }
        .font(.subheadline)
        .foregroundStyle(AppTheme.textSecondary)
    }
}

private struct ProfileNavigationCardLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 34, height: 34)
                .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }
}

private struct ActivitySummaryCard: View {
    let title: String
    let subtitle: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FlowLayout(spacing: 10) {
                ForEach(items, id: \.self) { item in
                    ProfileBadge(title: item, systemImage: "checkmark.circle.fill")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SectionSummaryCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 38, height: 38)
                .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct FeedbackComposerCard: View {
    @Binding var selectedFeedbackType: FeedbackType
    @Binding var feedbackMessage: String
    let statusMessage: String?
    let isSubmitting: Bool
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppStrings.Feedback.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker(AppStrings.Feedback.fieldType, selection: $selectedFeedbackType) {
                ForEach(FeedbackType.allCases) { feedbackType in
                    Text(feedbackType.title).tag(feedbackType)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel(AppStrings.Feedback.fieldType)

            TextEditor(text: $feedbackMessage)
                .frame(minHeight: 110)
                .padding(8)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel(AppStrings.Feedback.fieldMessage)

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(statusMessage == AppStrings.Feedback.submitted ? .green : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onSubmit) {
                if isSubmitting {
                    ProgressView(AppStrings.Feedback.submit)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(AppStrings.Feedback.submit)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accentPrimary)
            .disabled(isSubmitting)
            .accessibilityLabel(AppStrings.Feedback.submit)
        }
        .padding(.vertical, 4)
    }
}

private struct ProfileBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.accentPrimary)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.accentPrimarySoft, in: Capsule())
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }

        return CGSize(width: proposal.width ?? currentX, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct AppNewsManagementView: View {
    private let repository: NewsRepository
    @StateObject private var viewModel: NewsViewModel

    init(repository: NewsRepository = FirestoreNewsRepository()) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: NewsViewModel(repository: repository))
    }

    var body: some View {
        NewsListView(
            viewModel: viewModel,
            newsRepository: repository,
            onNewsPublished: {},
            onNewsChanged: {},
            presentationMode: .management
        )
    }
}

private struct AppEventsManagementView: View {
    private let repository: EventRepository
    @StateObject private var viewModel: EventsViewModel

    init(repository: EventRepository = FirestoreEventRepository()) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: EventsViewModel(repository: repository))
    }

    var body: some View {
        EventsListView(
            viewModel: viewModel,
            eventRepository: repository,
            onEventPublished: {},
            onEventDeleted: { @MainActor @Sendable in },
            presentationMode: .management
        )
    }
}

private struct OrganizationManagementHubView: View {
    let currentUser: AppUser

    private let repository: OrganizationRepository
    @StateObject private var organizationsViewModel: OrganizationsViewModel

    init(
        currentUser: AppUser,
        repository: OrganizationRepository = FirestoreOrganizationRepository()
    ) {
        self.currentUser = currentUser
        self.repository = repository
        _organizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(repository: repository))
    }

    private var manageableOrganizations: [Organization] {
        switch currentUser.globalRole {
        case .owner, .topAdmin:
            return organizationsViewModel.organizations
        case .appModerator, .user:
            let manageableIDs = PermissionService.manageableOrganizationIDs(user: currentUser)
            return organizationsViewModel.organizations.filter { manageableIDs.contains($0.id) }
        }
    }

    var body: some View {
        List {
            Section {
                Text(AppStrings.Profile.organizationManagementSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(AppTheme.surfacePrimary)

            if organizationsViewModel.isLoading && manageableOrganizations.isEmpty {
                Section {
                    LoadingStateCard(title: nil)
                }
                .listRowBackground(AppTheme.surfacePrimary)
            } else if manageableOrganizations.isEmpty {
                Section {
                    EmptyStateCard(
                        systemImage: "building.2",
                        title: AppStrings.Profile.myOrganizations,
                        message: AppStrings.Profile.noManagedOrganizations
                    )
                }
                .listRowBackground(AppTheme.surfacePrimary)
            } else {
                Section {
                    ForEach(manageableOrganizations) { organization in
                        NavigationLink {
                            ManagedOrganizationView(
                                organization: organization,
                                organizationsViewModel: organizationsViewModel
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(organization.name)
                                    .font(.headline)

                                Text(organization.city)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        .accessibilityLabel(organization.name)
                    }
                }
                .listRowBackground(AppTheme.surfacePrimary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(AppStrings.Profile.organizationManagement)
        .task {
            await organizationsViewModel.loadIfNeeded()
            await organizationsViewModel.refreshIfStale()
        }
        .refreshable {
            await organizationsViewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task {
                await organizationsViewModel.refresh()
            }
        }
    }
}

private struct ManagedOrganizationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState

    let organization: Organization
    @ObservedObject var organizationsViewModel: OrganizationsViewModel

    @State private var isShowingNewsEditor = false
    @State private var isShowingEventEditor = false
    @State private var isShowingOrganizationEditor = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeletingOrganization = false
    @State private var deleteErrorMessage: String?

    private var currentOrganization: Organization {
        organizationsViewModel.organization(for: organization.id) ?? organization
    }

    private var canCreateNews: Bool {
        PermissionService.canCreateNews(for: currentOrganization.id, user: authState.user)
    }

    private var canCreateEvent: Bool {
        PermissionService.canCreateEvent(for: currentOrganization.id, user: authState.user)
    }

    private var canEditOrganization: Bool {
        PermissionService.canEditOrganization(organizationId: currentOrganization.id, user: authState.user)
    }

    private var canDeleteOrganization: Bool {
        PermissionService.canDeleteOrganization(user: authState.user)
    }

    var body: some View {
        List {
            Section(AppStrings.Profile.myOrganizations) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(currentOrganization.name)
                        .font(.title3.weight(.semibold))

                    Text(currentOrganization.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                MetadataRow(label: AppStrings.Common.city, value: currentOrganization.city, systemImage: "mappin.and.ellipse")

                if let contactEmail = currentOrganization.contactEmail, !contactEmail.isEmpty {
                    MetadataRow(label: AppStrings.Common.contact, value: contactEmail, systemImage: "envelope")
                }

                if let website = currentOrganization.website, !website.isEmpty {
                    MetadataRow(label: AppStrings.Common.website, value: website, systemImage: "link")
                }
            }
            .listRowBackground(AppTheme.surfacePrimary)

            Section(AppStrings.Profile.organizationManagement) {
                if canCreateNews {
                    Button {
                        isShowingNewsEditor = true
                    } label: {
                        Label(AppStrings.Profile.createOrganizationNews, systemImage: "square.and.pencil")
                    }
                    .accessibilityLabel(AppStrings.Profile.createOrganizationNews)
                }

                if canCreateEvent {
                    Button {
                        isShowingEventEditor = true
                    } label: {
                        Label(AppStrings.Profile.createOrganizationEvent, systemImage: "calendar.badge.plus")
                    }
                    .accessibilityLabel(AppStrings.Profile.createOrganizationEvent)
                }

                if canEditOrganization {
                    Button {
                        isShowingOrganizationEditor = true
                    } label: {
                        Label(AppStrings.Profile.editOrganizationDetails, systemImage: "building.2.crop.circle")
                    }
                    .accessibilityLabel(AppStrings.Profile.editOrganizationDetails)
                }

                if canDeleteOrganization {
                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label(AppStrings.Organizations.delete, systemImage: "trash")
                    }
                    .disabled(isDeletingOrganization)
                    .accessibilityLabel(AppStrings.Organizations.delete)
                }
            }
            .listRowBackground(AppTheme.surfacePrimary)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(currentOrganization.name)
        .sheet(isPresented: $isShowingNewsEditor) {
            NavigationStack {
                NewsEditorView(
                    repository: FirestoreNewsRepository(),
                    organizationId: currentOrganization.id,
                    organizationName: currentOrganization.name,
                    organizationImageURL: currentOrganization.imageURL
                )
            }
        }
        .sheet(isPresented: $isShowingEventEditor) {
            NavigationStack {
                EventEditorView(
                    repository: FirestoreEventRepository(),
                    organizationId: currentOrganization.id,
                    organizationName: currentOrganization.name,
                    organizationImageURL: currentOrganization.imageURL
                )
            }
        }
        .sheet(isPresented: $isShowingOrganizationEditor) {
            NavigationStack {
                OrganizationEditorView(
                    organizationsViewModel: organizationsViewModel,
                    organization: currentOrganization,
                    onSaved: {}
                )
            }
        }
        .confirmationDialog(
            AppStrings.Organizations.deleteConfirmation,
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppStrings.Organizations.delete, role: .destructive) {
                Task {
                    await deleteOrganization()
                }
            }

            Button(AppStrings.Organizations.cancel, role: .cancel) {}
        }
        .alert(
            AppStrings.Organizations.deleteFailed,
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )
        ) {
            Button(AppStrings.Organizations.dismissError, role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    @MainActor
    private func deleteOrganization() async {
        guard !isDeletingOrganization else { return }
        isDeletingOrganization = true
        defer { isDeletingOrganization = false }

        do {
            try await organizationsViewModel.deleteOrganization(id: currentOrganization.id, user: authState.user)
            organizationsViewModel.removeDeletedOrganization(id: currentOrganization.id)
            dismiss()
        } catch let appError as AppError {
            deleteErrorMessage = readableManagedOrganizationErrorText(appError)
        } catch {
            deleteErrorMessage = readableManagedOrganizationErrorText(.unknown)
        }
    }

    private func readableManagedOrganizationErrorText(_ error: AppError?) -> String {
        switch error {
        case .network:
            AppStrings.Organizations.loadNetworkError
        case .permissionDenied:
            AppStrings.Organizations.actionPermissionError
        case .validationFailed:
            AppStrings.Organizations.actionValidationError
        case .notFound:
            AppStrings.Organizations.actionNotFoundError
        case .unknown:
            AppStrings.Organizations.actionUnknownError
        case nil:
            AppStrings.Organizations.actionUnknownError
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView(viewModel: ProfileViewModel(
            repository: MockUserRepository(),
            feedbackRepository: MockFeedbackRepository()
        ))
    }
    .environmentObject(AuthState())
}
