import Combine
import MapKit
import PhotosUI
import SwiftUI
import UIKit

struct EventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: EventEditorViewModel
    @StateObject private var locationSearch = EventLocationSearchViewModel()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isShowingMapPicker = false
    @State private var isApplyingLocationSelection = false
    @State private var activeDatePicker: EventEditorDatePicker?

    private let onPublished: @MainActor () async -> Void
    private let cardPadding: CGFloat = AppTheme.detailCompactCardPadding
    private let editorSpacing: CGFloat = AppTheme.detailSectionSpacing
    private let headerLogoSize = CGSize(width: 110, height: 39)
    private let organizerLogoSize: CGFloat = 48

    init(repository: EventRepository, onPublished: @escaping @MainActor () async -> Void = {}) {
        _viewModel = StateObject(wrappedValue: EventEditorViewModel(repository: repository, mode: .create()))
        self.onPublished = onPublished
    }

    init(
        repository: EventRepository,
        organizationId: String,
        organizationName: String,
        organizationImageURL: String?,
        organizationFederalState: AustrianFederalState? = nil,
        onPublished: @escaping @MainActor () async -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: EventEditorViewModel(
            repository: repository,
            mode: .create(context: .init(
                organizationId: organizationId,
                organizationName: organizationName,
                organizationImageURL: organizationImageURL,
                organizationFederalState: organizationFederalState
            ))
        ))
        self.onPublished = onPublished
    }

    init(repository: EventRepository, event: Event, onPublished: @escaping @MainActor () async -> Void = {}) {
        _viewModel = StateObject(wrappedValue: EventEditorViewModel(repository: repository, mode: .edit(existing: event)))
        self.onPublished = onPublished
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: editorSpacing) {
                editorHeader
                    .padding(.top, AppTheme.dashboardSpacing)

                editorTitleBlock
                statusContent
                mainCard
                imageCard
                dateTimeCard
                locationCard
                organizerCard
                categoryCard
                additionalSettingsCard
                publishNoticeCard
                bottomSubmitButton
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.bottom, AppTheme.homeBottomContentPadding)
        }
        .background(AppBackgroundView())
        .tint(AppTheme.accentPrimary)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $isShowingMapPicker) {
            EventMapPickerView(
                initialCoordinate: viewModel.selectedCoordinate,
                initialQuery: viewModel.locationSearchQuery
            ) { selection in
                applyLocation(selection)
            }
        }
        .sheet(item: $activeDatePicker) { picker in
            EventDatePickerSheet(
                title: picker.title,
                selection: dateBinding(for: picker),
                displayedComponents: picker.displayedComponents
            )
        }
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                await loadSelectedPhoto(item: newItem)
            }
        }
        .onChange(of: viewModel.venue) { _, newValue in
            guard !isApplyingLocationSelection else { return }
            viewModel.clearResolvedCoordinates()
            locationSearch.updateQuery(newValue)
        }
        .onChange(of: viewModel.address) { _, _ in
            guard !isApplyingLocationSelection else { return }
            viewModel.clearResolvedCoordinates()
        }
        .onChange(of: viewModel.city) { _, _ in
            guard !isApplyingLocationSelection else { return }
            viewModel.clearResolvedCoordinates()
        }
    }

    private var editorHeader: some View {
        ZStack {
            BrandMarkView(
                size: headerLogoSize.height,
                width: headerLogoSize.width,
                assetName: "logo1",
                contentMode: .fit
            )
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, minHeight: AppTheme.iconButtonSize)
        .overlay(alignment: .leading) {
            headerIconButton(systemImage: "chevron.left", accessibilityLabel: AppStrings.Common.back) {
                dismiss()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func headerIconButton(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: AppTheme.iconButtonSize, height: AppTheme.iconButtonSize)
                .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                        .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                )
                .shadow(color: AppTheme.glassShadow(for: colorScheme), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var editorTitleBlock: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsCardContentSpacing) {
            Text(viewModel.navigationTitle)
                .font(.title.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(AppStrings.Events.editorSubtitle)
                .font(.callout.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusContent: some View {
        if viewModel.isPublishing || viewModel.isUploadingImage || viewModel.isProcessingImage {
            editorStatusCard {
                Label(viewModel.isUploadingImage ? AppStrings.NewsEditor.uploadingImage : AppStrings.Events.publishing, systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accentPrimary)
            }
        }

        if let errorMessage = viewModel.errorMessage {
            editorStatusCard {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accentDestructive)
            }
        }

        if let successMessage = viewModel.successMessage {
            editorStatusCard {
                Label(successMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            }
        }

        if viewModel.requiresOrganizationRegionBeforePublishing {
            editorStatusCard {
                Label(AppStrings.Events.organizationRegionRequired, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accentDestructive)
            }
        }
    }

    private var statusMessage: String {
        if viewModel.isUploadingImage {
            return AppStrings.NewsEditor.uploadingImage
        }
        if viewModel.isProcessingImage {
            return AppStrings.NewsEditor.processingImage
        }
        return AppStrings.Events.publishing
    }

    private var bottomSubmitButton: some View {
        Button(action: submit) {
            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                if viewModel.isPublishing || viewModel.isUploadingImage {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }

                Text(viewModel.isPublishing || viewModel.isUploadingImage ? statusMessage : viewModel.primarySubmitButtonTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                    .fill(viewModel.canPublish ? AppTheme.accentPrimary : AppTheme.accentPrimary.opacity(0.26))
            )
            .shadow(color: AppTheme.accentPrimary.opacity(viewModel.canPublish ? 0.18 : 0), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canPublish || viewModel.isPublishing || viewModel.isUploadingImage)
        .accessibilityLabel(viewModel.primarySubmitButtonTitle)
    }

    private func submit() {
        Task {
            let didPublish = await viewModel.publish()
            guard didPublish else { return }
            await onPublished()
            dismiss()
        }
    }

    private var mainCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorField(title: AppStrings.Events.fieldTitle, counterText: "\(viewModel.title.count)/120") {
                    TextField(AppStrings.Events.titlePlaceholder, text: $viewModel.title)
                        .textInputAutocapitalization(.sentences)
                        .appEditorInputStyle()
                }

                AppEditorField(title: AppStrings.Events.fieldSummary) {
                    multilineInput(
                        placeholder: AppStrings.Events.summaryPlaceholder,
                        text: $viewModel.summary,
                        minHeight: 88,
                        counterText: "\(viewModel.summary.count)/200"
                    )
                }

                AppEditorField(title: AppStrings.Events.fieldDetails) {
                    multilineInput(
                        placeholder: AppStrings.Events.detailsPlaceholder,
                        text: $viewModel.details,
                        minHeight: 132,
                        counterText: "\(viewModel.details.count)/2000"
                    )
                }
            }
        }
    }

    private var imageCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.Events.imageSectionTitle)

                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    imagePickerContent
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isProcessingImage || viewModel.isPublishing)
                .accessibilityLabel(AppStrings.Events.imageSectionTitle)
            }
        }
    }

    @ViewBuilder
    private var imagePickerContent: some View {
        if let selectedImageData = viewModel.selectedImageData,
           let image = UIImage(data: selectedImageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                        .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                )
        } else if let existingImageURL = viewModel.existingImageURL {
            RemoteImageView(
                imageURL: existingImageURL,
                height: 150,
                cornerRadius: AppTheme.imageRadius,
                source: "EventEditorView",
                placeholderStyle: .glassSkeleton
            )
        } else {
            compactUploadPlaceholder
        }
    }

    private var dateTimeCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                AppEditorSectionTitle(title: AppStrings.Events.dateSectionTitle)
                EventDatePickerRow(systemImage: "calendar", title: AppStrings.Events.fieldStartDate, value: dateValue(viewModel.startDate)) {
                    activeDatePicker = .startDate
                }
                if !viewModel.isAllDay {
                    editorDivider
                    EventDatePickerRow(systemImage: "clock", title: AppStrings.Events.startTime, value: timeValue(viewModel.startDate)) {
                        activeDatePicker = .startTime
                    }
                }
                editorDivider
                EventDatePickerRow(systemImage: "calendar", title: AppStrings.Events.fieldEndDate, value: dateValue(viewModel.endDate)) {
                    activeDatePicker = .endDate
                }
                if !viewModel.isAllDay {
                    editorDivider
                    EventDatePickerRow(systemImage: "clock", title: AppStrings.Events.endTime, value: timeValue(viewModel.endDate)) {
                        activeDatePicker = .endTime
                    }
                }
                editorDivider
                allDayRow
            }
        }
    }

    private var locationCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.Events.fieldLocation)

                iconTextField(systemImage: "mappin.circle", placeholder: AppStrings.Events.locationPlaceholder, text: $viewModel.venue)

                locationSuggestions

                AppEditorField(title: AppStrings.Events.addressPlaceholder) {
                    TextField(AppStrings.Events.addressPlaceholder, text: $viewModel.address)
                        .textInputAutocapitalization(.words)
                        .appEditorInputStyle()
                }

                AppEditorField(title: AppStrings.Common.city) {
                    TextField(AppStrings.Common.city, text: $viewModel.city)
                        .textInputAutocapitalization(.words)
                        .appEditorInputStyle()
                }

                AppEditorField(title: AppStrings.Events.locationNoteTitle) {
                    multilineInput(
                        placeholder: AppStrings.Events.locationNotePlaceholder,
                        text: $viewModel.locationNote,
                        minHeight: 76,
                        counterText: "\(viewModel.locationNote.count)/160"
                    )
                }

                if viewModel.selectedCoordinate != nil || !viewModel.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    selectedLocationRow
                }

                mapPickerButton
            }
        }
    }

    @ViewBuilder
    private var locationSuggestions: some View {
        if !locationSearch.completions.isEmpty && !viewModel.venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let visibleCompletions = Array(locationSearch.completions.prefix(5))
            VStack(spacing: 0) {
                ForEach(Array(visibleCompletions.enumerated()), id: \.offset) { index, completion in
                    Button {
                        Task {
                            guard let selection = await locationSearch.resolve(completion) else { return }
                            applyLocation(selection)
                            locationSearch.clear()
                        }
                    } label: {
                        locationSuggestionRow(title: completion.title, subtitle: completion.subtitle)
                    }
                    .buttonStyle(.plain)

                    if index < visibleCompletions.count - 1 {
                        editorDivider
                    }
                }
            }
            .padding(.vertical, 4)
            .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                    .strokeBorder(AppTheme.glassBorder(for: colorScheme))
            )
        }
    }

    private func locationSuggestionRow(title: String, subtitle: String) -> some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: AppTheme.eventsMetadataSpacing)
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(minHeight: 48)
    }

    private var selectedLocationRow: some View {
        HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            VStack(alignment: .leading, spacing: 3) {
                Text(AppStrings.Events.selectedLocation)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                Text(selectedLocationText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
            }

            Spacer(minLength: AppTheme.eventsMetadataSpacing)
        }
        .padding(AppTheme.inputHorizontalPadding)
        .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
    }

    private var selectedLocationText: String {
        [viewModel.venue, viewModel.address, viewModel.city]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private var mapPickerButton: some View {
        Button {
            isShowingMapPicker = true
        } label: {
            Label(AppStrings.Events.chooseOnMap, systemImage: "map")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.searchControlHeight)
                .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                        .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                )
        }
        .buttonStyle(.plain)
    }

    private var organizerCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.Events.editorOrganizerSectionTitle)

                HStack(spacing: AppTheme.dashboardSpacing) {
                    AppFeedThumbnail(
                        imageURL: viewModel.organizerImageURL,
                        fallbackSystemImage: "building.2",
                        tint: AppTheme.accentPrimary,
                        fill: AppTheme.accentPrimarySoft,
                        size: organizerLogoSize,
                        cornerRadius: AppTheme.feedThumbnailRadius,
                        source: "EventEditorOrganizer"
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.organizerName ?? AppStrings.Home.brandTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)

                        AppInfoChip(
                            title: viewModel.organizerName == nil ? AppStrings.Tabs.events : AppStrings.Organizations.detailBadge,
                            systemImage: "building.2",
                            tint: AppTheme.accentPrimary,
                            fill: AppTheme.accentPrimarySoft,
                            size: .small
                        )
                    }

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    Label(AppStrings.Common.notAvailable, systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
                        .labelStyle(.iconOnly)
                        .frame(width: 32, height: 32)
                        .background(AppTheme.glassControlSurface(for: colorScheme), in: Circle())
                }
            }
        }
    }

    private var categoryCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.Events.categorySectionTitle)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.eventsMetadataSpacing) {
                        ForEach(EventCategory.allCases) { category in
                            EventEditorCategoryChip(category: category, isSelected: viewModel.selectedCategory == category) {
                                viewModel.selectedCategory = category
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .clipShape(Rectangle())
            }
        }
    }

    private var additionalSettingsCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                AppEditorSectionTitle(title: AppStrings.Events.additionalSettingsTitle)
                if viewModel.showsRegionPicker {
                    regionPickerRow
                    editorDivider
                }
                priceRow
                editorDivider
                capacityRow
            }
        }
    }

    private var regionPickerRow: some View {
        Menu {
            ForEach(AustrianFederalState.allCases) { federalState in
                Button(federalState.displayName) {
                    viewModel.selectedFederalState = federalState
                }
            }
        } label: {
            settingsRow(
                systemImage: "map",
                title: AppStrings.NewsEditor.regionSectionTitle,
                value: viewModel.selectedFederalState.displayName,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
    }

    private var priceRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: AppTheme.dashboardSpacing) {
                Image(systemName: "eurosign.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                Text(AppStrings.Events.priceTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer(minLength: AppTheme.eventsMetadataSpacing)

                TextField(AppStrings.Events.pricePlaceholder, text: $viewModel.priceText)
                    .keyboardType(.decimalPad)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 112)
            }
            .frame(minHeight: 44)

            Text(AppStrings.Events.priceHelper)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.78))
                .padding(.leading, AppTheme.metadataIconSize + AppTheme.dashboardSpacing)
        }
    }

    private var capacityRow: some View {
        HStack(spacing: AppTheme.dashboardSpacing) {
            Image(systemName: "person.2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            Text(AppStrings.Events.maxParticipantsTitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer(minLength: AppTheme.eventsMetadataSpacing)

            TextField(AppStrings.Events.unlimitedParticipants, text: $viewModel.capacityText)
                .keyboardType(.numberPad)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 112)
        }
        .frame(minHeight: 48)
    }

    private var publishNoticeCard: some View {
        HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            Text(AppStrings.Events.publishNotice)
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(3)
        }
        .padding(AppTheme.detailCompactCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceGlass, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private func editorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        SoftContentCard(padding: cardPadding) {
            content()
        }
    }

    private func editorStatusCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        SoftContentCard(padding: AppTheme.dashboardSpacing) {
            content()
        }
    }

    private var editorDivider: some View {
        Rectangle()
            .fill(AppTheme.borderSubtle)
            .frame(height: 1)
            .padding(.leading, AppTheme.metadataIconSize + AppTheme.dashboardSpacing)
    }

    private func multilineInput(placeholder: String, text: Binding<String>, minHeight: CGFloat, counterText: String) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
                    .padding(.horizontal, AppTheme.inputHorizontalPadding)
                    .padding(.vertical, 13)
            }

            TextEditor(text: text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal, AppTheme.inputHorizontalPadding - 5)
                .padding(.vertical, 5)
                .frame(minHeight: minHeight, alignment: .topLeading)

            Text(counterText)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, AppTheme.inputHorizontalPadding)
                .padding(.bottom, 10)
        }
        .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme))
        )
    }

    private var allDayRow: some View {
        HStack(spacing: AppTheme.dashboardSpacing) {
            Image(systemName: "sun.max")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            Text(AppStrings.Events.allDay)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer(minLength: AppTheme.eventsMetadataSpacing)

            Toggle("", isOn: $viewModel.isAllDay)
                .labelsHidden()
        }
        .frame(minHeight: 48)
    }

    private var compactUploadPlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.badge.plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)

            Text(AppStrings.Events.coverUploadTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(AppStrings.Events.coverUploadHelper)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                .stroke(AppTheme.glassBorder(for: colorScheme), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        )
    }

    private func dateValue(_ date: Date) -> String {
        LocalizationStore.dateString(from: date, dateStyle: .medium, timeStyle: .none)
    }

    private func timeValue(_ date: Date) -> String {
        LocalizationStore.dateString(from: date, dateStyle: .none, timeStyle: .short)
    }

    private func iconTextField(systemImage: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            TextField(placeholder, text: text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .textInputAutocapitalization(.words)
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(height: AppTheme.searchControlHeight)
        .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme))
        )
    }

    private func disabledWideButton(systemImage: String, title: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.searchControlHeight)
            .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                    .strokeBorder(AppTheme.glassBorder(for: colorScheme))
            )
            .opacity(0.66)
            .accessibilityHint(AppStrings.Action.comingSoon)
    }

    private func disabledSettingsRow(systemImage: String, title: String, value: String) -> some View {
        settingsRow(systemImage: systemImage, title: title, value: value, showsChevron: false)
            .opacity(0.68)
            .accessibilityHint(AppStrings.Action.comingSoon)
    }

    private func settingsRow(systemImage: String, title: String, value: String, showsChevron: Bool) -> some View {
        HStack(spacing: AppTheme.dashboardSpacing) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer(minLength: AppTheme.eventsMetadataSpacing)

            if !value.isEmpty {
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
            }
        }
    }

    private func applyLocation(_ selection: EventLocationSelection) {
        isApplyingLocationSelection = true
        locationSearch.clear()
        viewModel.applyLocation(
            venueName: selection.name,
            address: selection.address,
            city: selection.city,
            federalState: selection.federalState,
            latitude: selection.coordinate?.latitude,
            longitude: selection.coordinate?.longitude
        )
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            isApplyingLocationSelection = false
        }
    }

    private func dateBinding(for picker: EventEditorDatePicker) -> Binding<Date> {
        switch picker {
        case .startDate, .startTime:
            $viewModel.startDate
        case .endDate, .endTime:
            $viewModel.endDate
        }
    }

    private func loadSelectedPhoto(item: PhotosPickerItem?) async {
        guard let item else {
            await MainActor.run {
                viewModel.setImageProcessing(false)
                viewModel.setSelectedImageData(nil)
            }
            return
        }

        await MainActor.run {
            viewModel.setImageProcessing(true)
        }

        do {
            let data = try await item.loadTransferable(type: Data.self)
            guard let data else {
                await MainActor.run {
                    selectedPhoto = nil
                    viewModel.setImageProcessing(false)
                    viewModel.setSelectedImageData(nil)
                    viewModel.errorMessage = AppStrings.NewsEditor.imageLoadFailed
                }
                return
            }

            await MainActor.run {
                viewModel.setImageProcessing(false)
                viewModel.setSelectedImageData(data)
            }
        } catch {
            await MainActor.run {
                selectedPhoto = nil
                viewModel.setImageProcessing(false)
                viewModel.setSelectedImageData(nil)
                viewModel.errorMessage = AppStrings.NewsEditor.imageLoadFailed
            }
        }
    }
}

