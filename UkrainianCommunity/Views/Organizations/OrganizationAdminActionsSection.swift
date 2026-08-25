import SwiftUI

extension OrganizationDetailView {
    func actionButtons(for organization: Organization) -> some View {
        detailGlassCard(padding: 9) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    engagementMetrics(for: organization)
                    Spacer(minLength: 0)
                    subscribeButton(for: organization)
                }

                VStack(alignment: .leading, spacing: 10) {
                    engagementMetrics(for: organization)
                    subscribeButton(for: organization)
                }
            }
        }
    }

    @ViewBuilder
    func supportCard(for organization: Organization) -> some View {
        if let donationURL = normalizedOrganizationURL(from: organization.donationURL) {
            detailGlassCard(padding: 12) {
                Link(destination: donationURL) {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.accentPrimaryForeground)
                            .frame(width: 36, height: 36)
                            .background(
                                reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassControlSurface(for: colorScheme),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppStrings.Organizations.supportOrganizationTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)

                            Text(AppStrings.Organizations.supportOrganizationSubtitle)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.Organizations.supportOrganizationTitle)
            }
        }
    }

    func engagementMetrics(for organization: Organization) -> some View {
        HStack(spacing: 8) {
            detailMetricButton(
                systemImage: organization.likeState.isLiked ? "heart.fill" : "heart",
                count: organization.likeCount,
                accessibilityLabel: organization.likeState.isLiked ? AppStrings.Action.unlike : AppStrings.Action.like,
                isSelected: organization.likeState.isLiked
            ) {
                toggleLike(for: organization)
            }
            .disabled(viewModel.pendingOrganizationLikeIDs.contains(organization.id))

            detailMetricButton(
                systemImage: "bubble.left",
                count: viewModel.comments(for: organization.id).count,
                accessibilityLabel: AppStrings.Common.comments
            ) {
                isCommentFieldFocused = true
            }
        }
    }

    func subscribeButton(for organization: Organization) -> some View {
        organizationActionButton(
            title: organization.isSubscribed ? AppStrings.Organizations.unfollow : AppStrings.Organizations.follow,
            systemImage: organization.isSubscribed ? "person.2.fill" : "person.2.badge.plus",
            isPrimary: true,
            isDestructive: organization.isSubscribed,
            isDisabled: viewModel.pendingOrganizationSubscriptionIDs.contains(organization.id)
        ) {
            guard authState.isAuthenticated else {
                toggleSubscription(for: organization)
                return
            }

            if organization.isSubscribed {
                pendingSubscriptionConfirmation = .unsubscribe(organization.id)
            } else {
                toggleSubscription(for: organization)
            }
        }
        .frame(maxWidth: 180)
        .accessibilityAddTraits(organization.isSubscribed ? .isSelected : [])
    }

    func toggleLike(for organization: Organization) {
        guard authState.isAuthenticated else {
            guestAccessAction = .likes
            return
        }

        viewModel.toggleLike(for: organization.id)
    }

    func toggleSubscription(for organization: Organization) {
        guard authState.isAuthenticated else {
            guestAccessAction = .subscriptions
            return
        }

        viewModel.toggleSubscription(for: organization.id)
    }

    func detailMetricButton(
        systemImage: String,
        count: Int,
        accessibilityLabel: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? AppTheme.accentDestructiveForeground : AppTheme.accentPrimaryForeground)

                Text("\(count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .monospacedDigit()
            }
            .frame(minWidth: 74, minHeight: AppTheme.minimumInteractiveTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppPressFeedbackButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(count)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    func organizationLinkButton(title: String, systemImage: String, destination: URL) -> some View {
        Link(destination: destination) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, AppTheme.dashboardSpacing)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppTheme.iconButtonSize)
                .appGlassActionSurface(.regular)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    func organizationActionButton(
        title: String,
        systemImage: String,
        isPrimary: Bool = false,
        isDestructive: Bool = false,
        isPlaceholder: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void = {}
    ) -> some View {
        let isInteractionDisabled = isPlaceholder || isDisabled
        let hierarchy: AppGlassActionHierarchy = isDestructive
            ? .destructive
            : (isPrimary ? .prominent : .regular)

        return Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, AppTheme.dashboardSpacing)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppTheme.iconButtonSize)
                .appGlassActionSurface(hierarchy, isEnabled: !isInteractionDisabled)
        }
        .buttonStyle(.plain)
        .disabled(isInteractionDisabled)
        .accessibilityHint(isPlaceholder ? AppStrings.Action.comingSoon : "")
    }

    func deleteCurrentOrganization() async {
        do {
            try await viewModel.deleteOrganization(id: organizationID, user: authState.user)
            pendingRemovalOrganizationID = organizationID
            dismiss()
            onOrganizationDeleted()
        } catch let appError as AppError {
            deleteErrorMessage = readableOrganizationErrorText(appError)
        } catch {
            deleteErrorMessage = readableOrganizationErrorText(.unknown)
        }
    }
}
