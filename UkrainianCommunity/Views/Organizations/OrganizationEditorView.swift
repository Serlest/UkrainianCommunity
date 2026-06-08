import PhotosUI
import SwiftUI
import UIKit

struct OrganizationEditorView: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @ObservedObject var organizationsViewModel: OrganizationsViewModel
    @StateObject var viewModel: OrganizationEditorViewModel
    @State var selectedPhoto: PhotosPickerItem?
    @State var cropSourceLogoImage: UIImage?
    @State var isShowingLogoCrop = false
    @State var ignoresNextPhotoClear = false
    @State var isShowingDraftRecoveryDialog = false
    @State var isShowingDraftCloseConfirmation = false
    let onSaved: @MainActor () async -> Void
    let editorSectionSpacing: CGFloat = 8
    let editorCardSpacing: CGFloat = 8
    let editorCardPadding: CGFloat = 10
    let editorCardRadius: CGFloat = 16
    let compactInputHeight: CGFloat = 40
    let summaryInputHeight: CGFloat = 78
    let summaryTextHeight: CGFloat = 60
    let uploadMinHeight: CGFloat = 124

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
        EditorScreenShell(
            title: viewModel.navigationTitle,
            subtitle: AppStrings.Organizations.editorSubtitle,
            closeStyle: .cancel,
            closeAction: requestClose
        ) {
            statusContent
            mainInfoCard
            contactCard
            locationCard
            aboutCard
            moderationNoticeCard
            bottomSubmitButton
        }
        .tint(AppTheme.accentPrimary)
        .sheet(isPresented: $isShowingLogoCrop, onDismiss: resetLogoCropSelection) {
            if let cropSourceLogoImage {
                ImageCropView(
                    sourceImage: cropSourceLogoImage,
                    profile: .squareLogo,
                    title: AppStrings.Images.Crop.title,
                    instructions: AppStrings.Organizations.logoUploadHelper,
                    onCancel: {},
                    onApply: applyCroppedLogoImage(_:)
                )
            }
        }
        .confirmationDialog(
            AppStrings.DraftRecovery.recoveryTitle,
            isPresented: $isShowingDraftRecoveryDialog,
            titleVisibility: .visible
        ) {
            Button(AppStrings.DraftRecovery.continueDraft) {
                viewModel.continueRecoveredDraft()
            }
            Button(AppStrings.DraftRecovery.createNew) {
                Task {
                    await viewModel.createNewInsteadOfRecoveredDraft()
                }
            }
            Button(AppStrings.DraftRecovery.deleteDraft, role: .destructive) {
                Task {
                    await viewModel.deleteRecoveredDraft()
                }
            }
        } message: {
            Text(AppStrings.DraftRecovery.organizationRecoveryMessage)
        }
        .confirmationDialog(
            AppStrings.DraftRecovery.closeTitle,
            isPresented: $isShowingDraftCloseConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppStrings.DraftRecovery.saveDraftAndClose) {
                Task {
                    await viewModel.saveDraftBeforeClosing()
                    dismiss()
                }
            }
            Button(AppStrings.DraftRecovery.discardDraft, role: .destructive) {
                Task {
                    await viewModel.discardCreateDraft()
                    dismiss()
                }
            }
            Button(AppStrings.DraftRecovery.continueEditing, role: .cancel) {}
        } message: {
            Text(AppStrings.DraftRecovery.organizationCloseMessage)
        }
        .interactiveDismissDisabled(viewModel.shouldConfirmDraftBeforeDismiss)
        .onChange(of: selectedPhoto) { _, newItem in
            if newItem == nil, ignoresNextPhotoClear {
                ignoresNextPhotoClear = false
                return
            }
            Task {
                await loadSelectedPhoto(item: newItem)
            }
        }
        .task {
            await loadRecoverableDraftIfNeeded()
        }
    }

    func loadRecoverableDraftIfNeeded() async {
        await viewModel.loadRecoverableDraftIfNeeded()
        isShowingDraftRecoveryDialog = viewModel.hasPendingRecoveryDraft
    }

    var moderationNoticeCard: some View {
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

    func iconTextField(
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
        .appEditorInputStyle(minHeight: compactInputHeight)
        .opacity(isDisabled ? 0.58 : 1)
        .accessibilityHint(isDisabled ? AppStrings.Action.comingSoon : "")
    }

    func editorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
        }
    }

    func editorField<Content: View>(title: String, counterText: String, @ViewBuilder content: () -> Content) -> some View {
        AppEditorField(title: title, counterText: counterText) {
            content()
        }
    }

    func editorSectionTitle(_ title: String) -> some View {
        AppEditorSectionTitle(title: title)
    }
}

extension View {
    func organizationEditorCompactInputStyle(minHeight: CGFloat) -> some View {
        self.appEditorInputStyle(minHeight: minHeight)
    }
}