private extension AustrianFederalState {
    var displayName: String {
        switch self {
        case .burgenland:
            "Burgenland"
        case .kaernten:
            "Kärnten"
        case .niederoesterreich:
            "Niederösterreich"
        case .oberoesterreich:
            "Oberösterreich"
        case .salzburg:
            "Salzburg"
        case .steiermark:
            "Steiermark"
        case .tirol:
            "Tirol"
        case .vorarlberg:
            "Vorarlberg"
        case .wien:
            "Wien"
        }
    }
}

private enum EventEditorDatePicker: Identifiable {
    case startDate
    case startTime
    case endDate
    case endTime

    var id: String {
        switch self {
        case .startDate:
            "startDate"
        case .startTime:
            "startTime"
        case .endDate:
            "endDate"
        case .endTime:
            "endTime"
        }
    }

    var title: String {
        switch self {
        case .startDate:
            AppStrings.Events.fieldStartDate
        case .startTime:
            AppStrings.Events.startTime
        case .endDate:
            AppStrings.Events.fieldEndDate
        case .endTime:
            AppStrings.Events.endTime
        }
    }

    var displayedComponents: DatePickerComponents {
        switch self {
        case .startDate, .endDate:
            .date
        case .startTime, .endTime:
            .hourAndMinute
        }
    }
}

