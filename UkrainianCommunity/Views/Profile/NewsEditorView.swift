import PhotosUI
import SwiftUI
import UIKit

struct NewsEditorView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: NewsEditorViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    private let onPublished: @MainActor () async -> Void

    private let titleLimit = 120
    private let summaryLimit = 200
    private let bodyLimit = 10000
    private let editorSectionSpacing: CGFloat = 8
    private let editorCardSpacing: CGFloat = 8
    private let editorCardPadding: CGFloat = 10
    private let editorCardRadius: CGFloat = 16
    private let compactInputHeight: CGFloat = 40
    private let summaryInputHeight: CGFloat = 78
    private let summaryTextHeight: CGFloat = 60
    private let bodyInputHeight: CGFloat = 70
    private let detailRowHeight: CGFloat = 52
    private let detailIconSize: CGFloat = 16
    private let uploadMinHeight: CGFloat = 124
    private let headerLogoSize = CGSize(width: 118, height: 42)

    init(repository: NewsRepository, onPublished: @escaping @MainActor () async -> Void = {}) {
        _viewModel = StateObject(wrappedValue: NewsEditorViewModel(repository: repository, mode: .create()))
        self.onPublished = onPublished
    }

    init(
        repository: NewsRepository,
        organizationId: String,
        organizationName: String,
        organizationImageURL: String?,
        organizationFederalState: AustrianFederalState? = nil,
        onPublished: @escaping @MainActor () async -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: NewsEditorViewModel(
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

    init(repository: NewsRepository, news: NewsPost, onPublished: @escaping @MainActor () async -> Void = {}) {
        _viewModel = StateObject(wrappedValue: NewsEditorViewModel(repository: repository, mode: .edit(existing: news)))
        self.onPublished = onPublished
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: editorSectionSpacing) {
                editorHeader
                    .padding(.top, AppTheme.dashboardSpacing)

                editorTitleBlock

                statusContent

                mainInformationCard

                coverImageCard

                bodyContentCard

                tagsCard

                if viewModel.showsRegionPicker {
                    settingsCard
                }

                bottomPublishButton
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.bottom, AppTheme.homeBottomContentPadding)
        }
        .background(AppBackgroundView())
        .tint(AppTheme.accentPrimary)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                await loadSelectedPhoto(item: newItem)
            }
        }
        .task(id: authState.user?.id) {
            viewModel.setAuthState(authState)
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
            headerIconButton(systemImage: "xmark", accessibilityLabel: AppStrings.Common.cancel) {
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

    private var bottomPublishButton: some View {
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

    private var editorTitleBlock: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsCardContentSpacing) {
            Text(viewModel.isEditing ? AppStrings.NewsEditor.editTitle : AppStrings.NewsEditor.addTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(AppStrings.NewsEditor.editorSubtitle)
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusContent: some View {
        if viewModel.isPublishing || viewModel.isUploadingImage || viewModel.isProcessingImage {
            editorCard {
                Label(statusMessage, systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accentPrimary)
            }
        }

        if let successMessage = viewModel.successMessage {
            editorCard {
                Label(successMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            }
        }

        if let errorMessage = viewModel.errorMessage {
            editorCard {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accentDestructive)
            }
        }

        if viewModel.requiresOrganizationRegionBeforePublishing {
            editorCard {
                Label(AppStrings.NewsEditor.organizationRegionRequired, systemImage: "exclamationmark.triangle.fill")
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
        return AppStrings.NewsEditor.publishing
    }

    private var mainInformationCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorField(
                    title: AppStrings.NewsEditor.titleFieldRequired,
                    counterText: counterText(viewModel.title.count, limit: titleLimit)
                ) {
                    TextField(AppStrings.NewsEditor.titlePlaceholder, text: $viewModel.title)
                        .font(.subheadline)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.next)
                        .newsEditorCompactInputStyle(minHeight: compactInputHeight)
                }

                editorField(
                    title: AppStrings.NewsEditor.summaryFieldRequired,
                    counterText: counterText(viewModel.summary.count, limit: summaryLimit)
                ) {
                    ZStack(alignment: .topLeading) {
                        if viewModel.summary.isEmpty {
                            Text(AppStrings.NewsEditor.summaryPlaceholder)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
                                .lineSpacing(2)
                                .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
                                .padding(.vertical, AppTheme.eventsMetadataSpacing)
                        }

                        TextEditor(text: $viewModel.summary)
                            .scrollContentBackground(.hidden)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(minHeight: summaryTextHeight)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                    }
                    .newsEditorCompactInputStyle(minHeight: summaryInputHeight)
                }
            }
        }
    }

    private var coverImageCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorSectionTitle(AppStrings.NewsEditor.coverSectionTitle)

                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    coverPickerContent
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isProcessingImage || viewModel.isPublishing)
            }
        }
    }

    @ViewBuilder
    private var coverPickerContent: some View {
        if let selectedImageData = viewModel.selectedImageData,
           let image = UIImage(data: selectedImageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: uploadMinHeight)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                        .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                )
        } else if let existingImageURL = viewModel.existingImageURL {
            RemoteImageView(
                imageURL: existingImageURL,
                height: uploadMinHeight,
                cornerRadius: AppTheme.imageRadius,
                source: "NewsEditorView",
                placeholderStyle: .glassSkeleton
            )
            .overlay(alignment: .bottomTrailing) {
                Text(AppStrings.NewsEditor.replacePhoto)
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

    private var uploadPlaceholder: some View {
        VStack(spacing: 7) {
            Image(systemName: "photo.badge.plus")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary.opacity(0.78))

            Text(AppStrings.NewsEditor.coverUploadTitle)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(AppStrings.NewsEditor.coverUploadHelper)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: uploadMinHeight)
        .background(AppTheme.glassControlSurface(for: colorScheme).opacity(0.72), in: RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                .stroke(AppTheme.glassBorder(for: colorScheme).opacity(0.82), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        )
    }

    private var bodyContentCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorSectionTitle(AppStrings.NewsEditor.bodySectionTitle)

                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        if viewModel.body.isEmpty {
                            Text(AppStrings.NewsEditor.bodyPlaceholder)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
                                .lineSpacing(2)
                                .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
                                .padding(.top, AppTheme.dashboardSpacing)
                        }

                        TextEditor(text: $viewModel.body)
                            .scrollContentBackground(.hidden)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(minHeight: bodyInputHeight)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                    }

                    HStack {
                        Spacer(minLength: 0)
                        Text(counterText(viewModel.body.count, limit: bodyLimit))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.trailing, AppTheme.eventsControlGroupSpacing)
                            .padding(.bottom, AppTheme.eventsMetadataSpacing)
                    }
                }
                .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                        .strokeBorder(AppTheme.glassBorder(for: colorScheme).opacity(0.82))
                )
            }
        }
    }

    private var tagsCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorSectionTitle(AppStrings.NewsEditor.tagsSectionTitle)

                TextField(AppStrings.NewsEditor.tagsPlaceholder, text: $viewModel.tagsInput)
                    .newsEditorCompactInputStyle(minHeight: compactInputHeight)

                Text(AppStrings.NewsEditor.tagsHelper)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(2)
            }
        }
    }

    private var settingsCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorSectionTitle(AppStrings.NewsEditor.regionSectionTitle)

                Menu {
                    ForEach(AustrianFederalState.allCases) { federalState in
                        Button(federalState.displayName) {
                            viewModel.selectedFederalState = federalState
                        }
                    }
                } label: {
                    settingsRows {
                        detailRow(
                            systemImage: "map",
                            title: AppStrings.NewsEditor.regionSectionTitle,
                            value: viewModel.selectedFederalState.displayName,
                            showsChevron: true
                        )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func settingsRows<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(AppTheme.glassControlSurface(for: colorScheme).opacity(0.72), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme).opacity(0.82))
        )
    }

    private func detailRow(
        systemImage: String,
        title: String,
        value: String,
        isPlaceholder: Bool = false,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            rowIcon(systemImage)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: AppTheme.eventsMetadataSpacing)

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isPlaceholder ? AppTheme.textSecondary.opacity(0.68) : AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: detailRowHeight)
    }

    private func rowIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary.opacity(0.92))
            .frame(width: detailIconSize, height: detailIconSize)
    }

    private func editorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(editorCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.glassSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: editorCardRadius, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: editorCardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: editorCardRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme).opacity(0.55))
        )
        .shadow(color: AppTheme.glassShadow(for: colorScheme).opacity(0.45), radius: 10, y: 5)
    }

    private func editorField<Content: View>(title: String, counterText: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer(minLength: AppTheme.eventsMetadataSpacing)

                Text(counterText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .monospacedDigit()
            }

            content()
        }
    }

    private func editorSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func counterText(_ count: Int, limit: Int) -> String {
        "\(count)/\(limit)"
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

#Preview {
    NavigationStack {
        NewsEditorView(repository: MockNewsRepository(), onPublished: {})
    }
    .environmentObject(AuthState())
}

private extension View {
    func newsEditorCompactInputStyle(minHeight: CGFloat) -> some View {
        self
            .font(.subheadline)
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
            .frame(minHeight: minHeight, alignment: .leading)
            .background(AppTheme.surfaceControl.opacity(0.36), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                    .strokeBorder(AppTheme.borderSubtle)
            )
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
