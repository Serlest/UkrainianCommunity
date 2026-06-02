import PhotosUI
import SwiftUI
import UIKit

struct FeaturedBannerEditorView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: FeaturedBannerEditorViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedPreviewImage: UIImage?
    @State private var cropSourceImage: UIImage?
    @State private var isShowingImageCrop = false
    @State private var ignoresNextPhotoClear = false
    @State private var imageProcessingTask: Task<Void, Never>?
    @State private var imageProcessingToken = UUID()
    @State private var isShowingActionTargetPicker = false
    @State private var actionTargetSearchText = ""
    let onSave: @MainActor () async -> Void

    init(
        repository: FeaturedBannerRepository,
        mode: FeaturedBannerEditorViewModel.Mode = .create,
        newsRepository: NewsRepository? = nil,
        eventRepository: EventRepository? = nil,
        organizationRepository: OrganizationRepository? = nil,
        onSave: @escaping @MainActor () async -> Void
    ) {
        _viewModel = StateObject(wrappedValue: FeaturedBannerEditorViewModel(
            repository: repository,
            mode: mode,
            newsRepository: newsRepository,
            eventRepository: eventRepository,
            organizationRepository: organizationRepository
        ))
        self.onSave = onSave
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    AppCenteredBrandHeader {
                        AppGlassIconButton(systemImage: "chevron.left", accessibilityLabel: AppStrings.Common.back) {
                            dismiss()
                        }
                    } trailingContent: {
                        EmptyView()
                    }

                    SectionHeaderBlock(
                        title: viewModel.navigationTitle,
                        subtitle: AppStrings.FeaturedEditor.subtitle
                    )

                    statusContent
                    basicsCard
                    imageCard
                    targetingCard
                    actionCard
                    schedulingCard

                    Spacer(minLength: AppTheme.iconButtonSize + AppTheme.sectionSpacing)
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.sectionSpacing)
                .padding(.bottom, AppTheme.homeBottomContentPadding + 72)
            }
        }
        .safeAreaInset(edge: .bottom) {
            saveBar
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .tint(AppTheme.accentPrimary)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: selectedPhoto) { _, newItem in
            if newItem == nil, ignoresNextPhotoClear {
                ignoresNextPhotoClear = false
                return
            }
            imageProcessingTask?.cancel()
            let token = UUID()
            imageProcessingToken = token
            imageProcessingTask = Task {
                await loadSelectedPhoto(item: newItem, token: token)
            }
        }
        .onChange(of: viewModel.actionType) { oldValue, newValue in
            actionTargetSearchText = ""
            viewModel.handleActionTypeChanged(from: oldValue, to: newValue)
            Task {
                await viewModel.loadActionTargetsIfNeeded()
            }
        }
        .onDisappear {
            imageProcessingTask?.cancel()
        }
        .sheet(isPresented: $isShowingImageCrop, onDismiss: resetCropSelection) {
            if let cropSourceImage {
                ImageCropView(
                    sourceImage: cropSourceImage,
                    profile: .hero16x9,
                    title: AppStrings.Images.Crop.title,
                    instructions: AppStrings.FeaturedEditor.cropInstructions,
                    onCancel: {},
                    onApply: applyCroppedImage(_:)
                )
            }
        }
        .sheet(isPresented: $isShowingActionTargetPicker) {
            FeaturedBannerActionTargetPickerSheet(
                viewModel: viewModel,
                searchText: $actionTargetSearchText,
                onSelect: { item in
                    viewModel.selectActionTarget(item)
                    isShowingActionTargetPicker = false
                }
            )
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        if let message = viewModel.errorMessage {
            InlineMessageCard(style: .error, message: message)
        } else if let message = viewModel.successMessage {
            InlineMessageCard(style: .success, message: message)
        } else if let validationMessage = viewModel.validationMessage {
            InlineMessageCard(style: .info, message: validationMessage)
        }
    }

    private var basicsCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.FeaturedEditor.basicsSection)
                EditorTextField(AppStrings.FeaturedEditor.internalNameField, text: $viewModel.internalName, systemImage: "tag")
                EditorTextField(AppStrings.FeaturedEditor.titleField, text: $viewModel.title, systemImage: "textformat")
                EditorTextField(AppStrings.FeaturedEditor.subtitleField, text: $viewModel.subtitle, systemImage: "text.alignleft")

                Toggle(isOn: $viewModel.isActive) {
                    Text(AppStrings.FeaturedManagement.activeToggle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
        }
    }

    private var imageCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.FeaturedEditor.imageSection)

                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    imagePickerContent
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isProcessingImage || viewModel.isSaving)
                .overlay {
                    if viewModel.isProcessingImage {
                        imageProcessingOverlay
                    }
                }

                Text(AppStrings.FeaturedEditor.imageHelper)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var imagePickerContent: some View {
        if let selectedPreviewImage {
            Rectangle()
                .fill(AppTheme.glassControlSurface(for: colorScheme).opacity(0.72))
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    Image(uiImage: selectedPreviewImage)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous)
                        .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                )
        } else if let existingImageURL = viewModel.existingImageURL {
            RemoteImageView(
                imageURL: existingImageURL,
                height: AppTheme.heroBannerHeight,
                cornerRadius: AppTheme.heroRadius,
                source: "FeaturedBannerEditorView",
                placeholderStyle: .glassSkeleton
            )
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                Text(AppStrings.FeaturedEditor.replaceImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
                    .padding(.vertical, AppTheme.eventsMetadataSpacing)
                    .background(.black.opacity(0.48), in: Capsule())
                    .padding(AppTheme.dashboardSpacing)
            }
        } else {
            uploadPlaceholder
        }
    }

    private var imageProcessingOverlay: some View {
        ProgressView()
            .controlSize(.regular)
            .tint(AppTheme.accentPrimary)
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
            .allowsHitTesting(false)
    }

    private var uploadPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)

            Text(AppStrings.FeaturedEditor.uploadImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(AppStrings.FeaturedEditor.uploadImageHelper)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .background(AppTheme.glassControlSurface(for: colorScheme).opacity(0.72), in: RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous)
                .stroke(AppTheme.glassBorder(for: colorScheme).opacity(0.82), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        )
    }

    private var targetingCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.FeaturedEditor.targetingSection)

                Picker(AppStrings.FeaturedEditor.regionScopeField, selection: $viewModel.regionScope) {
                    ForEach(FeaturedBannerRegionScope.allCases) { scope in
                        Text(scope.editorTitle).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.regionScope == .federalState {
                    Picker(AppStrings.FeaturedEditor.federalStateField, selection: $viewModel.federalState) {
                        Text(AppStrings.FeaturedEditor.selectFederalState).tag(Optional<AustrianFederalState>.none)
                        ForEach(AustrianFederalState.allCases) { federalState in
                            Text(AppStrings.FederalStates.title(for: federalState)).tag(Optional(federalState))
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    Text(AppStrings.FeaturedEditor.visibleSectionsField)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    ForEach(FeaturedBannerVisibleSection.allCases) { section in
                        Toggle(isOn: Binding(
                            get: { viewModel.visibleSections.contains(section) },
                            set: { viewModel.toggleVisibleSection(section, isVisible: $0) }
                        )) {
                            Text(section.editorTitle)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    private var actionCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.FeaturedEditor.actionSection)

                Picker(AppStrings.FeaturedEditor.actionTypeField, selection: $viewModel.actionType) {
                    ForEach(FeaturedBannerActionType.allCases) { actionType in
                        Text(actionType.editorTitle).tag(actionType)
                    }
                }
                .pickerStyle(.menu)

                Text(viewModel.actionType.editorHelperText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if viewModel.requiresActionTarget {
                    if viewModel.supportsActionTargetPicker {
                        FeaturedBannerActionTargetSelectionField(
                            kind: viewModel.actionTargetPickerKind,
                            selectedItem: viewModel.selectedActionTargetItem,
                            targetID: viewModel.actionTargetID,
                            isLoading: viewModel.isLoadingCurrentActionTargets,
                            onSelect: {
                                actionTargetSearchText = ""
                                isShowingActionTargetPicker = true
                            },
                            onClear: {
                                viewModel.actionTargetID = ""
                            }
                        )
                        .task {
                            await viewModel.loadActionTargetsIfNeeded()
                        }
                    } else {
                        EditorTextField(
                            AppStrings.FeaturedEditor.actionTargetField,
                            text: $viewModel.actionTargetID,
                            systemImage: "number",
                            autocapitalization: .never,
                            autocorrectionDisabled: true
                        )
                        Text(AppStrings.FeaturedEditor.manualTargetHelper)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if viewModel.requiresExternalURL {
                    EditorTextField(
                        AppStrings.FeaturedEditor.externalURLField,
                        text: $viewModel.externalURL,
                        systemImage: "link",
                        keyboardType: .URL,
                        autocapitalization: .never,
                        autocorrectionDisabled: true
                    )
                }
            }
        }
    }

    private var schedulingCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.FeaturedEditor.schedulingSection)

                Stepper(value: $viewModel.displayDurationSeconds, in: FeaturedBannerValidationService.displayDurationBounds) {
                    FeaturedEditorValueRow(
                        title: AppStrings.FeaturedEditor.durationField,
                        value: AppStrings.FeaturedEditor.durationValue(viewModel.displayDurationSeconds),
                        systemImage: "timer"
                    )
                }

                Stepper(value: $viewModel.priority, in: 0...1000) {
                    FeaturedEditorValueRow(
                        title: AppStrings.FeaturedEditor.priorityField,
                        value: "\(viewModel.priority)",
                        systemImage: "list.number"
                    )
                }

                Toggle(isOn: $viewModel.hasStartDate) {
                    Text(AppStrings.FeaturedEditor.startsAtEnabled)
                        .font(.subheadline.weight(.semibold))
                }

                if viewModel.hasStartDate {
                    DatePicker(AppStrings.FeaturedEditor.startsAtField, selection: $viewModel.startsAt)
                        .datePickerStyle(.compact)
                }

                Toggle(isOn: $viewModel.hasEndDate) {
                    Text(AppStrings.FeaturedEditor.endsAtEnabled)
                        .font(.subheadline.weight(.semibold))
                }

                if viewModel.hasEndDate {
                    DatePicker(AppStrings.FeaturedEditor.endsAtField, selection: $viewModel.endsAt)
                        .datePickerStyle(.compact)
                }
            }
        }
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            PrimaryActionButton(
                title: viewModel.saveButtonTitle,
                loadingTitle: AppStrings.FeaturedEditor.saving,
                isEnabled: viewModel.canSave,
                isLoading: viewModel.isSaving,
                systemImage: "checkmark"
            ) {
                Task {
                    let didSave = await viewModel.save(updatedBy: authState.user?.id)
                    guard didSave else { return }
                    await onSave()
                    dismiss()
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.top, AppTheme.eventsMetadataSpacing)
            .padding(.bottom, AppTheme.eventsMetadataSpacing)
            .background(.ultraThinMaterial)
        }
    }

    private func loadSelectedPhoto(item: PhotosPickerItem?, token: UUID) async {
        guard let item else {
            await MainActor.run {
                guard imageProcessingToken == token else { return }
                viewModel.setImageProcessing(false)
                viewModel.setSelectedImageData(nil)
                selectedPreviewImage = nil
            }
            return
        }

        await MainActor.run {
            guard imageProcessingToken == token else { return }
            viewModel.setImageProcessing(true)
        }

        do {
            let originalData = try await item.loadTransferable(type: Data.self)
            guard !Task.isCancelled else { return }
            guard let originalData else {
                await MainActor.run {
                    guard imageProcessingToken == token else { return }
                    selectedPhoto = nil
                    viewModel.setImageProcessing(false)
                    viewModel.errorMessage = AppStrings.FeaturedEditor.imageLoadFailed
                }
                return
            }

            guard let sourceImage = UIImage(data: originalData) else {
                throw ImageProcessingError.invalidImageData
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard imageProcessingToken == token else { return }
                cropSourceImage = sourceImage
                isShowingImageCrop = true
                viewModel.setImageProcessing(false)
                viewModel.errorMessage = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard imageProcessingToken == token else { return }
                selectedPhoto = nil
                viewModel.setImageProcessing(false)
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func applyCroppedImage(_ processedImage: ProcessedImageSelection) {
        guard let previewImage = UIImage(data: processedImage.data) else {
            viewModel.errorMessage = AppStrings.FeaturedEditor.imageLoadFailed
            return
        }

        selectedPreviewImage = previewImage
        viewModel.setSelectedImageSelection(processedImage)
        viewModel.errorMessage = nil
    }

    private func resetCropSelection() {
        cropSourceImage = nil
        guard selectedPhoto != nil else { return }
        ignoresNextPhotoClear = true
        selectedPhoto = nil
    }
}

private struct FeaturedEditorValueRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        Label {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer(minLength: AppTheme.eventsMetadataSpacing)
                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accentPrimary)
        }
    }
}

private struct FeaturedBannerActionTargetSelectionField: View {
    let kind: FeaturedBannerActionTargetKind?
    let selectedItem: FeaturedBannerActionTargetItem?
    let targetID: String
    let isLoading: Bool
    let onSelect: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    Image(systemName: kind?.systemImage ?? "arrow.up.forward.app")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                        .frame(width: AppTheme.metadataIconSize)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedItem?.title ?? AppStrings.FeaturedEditor.selectTarget)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedItem == nil ? AppTheme.textSecondary : AppTheme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if let subtitle = selectedItem?.subtitle ?? selectedItem?.metadata {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1)
                        } else if let rawID = nonEmpty(targetID) {
                            Text(AppStrings.FeaturedEditor.selectedTargetID(rawID))
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .padding(.horizontal, AppTheme.inputHorizontalPadding)
                .padding(.vertical, AppTheme.eventsMetadataSpacing)
                .frame(minHeight: AppTheme.newsEditorInputHeight)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                        .strokeBorder(AppTheme.borderSubtle)
                )
            }
            .buttonStyle(.plain)

            if selectedItem != nil || !targetID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(role: .destructive, action: onClear) {
                    Label(AppStrings.FeaturedEditor.clearTarget, systemImage: "xmark.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct FeaturedBannerActionTargetPickerSheet: View {
    @ObservedObject var viewModel: FeaturedBannerEditorViewModel
    @Binding var searchText: String
    let onSelect: (FeaturedBannerActionTargetItem) -> Void
    @Environment(\.dismiss) private var dismiss

    private var items: [FeaturedBannerActionTargetItem] {
        viewModel.actionTargetItems(matching: searchText)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingCurrentActionTargets && items.isEmpty {
                    LoadingStateCard(title: AppStrings.FeaturedEditor.loadingTargets)
                        .padding(AppTheme.pageHorizontal)
                } else if let error = viewModel.actionTargetLoadError, items.isEmpty {
                    ErrorStateCard(
                        systemImage: "arrow.up.forward.app",
                        title: AppStrings.FeaturedEditor.targetPickerTitle(viewModel.actionTargetPickerKind?.title ?? ""),
                        message: error,
                        retryTitle: AppStrings.Action.retry
                    ) {
                        Task { await viewModel.refreshActionTargets() }
                    }
                    .padding(AppTheme.pageHorizontal)
                } else if items.isEmpty {
                    EmptyStateCard(
                        systemImage: "magnifyingglass",
                        title: AppStrings.FeaturedEditor.noTargetsFound,
                        message: AppStrings.FeaturedEditor.noTargetsFoundMessage
                    )
                    .padding(AppTheme.pageHorizontal)
                } else {
                    List(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            FeaturedBannerActionTargetPickerRow(
                                item: item,
                                isSelected: viewModel.actionTargetID == item.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(AppStrings.FeaturedEditor.targetPickerTitle(viewModel.actionTargetPickerKind?.title ?? ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Action.cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(AppStrings.Action.retry) {
                        Task { await viewModel.refreshActionTargets() }
                    }
                    .disabled(viewModel.isLoadingCurrentActionTargets)
                }
            }
            .searchable(text: $searchText, prompt: AppStrings.FeaturedEditor.targetPickerSearch)
            .task {
                await viewModel.loadActionTargetsIfNeeded()
            }
        }
    }
}

private struct FeaturedBannerActionTargetPickerRow: View {
    let item: FeaturedBannerActionTargetItem
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.eventsControlGroupSpacing) {
            Image(systemName: item.kind.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: AppTheme.iconButtonSize, height: AppTheme.iconButtonSize)
                .background(AppTheme.badgeBlueFill, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }

                if let metadata = item.metadata {
                    Text(metadata)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.78))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: AppTheme.eventsMetadataSpacing)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.accentPrimary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private extension FeaturedBannerRegionScope {
    var editorTitle: String {
        switch self {
        case .allAustria:
            return AppStrings.Home.regionAllAustria
        case .federalState:
            return AppStrings.FeaturedEditor.regionScopeFederalState
        }
    }
}

private extension FeaturedBannerVisibleSection {
    var editorTitle: String {
        switch self {
        case .home:
            return AppStrings.Tabs.home
        case .events:
            return AppStrings.Tabs.events
        case .organizations:
            return AppStrings.Tabs.organizations
        case .guide:
            return AppStrings.Guide.title
        }
    }
}

private extension FeaturedBannerActionType {
    var editorHelperText: String {
        switch self {
        case .none:
            return AppStrings.FeaturedEditor.actionHelperNoTap
        case .news, .event, .organization, .guide:
            return AppStrings.FeaturedEditor.actionHelperTarget
        case .externalURL:
            return AppStrings.FeaturedEditor.actionHelperExternalURL
        }
    }

    var editorTitle: String {
        switch self {
        case .none:
            return AppStrings.FeaturedManagement.actionNone
        case .news:
            return AppStrings.News.title
        case .event:
            return AppStrings.Tabs.events
        case .organization:
            return AppStrings.Tabs.organizations
        case .guide:
            return AppStrings.Guide.title
        case .externalURL:
            return AppStrings.FeaturedManagement.actionExternalURL
        }
    }
}

#Preview {
    NavigationStack {
        FeaturedBannerEditorView(repository: MockFeaturedBannerRepository()) {}
            .environmentObject(AuthState())
    }
}