private struct EventDatePickerRow: View {
    let systemImage: String
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: AppTheme.dashboardSpacing) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer(minLength: AppTheme.eventsMetadataSpacing)

                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 48)
    }
}

private struct EventDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var selection: Date
    let displayedComponents: DatePickerComponents

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker(title, selection: $selection, displayedComponents: displayedComponents)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .padding(.top, AppTheme.sectionSpacing)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .background(AppBackgroundView())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.Common.done) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
    }
}

private struct EventEditorCategoryChip: View {
    let category: EventCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(category.title, systemImage: category.systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isSelected ? AppTheme.accentPrimary : AppTheme.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    (isSelected ? AppTheme.accentPrimarySoft : AppTheme.surfaceGlass),
                    in: Capsule(style: .continuous)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? AppTheme.accentPrimary.opacity(0.12) : AppTheme.borderSubtle)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct EventLocationSelection: Identifiable {
    let id = UUID()
    let name: String
    let address: String?
    let city: String?
    let federalState: AustrianFederalState?
    let coordinate: CLLocationCoordinate2D?

    var subtitle: String {
        [address, city]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    init(mapItem: MKMapItem) {
        let placemark = mapItem.placemark
        self.name = mapItem.name?.nilIfEmpty ?? placemark.name?.nilIfEmpty ?? AppStrings.Events.selectedLocation
        self.address = EventLocationSelection.formattedAddress(from: placemark)
        self.city = placemark.locality?.nilIfEmpty ?? placemark.subAdministrativeArea?.nilIfEmpty
        self.federalState = AustrianFederalState(administrativeArea: placemark.administrativeArea)
        self.coordinate = placemark.coordinate
    }

    init(name: String, coordinate: CLLocationCoordinate2D?) {
        self.name = name
        self.address = nil
        self.city = nil
        self.federalState = nil
        self.coordinate = coordinate
    }

    private static func formattedAddress(from placemark: MKPlacemark) -> String? {
        let street = [placemark.thoroughfare, placemark.subThoroughfare]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: " ")
        let locality = [placemark.postalCode, placemark.locality]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: " ")
        let address = [street.nilIfEmpty, locality.nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: ", ")
        return address.nilIfEmpty
    }
}

