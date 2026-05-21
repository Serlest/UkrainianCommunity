import PhotosUI
import SwiftUI
import UIKit

struct OrganizationEditorView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var organizationsViewModel: OrganizationsViewModel
    @StateObject private var viewModel: OrganizationEditorViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var phone = ""
    @State private var social = ""
    private let onSaved: @MainActor () async -> Void

    init(
        organizationsViewModel: OrganizationsViewModel,
        onSaved: @escaping @MainActor () async -> Void = {}
    ) {
        self.organizationsViewModel = organizationsViewModel
        _viewModel = StateObject(wrappedValue: OrganizationEditorViewModel(mode: .create))
        self.onSaved = onSaved
    }

    init(
        organizationsViewModel: OrganizationsViewModel,
        organization: Organization,
        onSaved: @escaping @MainActor () async -> Void = {}
    ) {
        self.organizationsViewModel = organizationsViewModel
        _viewModel = StateObject(wrappedValue: OrganizationEditorViewModel(mode: .edit(existing: organization)))
        self.onSaved = onSaved
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                editorHeader
                    .padding(.top, AppTheme.dashboardSpacing)

                editorTitleBlock
                statusContent
                mainInfoCard
                categoryCard
                contactCard
                locationCard
                aboutCard
                additionalSettingsCard
                moderationNoticeCard
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
    }

    private var editorHeader: some View {
        AppCenteredBrandHeader {
            AppGlassIconButton(systemImage: "chevron.left", accessibilityLabel: AppStrings.Common.back) {
                dismiss()
            }
        } trailingContent: {
            AppEditorSubmitButton(
                title: viewModel.submitButtonTitle,
                isEnabled: viewModel.canSubmit && !organizationsViewModel.isSavingOrganization,
                isLoading: organizationsViewModel.isSavingOrganization || viewModel.isProcessingImage,
                loadingTitle: organizationsViewModel.isUploadingOrganizationImage ? AppStrings.NewsEditor.uploadingImage : AppStrings.Organizations.publishing
            ) {
                Task {
                    let didSave = await viewModel.submit(
                        with: organizationsViewModel,
                        user: authState.user
                    )
                    guard didSave else { return }
                    await onSaved()
                    dismiss()
                }
            }
        }
    }

    private var editorTitleBlock: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsCardContentSpacing) {
            Text(viewModel.navigationTitle)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(AppStrings.Organizations.editorSubtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusContent: some View {
        if organizationsViewModel.isSavingOrganization || viewModel.isProcessingImage {
            AppEditorSectionCard {
                Label(
                    organizationsViewModel.isUploadingOrganizationImage ? AppStrings.NewsEditor.uploadingImage : AppStrings.Organizations.publishing,
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.accentPrimary)
            }
        }

        if let errorMessage = viewModel.errorMessage {
            AppEditorSectionCard {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accentDestructive)
            }
        }

        if let successMessage = viewModel.successMessage {
            AppEditorSectionCard {
                Label(successMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
    }

    private var mainInfoCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: AppTheme.sectionSpacing) {
                        logoPicker
                            .frame(width: 150)

                        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                            nameField
                            descriptionField
                        }
                    }

                    VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                        logoPicker
                        nameField
                        descriptionField
                    }
                }
            }
        }
    }

    private var nameField: some View {
        AppEditorField(title: AppStrings.Organizations.fieldName, counterText: "\(viewModel.name.count)/100") {
            TextField(AppStrings.Organizations.fieldNamePlaceholder, text: $viewModel.name)
                .textInputAutocapitalization(.words)
                .appEditorInputStyle()
                .accessibilityLabel(AppStrings.Organizations.fieldName)
        }
    }

    private var descriptionField: some View {
        AppEditorField(title: AppStrings.Organizations.fieldDescription, counterText: "\(viewModel.description.count)/200") {
            TextField(AppStrings.Organizations.fieldDescriptionPlaceholder, text: $viewModel.description, axis: .vertical)
                .lineLimit(3...6)
                .textInputAutocapitalization(.sentences)
                .appEditorInputStyle(minHeight: AppTheme.newsEditorSummaryInputHeight)
                .accessibilityLabel(AppStrings.Organizations.fieldDescription)
        }
    }

    private var logoPicker: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
            logoPickerContent
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isProcessingImage || organizationsViewModel.isSavingOrganization)
        .accessibilityLabel(AppStrings.Organizations.imageSectionTitle)
    }

    @ViewBuilder
    private var logoPickerContent: some View {
        if let selectedImageData = viewModel.selectedImageData,
           let image = UIImage(data: selectedImageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
                .overlay(logoBorder)
        } else if let existingImageURL = viewModel.existingImageURL {
            RemoteImageView(
                imageURL: existingImageURL,
                height: 150,
                cornerRadius: AppTheme.imageRadius,
                source: "OrganizationEditorView",
                placeholderStyle: .glassSkeleton
            )
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
        } else {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                Image(systemName: "photo.badge.plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)

                Text(AppStrings.Organizations.logoUploadTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(AppStrings.Organizations.logoUploadHelper)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
            }
            .padding(AppTheme.detailCardPadding)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
            .overlay(logoBorder)
        }
    }

    private var logoBorder: some View {
        RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
            .stroke(AppTheme.glassBorder(for: colorScheme), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
    }

    private var categoryCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.Organizations.categorySectionTitle)

                AppHorizontalFilterRow {
                    ForEach(OrganizationEditorCategory.allCases) { category in
                        AppFilterChip(
                            title: category.title,
                            systemImage: category.systemImage
                        )
                        .opacity(0.58)
                        .accessibilityHint(AppStrings.Action.comingSoon)
                    }
                }
            }
        }
    }

    private var contactCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.Organizations.contactSectionTitle)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.eventsMetadataSpacing) {
                    iconTextField(systemImage: "envelope", placeholder: AppStrings.Organizations.fieldContactEmail, text: $viewModel.contactEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    iconTextField(systemImage: "phone", placeholder: AppStrings.Organizations.phonePlaceholder, text: $phone, isDisabled: true)
                        .keyboardType(.phonePad)
                }

                iconTextField(systemImage: "globe", placeholder: AppStrings.Organizations.fieldWebsite, text: $viewModel.website)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    iconTextField(systemImage: "point.3.connected.trianglepath.dotted", placeholder: AppStrings.Organizations.socialPlaceholder, text: $social, isDisabled: true)

                    AppGlassIconButton(systemImage: "plus", accessibilityLabel: AppStrings.Action.create, isPlaceholder: true)
                }
            }
        }
    }

    private var locationCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.Organizations.locationSectionTitle)

                iconTextField(systemImage: "mappin.circle", placeholder: AppStrings.Organizations.locationPlaceholder, text: $viewModel.city)

                Button {} label: {
                    Label(AppStrings.Organizations.chooseOnMap, systemImage: "map")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.searchControlHeight)
                        .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                                .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                        )
                }
                .buttonStyle(.plain)
                .disabled(true)
                .opacity(0.66)
                .accessibilityHint(AppStrings.Action.comingSoon)
            }
        }
    }

    private var aboutCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.Organizations.aboutSectionTitle)

                richTextToolbar
                    .opacity(0.54)
                    .accessibilityHint(AppStrings.Action.comingSoon)

                Text(AppStrings.Organizations.aboutPlaceholder)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, minHeight: AppTheme.newsEditorSummaryTextHeight, alignment: .topLeading)
                    .padding(AppTheme.inputHorizontalPadding)
                    .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                            .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                    )
            }
        }
    }

    private var additionalSettingsCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.Organizations.settingsSectionTitle)

                HStack(spacing: AppTheme.dashboardSpacing) {
                    Image(systemName: "lock")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppStrings.Organizations.visibilityTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(AppStrings.Organizations.visibilityHelper)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    AppFilterChip(title: AppStrings.Organizations.visibilityPublic, trailingSystemImage: "chevron.down")
                        .opacity(0.72)
                }
            }
        }
    }

    private var moderationNoticeCard: some View {
        HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            Text(AppStrings.Organizations.moderationNotice)
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(3)
        }
        .padding(AppTheme.detailCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceGlass, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private var richTextToolbar: some View {
        HStack(spacing: 0) {
            ForEach(OrganizationEditorToolbarItem.allCases) { item in
                Image(systemName: item.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.searchControlHeight)
            }
        }
        .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme))
        )
    }

    private func iconTextField(
        systemImage: String,
        placeholder: String,
        text: Binding<String>,
        isDisabled: Bool = false
    ) -> some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            TextField(placeholder, text: text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .disabled(isDisabled)
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(height: AppTheme.searchControlHeight)
        .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme))
        )
        .opacity(isDisabled ? 0.58 : 1)
        .accessibilityHint(isDisabled ? AppStrings.Action.comingSoon : "")
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

