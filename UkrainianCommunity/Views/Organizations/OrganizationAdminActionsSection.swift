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
                            .foregroundStyle(AppTheme.accentPrimary)
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
                systemImage: organization.likeState.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
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

            pendingSubscriptionConfirmation = organization.isSubscribed
            ? .unsubscribe(organization.id)
            : .subscribe(organization.id)
        }
        .frame(maxWidth: 180)
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
            guestAccessAction = .likes
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
                    .foregroundStyle(isSelected ? AppTheme.accentDestructive : AppTheme.accentPrimary)

                Text("\(count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .monospacedDigit()
            }
            .frame(minWidth: 74, minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(count)")
    }

    func organizationLinkButton(title: String, systemImage: String, destination: URL) -> some View {
        Link(destination: destination) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, AppTheme.dashboardSpacing)
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.iconButtonSize)
                .background(
                    reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassControlSurface(for: colorScheme),
                    in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                )
                .background {
                    if !reduceTransparency {
                        RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                        .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                )
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
        let foregroundColor: Color = {
            if isDestructive {
                return AppTheme.accentDestructive
            }
            return isPrimary ? .white : AppTheme.textPrimary
        }()
        let backgroundColor: Color = {
            if isDestructive {
                return AppTheme.badgeRedFill.opacity(isInteractionDisabled ? 0.62 : 1)
            }
            if isPrimary {
                return AppTheme.accentPrimary.opacity(isInteractionDisabled ? 0.78 : 1)
            }
            return reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassControlSurface(for: colorScheme)
        }()
        let borderColor: Color = {
            if isDestructive {
                return AppTheme.accentDestructive.opacity(isInteractionDisabled ? 0.24 : 0.38)
            }
            return isPrimary ? Color.white.opacity(0.18) : AppTheme.glassBorder(for: colorScheme)
        }()

        return Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, AppTheme.dashboardSpacing)
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.iconButtonSize)
                .background(
                    backgroundColor,
                    in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                )
                .background {
                    if !reduceTransparency {
                        RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                        .strokeBorder(borderColor)
                )
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
