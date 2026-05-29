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
    let onSaved: @MainActor () async -> Void
    let editorSectionSpacing: CGFloat = 8
    let editorCardSpacing: CGFloat = 8
    let editorCardPadding: CGFloat = 10
    let editorCardRadius: CGFloat = 16
    let compactInputHeight: CGFloat = 40
    let summaryInputHeight: CGFloat = 78
    let summaryTextHeight: CGFloat = 60
    let uploadMinHeight: CGFloat = 124
    let headerLogoSize = CGSize(width: 118, height: 42)

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

    func editorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
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

    func editorField<Content: View>(title: String, counterText: String, @ViewBuilder content: () -> Content) -> some View {
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

    func editorSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
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
