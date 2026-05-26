import PhotosUI
import SwiftUI
import UIKit

struct OrganizationEditorView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var organizationsViewModel: OrganizationsViewModel
    @StateObject private var viewModel: OrganizationEditorViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    private let onSaved: @MainActor () async -> Void
    private let editorSectionSpacing: CGFloat = 8
    private let editorCardSpacing: CGFloat = 8
    private let editorCardPadding: CGFloat = 10
    private let editorCardRadius: CGFloat = 16
    private let compactInputHeight: CGFloat = 40
    private let summaryInputHeight: CGFloat = 78
    private let summaryTextHeight: CGFloat = 60
    private let uploadMinHeight: CGFloat = 124
    private let headerLogoSize = CGSize(width: 118, height: 42)

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
            VStack(alignment: .leading, spacing: editorSectionSpacing) {
                editorHeader
                    .padding(.top, AppTheme.dashboardSpacing)

                editorTitleBlock
                statusContent
                mainInfoCard
                contactCard
                locationCard
                aboutCard
                futureCapabilitiesCard
                moderationNoticeCard
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
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                await loadSelectedPhoto(item: newItem)
            }
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
            AppGlassIconButton(systemImage: "xmark", accessibilityLabel: AppStrings.Common.cancel) {
                dismiss()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var bottomSubmitButton: some View {
        Button(action: submit) {
            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }

                Text(isSaving ? bottomLoadingTitle : bottomSubmitTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                    .fill(canTapSubmit ? AppTheme.accentPrimary : AppTheme.accentPrimary.opacity(0.26))
            )
            .shadow(color: AppTheme.accentPrimary.opacity(canTapSubmit ? 0.18 : 0), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!canTapSubmit)
        .accessibilityLabel(bottomSubmitTitle)
    }

    private var bottomSubmitTitle: String {
        viewModel.submitButtonTitle(for: authState.user)
    }

    private var bottomLoadingTitle: String {
        organizationsViewModel.isUploadingOrganizationImage ? AppStrings.NewsEditor.uploadingImage : AppStrings.Organizations.publishing
    }

    private var isSaving: Bool {
        organizationsViewModel.isSavingOrganization || viewModel.isProcessingImage
    }

    private var canTapSubmit: Bool {
        viewModel.canSubmit && !isSaving
    }

    private func submit() {
        guard canTapSubmit else { return }
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

    private var editorTitleBlock: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsCardContentSpacing) {
            Text(viewModel.navigationTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(AppStrings.Organizations.editorSubtitle)
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusContent: some View {
        if organizationsViewModel.isSavingOrganization || viewModel.isProcessingImage {
            editorCard {
                Label(
                    organizationsViewModel.isUploadingOrganizationImage ? AppStrings.NewsEditor.uploadingImage : AppStrings.Organizations.publishing,
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.accentPrimary)
            }
        }

        if let errorMessage = viewModel.errorMessage {
            editorCard {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accentDestructive)
            }
        }

        if let successMessage = viewModel.successMessage {
            editorCard {
                Label(successMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
    }

    private var mainInfoCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorSectionTitle(AppStrings.Organizations.detailsSectionTitle)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: AppTheme.dashboardSpacing) {
                        logoPicker
                            .frame(width: uploadMinHeight)

                        VStack(alignment: .leading, spacing: editorCardSpacing) {
                            nameField
                            descriptionField
                        }
                    }

                    VStack(alignment: .leading, spacing: editorCardSpacing) {
                        logoPicker
                        nameField
                        descriptionField
                    }
                }

                categoryPicker
            }
        }
    }

    private var nameField: some View {
        editorField(title: AppStrings.Organizations.fieldName, counterText: "\(viewModel.name.count)/100") {
            TextField(AppStrings.Organizations.fieldNamePlaceholder, text: $viewModel.name)
                .font(.subheadline)
                .textInputAutocapitalization(.words)
                .organizationEditorCompactInputStyle(minHeight: compactInputHeight)
                .accessibilityLabel(AppStrings.Organizations.fieldName)
        }
    }

    private var descriptionField: some View {
        editorField(title: AppStrings.Organizations.fieldDescription, counterText: "\(viewModel.shortDescription.count)/\(OrganizationEditorViewModel.shortDescriptionLimit)") {
            TextField(AppStrings.Organizations.fieldDescriptionPlaceholder, text: $viewModel.shortDescription, axis: .vertical)
                .lineLimit(3...6)
                .font(.subheadline)
                .textInputAutocapitalization(.sentences)
                .organizationEditorCompactInputStyle(minHeight: summaryInputHeight)
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
                height: uploadMinHeight,
                cornerRadius: AppTheme.imageRadius,
                source: "OrganizationEditorView",
                placeholderStyle: .glassSkeleton
            )
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
        } else {
            VStack(spacing: 7) {
                Image(systemName: "photo.badge.plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary.opacity(0.78))

                Text(AppStrings.Organizations.logoUploadTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(AppStrings.Organizations.logoUploadHelper)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
            }
            .padding(editorCardPadding)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(AppTheme.glassControlSurface(for: colorScheme).opacity(0.72), in: RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
            .overlay(logoBorder)
        }
    }

    private var logoBorder: some View {
        RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
            .stroke(AppTheme.glassBorder(for: colorScheme).opacity(0.82), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: editorCardSpacing) {
            editorSectionTitle(AppStrings.Organizations.categorySectionTitle)

            AppHorizontalFilterRow {
                ForEach(OrganizationEditorCategory.allCases) { category in
                    Button {
                        viewModel.organizationType = category.rawValue
                    } label: {
                        AppFilterChip(
                            title: category.title,
                            systemImage: category.systemImage,
                            isSelected: viewModel.organizationType == category.rawValue
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var contactCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorSectionTitle(AppStrings.Organizations.contactSectionTitle)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.eventsMetadataSpacing) {
                    iconTextField(systemImage: "envelope", placeholder: AppStrings.Organizations.fieldContactEmail, text: $viewModel.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    iconTextField(systemImage: "phone", placeholder: AppStrings.Organizations.phonePlaceholder, text: $viewModel.phone)
                        .keyboardType(.phonePad)
                }

                iconTextField(systemImage: "globe", placeholder: AppStrings.Organizations.fieldWebsite, text: $viewModel.website)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                iconTextField(systemImage: "paperplane", placeholder: AppStrings.Organizations.fieldTelegramURL, text: $viewModel.telegramURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                iconTextField(systemImage: "heart", placeholder: AppStrings.Organizations.fieldDonationURL, text: $viewModel.donationURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                iconTextField(systemImage: "person.crop.circle", placeholder: AppStrings.Organizations.fieldContactPerson, text: $viewModel.contactPerson)
                    .textInputAutocapitalization(.words)

                VStack(alignment: .leading, spacing: 7) {
                    Text(AppStrings.Organizations.socialLinksTitle)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    iconTextField(systemImage: "point.3.connected.trianglepath.dotted", placeholder: AppStrings.Organizations.socialPlaceholder, text: $viewModel.socialLinks)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        }
    }

    private var locationCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorSectionTitle(AppStrings.Organizations.locationSectionTitle)

                Menu {
                    ForEach(AustrianFederalState.allCases) { federalState in
                        Button(AppStrings.FederalStates.title(for: federalState)) {
                            viewModel.selectedFederalState = federalState
                        }
                    }
                } label: {
                    HStack(spacing: AppTheme.eventsMetadataSpacing) {
                        Image(systemName: "map")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                        Text(selectedRegionTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(viewModel.selectedFederalState == nil ? AppTheme.textSecondary : AppTheme.textPrimary)

                        Spacer(minLength: AppTheme.eventsMetadataSpacing)

                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
                    .frame(height: compactInputHeight)
                    .background(AppTheme.surfaceControl.opacity(0.36), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                            .strokeBorder(AppTheme.borderSubtle)
                    )
                }
                .buttonStyle(.plain)

                iconTextField(systemImage: "building.2", placeholder: AppStrings.Organizations.fieldCity, text: $viewModel.city)

                iconTextField(systemImage: "mappin.circle", placeholder: AppStrings.Organizations.fieldAddress, text: $viewModel.address)
            }
        }
    }

    private var aboutCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorSectionTitle(AppStrings.Organizations.aboutSectionTitle)

                TextField(AppStrings.Organizations.fieldMissionStatementPlaceholder, text: $viewModel.missionStatement, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.subheadline)
                    .textInputAutocapitalization(.sentences)
                    .organizationEditorCompactInputStyle(minHeight: summaryTextHeight)
                    .accessibilityLabel(AppStrings.Organizations.fieldMissionStatement)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(AppStrings.Organizations.fieldFullDescription)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Spacer(minLength: AppTheme.eventsMetadataSpacing)

                        Text("\(viewModel.fullDescription.count)/\(OrganizationEditorViewModel.fullDescriptionLimit)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .monospacedDigit()
                    }

                    TextField(AppStrings.Organizations.fieldFullDescriptionPlaceholder, text: $viewModel.fullDescription, axis: .vertical)
                        .lineLimit(6...12)
                        .font(.subheadline)
                        .textInputAutocapitalization(.sentences)
                        .organizationEditorCompactInputStyle(minHeight: summaryTextHeight)
                        .accessibilityLabel(AppStrings.Organizations.fieldFullDescription)
                }

                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.eventsMetadataSpacing) {
                        iconTextField(systemImage: "calendar", placeholder: AppStrings.Organizations.fieldFoundedYear, text: $viewModel.foundedYear)
                            .keyboardType(.numberPad)

                        foundedMonthPicker
                    }

                    iconTextField(systemImage: "globe.europe.africa", placeholder: AppStrings.Organizations.fieldLanguages, text: $viewModel.languages)
                }
            }
        }
    }

    private var futureCapabilitiesCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorSectionTitle(AppStrings.Organizations.futureSectionTitle)

                futureCapabilityRow(
                    systemImage: "scope",
                    title: AppStrings.Organizations.organizationSizeTitle,
                    subtitle: AppStrings.Organizations.organizationSizeOptions
                )

                futureCapabilityRow(
                    systemImage: "figure.2.and.child.holdinghands",
                    title: AppStrings.Organizations.volunteersNeededTitle,
                    subtitle: AppStrings.Organizations.volunteersNeededSubtitle
                )

                futureCapabilityRow(
                    systemImage: "checkmark.seal",
                    title: AppStrings.Organizations.verificationRequestTitle,
                    subtitle: AppStrings.Organizations.verificationRequestSubtitle
                )

                futureCapabilityRow(
                    systemImage: "person.3",
                    title: AppStrings.Organizations.teamManagementTitle,
                    subtitle: AppStrings.Organizations.teamManagementSubtitle
                )
            }
        }
    }

    private var selectedRegionTitle: String {
        guard let selectedFederalState = viewModel.selectedFederalState else {
            return AppStrings.Organizations.fieldRegionPlaceholder
        }
        return AppStrings.FederalStates.title(for: selectedFederalState)
    }

    private var foundedMonthPicker: some View {
        Menu {
            Button(AppStrings.Organizations.fieldFoundedMonthNone) {
                viewModel.foundedMonth = nil
            }

            ForEach(1...12, id: \.self) { month in
                Button(localizedMonthName(for: month)) {
                    viewModel.foundedMonth = month
                }
            }
        } label: {
            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                Image(systemName: "calendar.badge.clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                Text(selectedFoundedMonthTitle)
                    .font(.subheadline)
                    .foregroundStyle(viewModel.foundedMonth == nil ? AppTheme.textSecondary : AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: AppTheme.eventsMetadataSpacing)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
            .frame(minHeight: compactInputHeight, alignment: .leading)
            .background(AppTheme.surfaceControl.opacity(0.36), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                    .strokeBorder(AppTheme.borderSubtle)
            )
            .opacity(viewModel.canSelectFoundedMonth ? 1 : 0.58)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSelectFoundedMonth)
        .accessibilityLabel(AppStrings.Organizations.fieldFoundedMonth)
    }

    private var selectedFoundedMonthTitle: String {
        guard viewModel.canSelectFoundedMonth,
              let foundedMonth = viewModel.foundedMonth else {
            return AppStrings.Organizations.fieldFoundedMonthNone
        }
        return localizedMonthName(for: foundedMonth)
    }

    private func localizedMonthName(for month: Int) -> String {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2024
        components.month = month
        components.day = 1

        guard let date = components.date else {
            return AppStrings.Organizations.fieldFoundedMonthNone
        }

        let formatter = DateFormatter()
        formatter.locale = LocalizationStore.locale
        formatter.setLocalizedDateFormatFromTemplate("LLLL")
        return formatter.string(from: date).capitalized(with: LocalizationStore.locale)
    }

    private func futureCapabilityRow(systemImage: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(subtitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppTheme.eventsMetadataSpacing)

            Text(AppStrings.Organizations.comingSoon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(AppTheme.surfaceControl.opacity(0.34), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(AppTheme.borderSubtle)
                )
        }
        .padding(AppTheme.eventsControlGroupSpacing)
        .background(AppTheme.surfaceControl.opacity(0.22), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle.opacity(0.72))
        )
        .opacity(0.68)
        .accessibilityElement(children: .combine)
        .accessibilityHint(AppStrings.Action.comingSoon)
    }

    private var moderationNoticeCard: some View {
        editorCard {
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
        }
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
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
                .disabled(isDisabled)
        }
        .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
        .frame(minHeight: compactInputHeight, alignment: .leading)
        .background(AppTheme.surfaceControl.opacity(0.36), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
        .opacity(isDisabled ? 0.58 : 1)
        .accessibilityHint(isDisabled ? AppStrings.Action.comingSoon : "")
    }

    private func editorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(editorCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassSurface(for: colorScheme),
            in: RoundedRectangle(cornerRadius: editorCardRadius, style: .continuous)
        )
        .background {
            if !reduceTransparency {
                RoundedRectangle(cornerRadius: editorCardRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
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

private extension View {
    func organizationEditorCompactInputStyle(minHeight: CGFloat) -> some View {
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