private enum OrganizationEditorCategory: String, CaseIterable, Identifiable {
    case education
    case culture
    case support
    case integration
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .education:
            AppStrings.Organizations.categoryEducation
        case .culture:
            AppStrings.Organizations.categoryCulture
        case .support:
            AppStrings.Organizations.categorySupport
        case .integration:
            AppStrings.Organizations.categoryIntegration
        case .other:
            AppStrings.Organizations.categoryOther
        }
    }

    var systemImage: String {
        switch self {
        case .education:
            "graduationcap"
        case .culture:
            "theatermasks"
        case .support:
            "hands.clap"
        case .integration:
            "person.2"
        case .other:
            "square.grid.2x2"
        }
    }
}

private enum OrganizationEditorToolbarItem: String, CaseIterable, Identifiable {
    case text
    case bold
    case italic
    case underline
    case bulletList
    case numberedList
    case link
    case image
    case quote
    case more

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .text:
            "textformat"
        case .bold:
            "bold"
        case .italic:
            "italic"
        case .underline:
            "underline"
        case .bulletList:
            "list.bullet"
        case .numberedList:
            "list.number"
        case .link:
            "link"
        case .image:
            "photo"
        case .quote:
            "quote.bubble"
        case .more:
            "ellipsis"
        }
    }
}
