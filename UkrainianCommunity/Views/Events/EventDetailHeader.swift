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
                    accessibilityLabel: AppStrings.Action.save,
                    isDisabled: viewModel.pendingEventBookmarkIDs.contains(event.id)
                ) {
                    handleBookmark(for: event)
                }

                DetailHeaderActionButton(
                    systemImage: "square.and.arrow.up",
                    accessibilityLabel: AppStrings.Action.share
                ) {
                    sharePayload = EventSharePayload(event: event)
                }
            }
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
            ContentMetadataPill(
                systemImage: event.category.systemImage,
                text: eventDetailCategoryTitle(for: event.category).uppercased()
            )
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
            case .training:
                AppStrings.Events.categoryTraining
            case .culture:
                AppStrings.Events.categoryCulture
            case .education:
                AppStrings.Events.categoryEducation
            case .other:
                AppStrings.Events.categoryOther
            }
        }

        func leadBlock(for event: Event) -> some View {
            DetailCard {
                HStack(alignment: .top, spacing: AppTheme.dashboardSpacing) {
                    Image(systemName: "info.circle")
                        .font(AppTheme.sectionTitleFont)
                        .foregroundStyle(AppTheme.accentPrimary)
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
