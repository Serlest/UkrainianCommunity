import SwiftUI

struct GuideMaterialDetailView: View {
    let material: GuideMaterial
    @ObservedObject var viewModel: GuideReaderViewModel
    let feedbackRepository: FeedbackRepository
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @State private var guestAccessAction: GuestAccessAction?
    @State private var saveError: AppError?
    @State private var presentedFeedbackKind: GuideMaterialFeedbackKind?

    var body: some View {
        DetailPageContainer {
            detailHeader
            compactHeader
            content
            GuideMaterialSourcesView(
                links: material.sourceLinks,
                legacyURL: material.officialSourceURL,
                legacyTitle: material.sourceName
            )
            GuideMaterialFeedbackSection(
                onSelectKind: handleFeedbackAction
            )
        }
        .background(AppBackgroundView().allowsHitTesting(false))
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadSavedMaterialsIfNeeded()
        }
        .sheet(item: $presentedFeedbackKind) { kind in
            GuideMaterialFeedbackSheet(
                material: material,
                initialKind: kind,
                repository: feedbackRepository
            )
            .presentationDetents([.medium, .large])
        }
        .guestAccessAlert($guestAccessAction)
        .alert(
            GuideCategoryPresentation.saveActionFailedTitle,
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button(AppStrings.Common.ok, role: .cancel) {}
        } message: {
            Text(GuideCategoryPresentation.saveActionErrorMessage(for: saveError ?? .unknown))
        }
    }

    private var detailHeader: some View {
        AppCenteredBrandHeader {
            detailIconButton(systemImage: "chevron.left", accessibilityLabel: AppStrings.Common.back) {
                dismiss()
            }
        } trailingContent: {
            detailIconButton(
                systemImage: viewModel.isMaterialSaved(material.id) ? "bookmark.fill" : "bookmark",
                accessibilityLabel: AppStrings.Action.save
            ) {
                handleSavedToggle()
            }
            .disabled(viewModel.isMaterialSavePending(material.id))
        }
        .zIndex(10)
    }

    private var compactHeader: some View {
        GuideHierarchyHeaderCard(
            title: material.title,
            subtitle: material.summary.nilIfBlank,
            badgeSystemImage: "doc.text",
            badgeTitle: GuideCategoryPresentation.materialBadgeTitle,
            contextText: pathDescription.nilIfBlank
        )
    }

    @ViewBuilder
    private var content: some View {
        if !material.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DetailCard {
                GuideBlockTitleView(title: GuideAuthoringPresentation.descriptionSectionTitle)

                Text(material.body)
                    .font(AppTheme.detailBodyFont)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        ForEach(structuredBlocks) { block in
            GuideContentBlockView(block: block)
        }
    }

    private var pathDescription: String {
        let components = material.nodePath.titles
        return components.joined(separator: " → ")
    }

    private var structuredBlocks: [GuideContentBlock] {
        var textBlocks: [GuideContentBlock] = []
        var stepsBlocks: [GuideContentBlock] = []
        var checklistBlocks: [GuideContentBlock] = []
        var contactsBlocks: [GuideContentBlock] = []
        var informationBlocks: [GuideContentBlock] = []
        var linksBlocks: [GuideContentBlock] = []

        for block in material.contentBlocks where block.isRenderable {
            switch block {
            case .text:
                textBlocks.append(block)
            case .steps:
                stepsBlocks.append(block)
            case .checklist:
                checklistBlocks.append(block)
            case .contacts:
                contactsBlocks.append(block)
            case .warning, .infoBox:
                informationBlocks.append(block)
            case .links:
                linksBlocks.append(block)
            }
        }

        return textBlocks + stepsBlocks + checklistBlocks + contactsBlocks + informationBlocks + linksBlocks
    }

    private func handleSavedToggle() {
        guard authState.isAuthenticated else {
            guestAccessAction = .bookmarks
            return
        }

        Task {
            do {
                try await viewModel.toggleSavedMaterial(material)
                saveError = nil
            } catch let appError as AppError {
                saveError = appError
            } catch {
                saveError = .unknown
            }
        }
    }

    private func handleFeedbackAction(_ kind: GuideMaterialFeedbackKind) {
        guard authState.isAuthenticated else {
            guestAccessAction = .feedback
            return
        }

        presentedFeedbackKind = kind
    }

    private func detailIconButton(
        systemImage: String,
        accessibilityLabel: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        AppGlassIconButton(
            systemImage: systemImage,
            accessibilityLabel: accessibilityLabel,
            role: role
        ) {
            action()
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .zIndex(2)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