@MainActor
private final class EventLocationSearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    @Published private(set) var isSearching = false

    private let completer = MKLocalSearchCompleter()
    private var debounceTask: Task<Void, Never>?

    override init() {
        super.init()
        completer.delegate = self
        completer.region = Self.austriaRegion
        completer.resultTypes = [.address, .pointOfInterest]
    }

    deinit {
        debounceTask?.cancel()
    }

    func updateQuery(_ query: String) {
        debounceTask?.cancel()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 2 else {
            clear()
            return
        }

        isSearching = true
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.completer.queryFragment = trimmedQuery
            }
        }
    }

    func clear() {
        debounceTask?.cancel()
        completer.queryFragment = ""
        completions = []
        isSearching = false
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> EventLocationSelection? {
        let request = MKLocalSearch.Request(completion: completion)
        request.region = Self.austriaRegion

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let mapItem = response.mapItems.first else { return nil }
            return EventLocationSelection(mapItem: mapItem)
        } catch {
            return nil
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            completions = completer.results
            isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            completions = []
            isSearching = false
        }
    }

    static let austriaRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 47.6965, longitude: 13.3457),
        span: MKCoordinateSpan(latitudeDelta: 5.1, longitudeDelta: 9.8)
    )
}

private struct EventMapPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var search = EventLocationSearchViewModel()
    @State private var query: String
    @State private var selection: EventLocationSelection?

    private let initialCoordinate: CLLocationCoordinate2D?
    private let onSelect: (EventLocationSelection) -> Void

    init(
        initialCoordinate: CLLocationCoordinate2D?,
        initialQuery: String,
        onSelect: @escaping (EventLocationSelection) -> Void
    ) {
        self.initialCoordinate = initialCoordinate
        self.onSelect = onSelect
        _query = State(initialValue: initialQuery)
        if let initialCoordinate {
            _selection = State(initialValue: EventLocationSelection(name: initialQuery.nilIfEmpty ?? AppStrings.Events.selectedLocation, coordinate: initialCoordinate))
        } else {
            _selection = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.dashboardSpacing) {
                mapSearchField

                if !search.completions.isEmpty {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            let visibleCompletions = Array(search.completions.prefix(6))
                            ForEach(Array(visibleCompletions.enumerated()), id: \.offset) { index, completion in
                                Button {
                                    Task {
                                        guard let resolvedSelection = await search.resolve(completion) else { return }
                                        selection = resolvedSelection
                                    }
                                } label: {
                                    mapSearchResultRow(title: completion.title, subtitle: completion.subtitle)
                                }
                                .buttonStyle(.plain)

                                if index < visibleCompletions.count - 1 {
                                    Rectangle()
                                        .fill(AppTheme.borderSubtle)
                                        .frame(height: 1)
                                        .padding(.leading, AppTheme.metadataIconSize + AppTheme.dashboardSpacing + AppTheme.inputHorizontalPadding)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 250)
                    .background(AppTheme.surfaceGlass, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !search.isSearching {
                    Text(AppStrings.Events.noLocationResults)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                EventMapView(selection: selection, fallbackCoordinate: initialCoordinate)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                            .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                    )

                Button {
                    guard let selection else { return }
                    onSelect(selection)
                    dismiss()
                } label: {
                    Text(AppStrings.Events.selectLocation)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.searchControlHeight)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                                .fill(selection == nil ? AppTheme.accentPrimary.opacity(0.28) : AppTheme.accentPrimary)
                        )
                }
                .buttonStyle(.plain)
                .disabled(selection == nil)
            }
            .padding(AppTheme.pageHorizontal)
            .background(AppBackgroundView())
            .navigationTitle(AppStrings.Events.chooseOnMap)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Common.cancel) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                search.updateQuery(query)
            }
            .onChange(of: query) { _, newValue in
                search.updateQuery(newValue)
            }
        }
    }

    private var mapSearchField: some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            TextField(AppStrings.Events.searchLocation, text: $query)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .textInputAutocapitalization(.words)
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(height: AppTheme.searchControlHeight)
        .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme))
        )
    }

    private func mapSearchResultRow(title: String, subtitle: String) -> some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: "mappin.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: AppTheme.eventsMetadataSpacing)
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(minHeight: 48)
    }
}

private struct EventMapView: UIViewRepresentable {
    let selection: EventLocationSelection?
    let fallbackCoordinate: CLLocationCoordinate2D?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.isRotateEnabled = false
        mapView.pointOfInterestFilter = .includingAll
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeAnnotations(mapView.annotations)

        let coordinate = selection?.coordinate
            ?? fallbackCoordinate
            ?? EventLocationSearchViewModel.austriaRegion.center
        let span = selection?.coordinate == nil && fallbackCoordinate == nil
            ? EventLocationSearchViewModel.austriaRegion.span
            : MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)

        mapView.setRegion(MKCoordinateRegion(center: coordinate, span: span), animated: true)

        if selection?.coordinate != nil || fallbackCoordinate != nil {
            let annotation = MKPointAnnotation()
            annotation.coordinate = coordinate
            annotation.title = selection?.name
            annotation.subtitle = selection?.subtitle
            mapView.addAnnotation(annotation)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    NavigationStack {
        EventEditorView(repository: MockEventRepository())
    }
}
