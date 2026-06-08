import SwiftUI

enum GuideMaterialFeedbackKind: String, CaseIterable, Identifiable {
    case reportIssue
    case suggestChange

    var id: String { rawValue }

    var feedbackType: FeedbackType {
        switch self {
        case .reportIssue:
            return .report
        case .suggestChange:
            return .suggestion
        }
    }

    var title: String {
        switch self {
        case .reportIssue:
            return GuideCategoryPresentation.feedbackTypeErrorTitle
        case .suggestChange:
            return GuideCategoryPresentation.feedbackTypeSuggestionTitle
        }
    }
}

struct GuideMaterialFeedbackSection: View {
    let onSelectKind: (GuideMaterialFeedbackKind) -> Void

    var body: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(GuideCategoryPresentation.feedbackSectionTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(GuideCategoryPresentation.feedbackSectionSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    onSelectKind(.reportIssue)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.bubble")
                            .font(.subheadline.weight(.semibold))
                        Text(GuideCategoryPresentation.reportIssueActionTitle)
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .appActionButtonStyle(.secondary)

                Button {
                    onSelectKind(.suggestChange)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.pencil")
                            .font(.subheadline.weight(.semibold))
                        Text(GuideCategoryPresentation.suggestChangeActionTitle)
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .appActionButtonStyle(.secondary)
            }
        }
    }
}

struct GuideMaterialFeedbackSheet: View {
    let material: GuideMaterial
    let initialKind: GuideMaterialFeedbackKind
    let repository: FeedbackRepository

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @State private var selectedKind: GuideMaterialFeedbackKind
    @State private var message = ""
    @State private var validationMessage: String?
    @State private var submitError: AppError?
    @State private var isSubmitting = false
    @State private var showsSuccessAlert = false

    init(
        material: GuideMaterial,
        initialKind: GuideMaterialFeedbackKind,
        repository: FeedbackRepository
    ) {
        self.material = material
        self.initialKind = initialKind
        self.repository = repository
        _selectedKind = State(initialValue: initialKind)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    AppEditorSectionCard {
                        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                            SectionHeaderBlock(
                                title: GuideCategoryPresentation.feedbackSheetTitle,
                                subtitle: GuideCategoryPresentation.feedbackSheetSubtitle
                            )

                            VStack(alignment: .leading, spacing: 8) {
                                Text(GuideCategoryPresentation.feedbackMaterialContextLabel)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(AppTheme.textSecondary)

                                Text(material.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text(GuideCategoryPresentation.feedbackTypeFieldTitle)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(AppTheme.textSecondary)

                                Picker(GuideCategoryPresentation.feedbackTypeFieldTitle, selection: $selectedKind) {
                                    ForEach(GuideMaterialFeedbackKind.allCases) { kind in
                                        Text(kind.title).tag(kind)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text(AppStrings.Feedback.fieldMessage)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(AppTheme.textSecondary)

                                ZStack(alignment: .topLeading) {
                                    if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(GuideCategoryPresentation.feedbackMessagePlaceholder)
                                            .font(.body)
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .padding(.horizontal, 13)
                                            .padding(.vertical, 14)
                                    }

                                    TextEditor(text: $message)
                                        .scrollContentBackground(.hidden)
                                        .frame(minHeight: 140)
                                        .padding(8)
                                        .background(Color.clear)
                                }
                                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(AppTheme.borderSubtle)
                                )
                            }

                            if let validationMessage {
                                Text(validationMessage)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.accentDestructive)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if let submitError {
                                Text(GuideCategoryPresentation.feedbackSubmitErrorMessage(for: submitError))
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.accentDestructive)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            PrimaryActionButton(
                                title: GuideCategoryPresentation.feedbackSubmitActionTitle,
                                loadingTitle: AppStrings.Feedback.sending,
                                isEnabled: !isSubmitting,
                                isLoading: isSubmitting,
                                systemImage: "paperplane"
                            ) {
                                submitFeedback()
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.sectionSpacing)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
            }
            .background(AppBackgroundView().allowsHitTesting(false))
            .navigationTitle(initialKind == .reportIssue ? GuideCategoryPresentation.reportIssueActionTitle : GuideCategoryPresentation.suggestChangeActionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppStrings.Common.cancel) {
                        dismiss()
                    }
                }
            }
        }
        .observesKeyboardDismissTaps()
        .appSuccessDialog(Binding(
            get: {
                guard showsSuccessAlert else { return nil }
                return AppSuccessDialog(
                    title: GuideCategoryPresentation.feedbackSuccessTitle,
                    message: GuideCategoryPresentation.feedbackSuccessMessage
                )
            },
            set: {
                if $0 == nil {
                    showsSuccessAlert = false
                    dismiss()
                }
            }
        ))
    }

    private func submitFeedback() {
        guard !isSubmitting else { return }

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            validationMessage = AppStrings.Feedback.messageRequired
            submitError = nil
            return
        }

        guard let user = authState.user, authState.isAuthenticated else {
            validationMessage = GuideCategoryPresentation.feedbackAuthRequiredMessage
            submitError = .permissionDenied
            return
        }

        let now = Date()
        let feedback = FeedbackItem(
            id: UUID().uuidString,
            type: selectedKind.feedbackType,
            subject: "Guide • \(material.id) • \(material.title)",
            message: trimmedMessage,
            status: .open,
            createdAt: now,
            updatedAt: now,
            userId: user.id,
            userDisplayName: user.preferredDisplayName,
            ownerReply: nil,
            repliedAt: nil,
            repliedByUserId: nil,
            lastMessageText: trimmedMessage,
            lastMessageAt: now,
            lastMessageByUserId: user.id,
            lastMessageByRole: .user,
            unreadForOwner: true,
            unreadForUser: false
        )

        validationMessage = nil
        submitError = nil
        isSubmitting = true

        Task {
            do {
                try await repository.submitFeedback(feedback)
                await MainActor.run {
                    isSubmitting = false
                    showsSuccessAlert = true
                }
            } catch let appError as AppError {
                await MainActor.run {
                    isSubmitting = false
                    submitError = appError
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    submitError = .unknown
                }
            }
        }
    }
}
