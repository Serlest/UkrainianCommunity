import SwiftUI

extension EventDetailView {
        func navigateBack() {
            if let onNavigateBack {
                onNavigateBack()
            } else {
                dismiss()
            }
        }

        func eventHeaderActions(for event: Event) -> some View {
            Group {
                DetailHeaderActionButton(
                    systemImage: event.isBookmarked ? "bookmark.fill" : "bookmark",
                    accessibilityLabel: event.isBookmarked ? AppStrings.Action.unsave : AppStrings.Action.save,
                    isDisabled: viewModel.pendingEventBookmarkIDs.contains(event.id),
                    isSelected: event.isBookmarked
                ) {
                    handleBookmark(for: event)
                }

                DetailHeaderShareButton(
                    title: event.title,
                    message: eventShareMessage(for: event),
                    url: eventShareURL(for: event)
                )

                if event.authorId != authState.user?.id || !authState.isAuthenticated {
                    DetailHeaderActionButton(
                        systemImage: "exclamationmark.bubble",
                        accessibilityLabel: AppStrings.Safety.reportAction
                    ) {
                        presentContentReport(.event(event))
                    }
                }

                if authState.isAuthenticated,
                   let target = UserBlockTarget.event(event),
                   target.userId != authState.user?.id {
                    DetailHeaderActionButton(
                        systemImage: "person.crop.circle.badge.xmark",
                        accessibilityLabel: AppStrings.Safety.blockAction
                    ) {
                        userBlockingPresentation.present(target)
                    }
                }
            }
        }

        func presentContentReport(_ target: ContentReportTarget) {
            guard authState.isAuthenticated else {
                guestAccessAction = .feedback
                return
            }
            contentReportPresentation.present(target)
        }

        func eventShareMessage(for event: Event) -> String {
            [
                event.summary,
                eventScheduleText(for: event),
                [event.venue, event.city].filter { !$0.isEmpty }.joined(separator: ", ")
            ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        }

        func eventShareURL(for event: Event) -> URL? {
            [event.contactURL, event.organizerURL].compactMap(safeEventShareURL).first
        }

        private func safeEventShareURL(_ value: String?) -> URL? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http" else { return nil }
            return url
        }

        @ViewBuilder
        func heroImageSection(for event: Event) -> some View {
            if let imageURL = eventImageURL(for: event) {
                eventHeroImage(imageURL: imageURL, size: nil)
            }
        }

        func articleHeader(for event: Event) -> some View {
            DetailHeaderCard(title: event.title, subtitle: nil) {
                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    eventBadge(for: event)
                    metadataRow(for: event)
                }
            }
            .accessibilityElement(children: .contain)
        }

        func eventBadge(for event: Event) -> some View {
            AppHorizontalChipRow(spacing: 8) {
                ContentMetadataPill(
                    systemImage: event.category.systemImage,
                    text: eventDetailCategoryTitle(for: event.category).uppercased()
                )
                ContentMetadataPill(
                    systemImage: event.audience.systemImage,
                    text: event.audience.title.uppercased()
                )
                if let ageText = eventAgeRestrictionText(for: event) {
                    ContentMetadataPill(systemImage: "birthday.cake", text: ageText.uppercased())
                }
            }
        }

        func eventAgeRestrictionText(for event: Event) -> String? {
            switch (event.minimumAge, event.maximumAge) {
            case let (minimum?, maximum?): "\(minimum)–\(maximum) \(AppStrings.Events.ageYearsShort)"
            case let (minimum?, nil): "\(minimum)+ \(AppStrings.Events.ageYearsShort)"
            case let (nil, maximum?): "0–\(maximum) \(AppStrings.Events.ageYearsShort)"
            case (nil, nil): nil
            }
        }

        func metadataRow(for event: Event) -> some View {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    metadataItems(for: event)
                }

                VStack(alignment: .leading, spacing: 7) {
                    metadataItems(for: event)
                }
            }
        }

        func metadataItems(for event: Event) -> some View {
            Group {
                AppMetadataLine(title: LocalizationStore.dateString(from: event.startDate, dateStyle: .medium, timeStyle: .none), systemImage: "calendar")
                AppMetadataLine(title: LocalizationStore.timeRangeString(startDate: event.startDate, endDate: event.endDate), systemImage: "clock")
                AppMetadataLine(title: eventViewCountText(for: event), systemImage: "eye")
            }
        }

        func eventHeroImage(imageURL: String, size: CGFloat?) -> some View {
            RemoteImageView(
                imageURL: imageURL,
                height: size ?? detailImageHeight,
                cornerRadius: AppTheme.imageRadius,
                source: "EventDetailView",
                placeholderStyle: .glassSkeleton
            )
            .frame(width: size, height: size)
            .frame(minHeight: size == nil ? detailImageHeight : nil, maxHeight: size == nil ? detailImageHeight : nil)
            .frame(maxWidth: size == nil ? .infinity : size)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                    .strokeBorder(AppTheme.glassBorder(for: colorScheme).opacity(0.78))
            )
            .shadow(color: AppTheme.glassShadow(for: colorScheme).opacity(0.55), radius: 8, y: 4)
        }

        func eventImageURL(for event: Event) -> String? {
            guard let imageURL = event.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !imageURL.isEmpty else {
                return nil
            }
            return imageURL
        }

        func eventDetailCategoryTitle(for category: EventCategory) -> String {
            switch category {
            case .unspecified:
                AppStrings.Events.genericEventBadge
            case .meetups:
                AppStrings.Events.categoryMeetupSingular
            default:
                category.title
            }
        }

        func leadBlock(for event: Event) -> some View {
            DetailCard {
                HStack(alignment: .top, spacing: AppTheme.dashboardSpacing) {
                    Image(systemName: "info.circle")
                        .font(AppTheme.sectionTitleFont)
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppStrings.Events.aboutSectionTitle)
                            .font(AppTheme.sectionTitleFont)
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(event.summary)
                            .font(AppTheme.cardSubtitleFont)
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
}
